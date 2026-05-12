/// Helpers used by `ExprLowerer.lowerExpr`:
/// mutable-capture cell ensure/load/store, finally-block inlining
/// (for return / break / continue), and the lateinit-read wrapping
/// helper.
///
/// Split out from `ExprLowerer+ControlFlowAndBlocks.swift`.
extension ExprLowerer {
    func ensureMutableCaptureCell(
        for symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if let existingCell = driver.ctx.mutableCaptureCell(for: symbol) {
            return existingCell
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol),
              semanticSymbol.kind == .local,
              semanticSymbol.flags.contains(.mutable),
              let currentValue = driver.ctx.localValue(for: symbol)
        else {
            return nil
        }
        return emitMutableCaptureCellInitialization(
            driver: driver,
            symbol: symbol,
            currentValue: currentValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func loadMutableCaptureCellValue(
        symbol: SymbolID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let cellExpr = driver.ctx.mutableCaptureCell(for: symbol) else {
            return nil
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [cellExpr, zeroExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func storeMutableCaptureCellValue(
        _ valueID: KIRExprID,
        for symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        guard let cellExpr = driver.ctx.mutableCaptureCell(for: symbol) else {
            return false
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let setResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: arena.exprType(valueID) ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [cellExpr, zeroExpr, valueID],
            result: setResult,
            canThrow: false,
            thrownResult: nil
        ))
        return true
    }

    // MARK: - Finally Block Inlining Helper (CODE-001)

    /// Inline enclosing finally blocks before a control-flow transfer.
    ///
    /// For `return`, all enclosing finally blocks are inlined (a return always
    /// exits every enclosing try scope).  For `break`/`continue`, use
    /// `inlineFinallyBlocksForBreakOrContinue` instead, which only inlines
    /// finally blocks whose try scope is exited by the jump.
    ///
    /// **Re-entrancy guard**: Each finally block is lowered with the stack
    /// trimmed so that it (and any inner finally blocks already processed)
    /// are excluded.  This prevents infinite recursion when a finally body
    /// itself contains return/break/continue, because lowering that nested
    /// control-flow will only see *outer* finally blocks on the stack.
    ///
    /// **Exception routing (CODE-001)**: Each inlined finally block is
    /// lowered into a separate instruction buffer and wrapped with
    /// `appendThrowAwareInstructions` using its own rethrow label.  If
    /// the inlined finally body throws, the exception propagates outward
    /// via `.rethrow` rather than being caught by the enclosing try-catch
    /// dispatch, matching Kotlin semantics.
    func inlineAllEnclosingFinallyBlocks(
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        let blocks = driver.ctx.enclosingFinallyBlocks()
        // For `return`, all enclosing finally blocks are inlined.  The blocks
        // array corresponds 1:1 to finallyBlockStack, so stackIndex == array index.
        let indexedBlocks = blocks.enumerated().map { (exprID: $0.element, stackIndex: $0.offset) }
        inlineFinallyBlocks(
            indexedBlocks,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    /// Inline only the finally blocks whose try scope is exited by a
    /// `break` or `continue` targeting the given loop label.
    ///
    /// A finally block is skipped when the target loop was pushed *after*
    /// the try-finally scope was entered (meaning the loop is nested inside
    /// the try body and the break/continue stays within the try scope).
    func inlineFinallyBlocksForBreakOrContinue(
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        let targetDepth = driver.ctx.breakTargetLoopDepth(for: label)
        let indexedBlocks = driver.ctx.enclosingFinallyBlocksForBreakOrContinue(targetLoopDepth: targetDepth)
        inlineFinallyBlocks(
            indexedBlocks.map { (exprID: $0.exprID, stackIndex: $0.stackIndex) },
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    /// Core finally-inlining logic shared by return and break/continue paths.
    ///
    /// Each entry in `blocks` contains a `stackIndex` — the original position
    /// of the finally block in `finallyBlockStack`.  This is used with
    /// `withFinallyStackDepth` to trim the stack to the correct depth so that
    /// re-entrant lowering (e.g., a `return` inside an inlined finally) only
    /// sees the outer finally blocks that precede it in the original stack.
    ///
    /// For `return`, the indices are 0..<count (the full stack).  For
    /// `break`/`continue`, only a filtered subset is passed, and the indices
    /// are the *original* positions — not sequential starting from 0.
    func inlineFinallyBlocks(
        _ blocks: [(exprID: ExprID, stackIndex: Int)],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        guard !blocks.isEmpty else { return }

        let intType = sema.types.make(.primitive(.int, .nonNull))

        // Process innermost-first (reversed) so that the stack is trimmed
        // correctly: for each finally block, we temporarily set the stack
        // depth to its original stack index so that re-entrant lowering only
        // sees outer blocks.
        //
        // CODE-001 fix: Each inlined finally block is lowered into a separate
        // instruction buffer, then wrapped with appendThrowAwareInstructions
        // that routes exceptions to a *rethrow* label instead of the
        // enclosing try-catch dispatch.  This matches Kotlin semantics where
        // an exception thrown from a finally block propagates outward (to the
        // next outer exception handler) rather than being caught by the
        // try-catch that owns the finally.
        for i in stride(from: blocks.count - 1, through: 0, by: -1) {
            let entry = blocks[i]
            var finallyInstructions: [KIRInstruction] = []
            driver.ctx.withFinallyStackDepth(entry.stackIndex) {
                _ = lowerExpr(
                    entry.exprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &finallyInstructions
                )
            }

            // Check whether the finally body contains any call / virtualCall
            // instructions that could throw.  If it does, wrap with throw-aware
            // routing; otherwise append directly to avoid unnecessary labels
            // and exception-slot overhead.
            let hasThrowableCall = finallyInstructions.contains { (instr: KIRInstruction) -> Bool in
                switch instr {
                case .call(_, _, _, _, _, _, _, _),
                     .virtualCall(_, _, _, _, _, _, _, _),
                     .rethrow:
                    return true
                default:
                    return false
                }
            }

            if hasThrowableCall {
                // Allocate per-inlined-finally exception slots so that any
                // throw inside the finally body is captured and rethrown
                // outward rather than routed to the enclosing try's catch.
                let exSlot = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                let exTypeSlot = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
                )
                let nullValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                let zeroValue = arena.appendExpr(.intLiteral(0), type: intType)

                // Wrap the entire finally guard region with sentinels so
                // that an outer appendThrowAwareInstructions pass does not
                // double-wrap the already-routed exception handling.
                instructions.append(.beginFinallyGuard)

                instructions.append(.constValue(result: nullValue, value: .null))
                instructions.append(.constValue(result: zeroValue, value: .intLiteral(0)))
                instructions.append(.copy(from: nullValue, to: exSlot))
                instructions.append(.copy(from: zeroValue, to: exTypeSlot))

                let rethrowLabel = driver.ctx.makeLoopLabel()
                let afterRethrowLabel = driver.ctx.makeLoopLabel()

                driver.controlFlowLowerer.appendThrowAwareInstructions(
                    finallyInstructions,
                    exceptionSlot: exSlot,
                    exceptionTypeSlot: exTypeSlot,
                    thrownTarget: rethrowLabel,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.jump(afterRethrowLabel))

                // Rethrow block: propagates the exception outward.
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: exSlot))

                instructions.append(.label(afterRethrowLabel))
                instructions.append(.endFinallyGuard)
            } else {
                // No throwable calls — append the finally body directly.
                instructions.append(contentsOf: finallyInstructions)
            }
        }
    }

    func wrapLateinitReadIfNeeded(
        _ valueExpr: KIRExprID,
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let symbolInfo = sema.symbols.symbol(symbol),
              symbolInfo.flags.contains(.lateinitProperty)
        else {
            return valueExpr
        }
        let propertyNameExpr = arena.appendExpr(
            .stringLiteral(symbolInfo.name),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        instructions.append(.constValue(result: propertyNameExpr, value: .stringLiteral(symbolInfo.name)))
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: arena.exprType(valueExpr) ?? sema.types.anyType
        )
        let thrownResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.nullableAnyType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_lateinit_get_or_throw"),
            arguments: [valueExpr, propertyNameExpr],
            result: result,
            canThrow: true,
            thrownResult: thrownResult
        ))
        return result
    }

}
