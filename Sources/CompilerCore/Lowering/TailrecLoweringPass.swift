import Foundation

/// Label base for tailrec loop-head labels, chosen to avoid collision
/// with user labels and coroutine dispatch labels.
let tailrecLoopLabelBase: Int32 = 9000

final class TailrecLoweringPass: LoweringPass {
    static let name = "TailrecLowering"

    private struct TailrecFunctionIdentity {
        let symbol: SymbolID
        let name: InternedString
    }

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        for decl in module.arena.declarations {
            if case let .function(function) = decl, function.isTailrec {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        var nextLoopLabel = tailrecLoopLabelBase

        module.arena.transformFunctions { function in
            guard function.isTailrec else { return function }

            // Avoid label collision: scan the function's existing labels and
            // ensure the generated loop-head label is strictly greater.
            let maxExistingLabel = function.body.compactMap { instruction -> Int32? in
                if case let .label(id) = instruction { return id }
                return nil
            }.max() ?? (tailrecLoopLabelBase - 1)

            let loopLabel = max(nextLoopLabel, maxExistingLabel + 1)
            nextLoopLabel = loopLabel + 1

            let functionIdentity = TailrecFunctionIdentity(
                symbol: function.symbol,
                name: function.name
            )
            var updated = function
            updated.replaceBody(rewriteTailCalls(
                body: function.body,
                functionIdentity: functionIdentity,
                params: function.params,
                loopLabel: loopLabel,
                arena: module.arena
            ))
            // Reset instructionLocations to match the new body length.
            // The rewrite changes instruction count, so the old parallel
            // array is stale.  Use the function-level sourceRange as a
            // conservative location for every synthesised instruction.
            updated.replaceInstructionLocations(Array(
                repeating: function.sourceRange,
                count: updated.body.count
            ))
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Check whether a `$default` stub call can be safely optimized into
    /// a tailrec loop.  Returns `true` if the call is NOT a `$default`
    /// stub, or if it IS a `$default` stub whose mask is statically
    /// resolvable and equal to 0 (all arguments explicitly provided).
    ///
    /// Returns `false` (skip optimization) when:
    ///  - the mask could not be resolved statically (nil), or
    ///  - the mask is non-zero (some params use defaults).
    /// A non-zero mask means the `$default` stub would evaluate default
    /// expressions to fill in missing arguments.  At this lowering stage
    /// we don't have access to those default expressions, so keeping the
    /// parameter's value from the previous iteration would silently
    /// miscompile.
    private func canOptimizeDefaultStubCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity,
        arguments: [KIRExprID],
        body: [KIRInstruction],
        callIndex: Int,
        arena: KIRArena
    ) -> (canOptimize: Bool, defaultMask: Int64?) {
        let isDefault = isDefaultStubCall(symbol: symbol, functionIdentity: functionIdentity)
        guard isDefault else {
            return (canOptimize: true, defaultMask: nil)
        }
        let mask = extractDefaultMask(
            arguments: arguments, body: body, callIndex: callIndex, arena: arena
        )
        guard let mask, mask == 0 else {
            return (canOptimize: false, defaultMask: mask)
        }
        return (canOptimize: true, defaultMask: mask)
    }

    /// Rewrite a tailrec function body:
    /// 1. Insert a loop-head label at the start of the body (index 0).
    /// 2. Replace `call(self, args) + returnValue(result)` with
    ///    parameter reassignment (`copy`) + `jump(loopLabel)`.
    /// 3. Also handle Unit-returning tail calls (`call + returnUnit`).
    private func rewriteTailCalls(
        body: [KIRInstruction],
        functionIdentity: TailrecFunctionIdentity,
        params: [KIRParameter],
        loopLabel: Int32,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count + 2)
        let loopInsertIndex = loopEntryIndex(body: body, params: params)
        let canonicalParamExprs = canonicalParameterExprs(
            body: Array(body[..<loopInsertIndex]),
            params: params
        )
        if loopInsertIndex > 0 {
            result.append(contentsOf: body[..<loopInsertIndex])
        }
        result.append(.label(loopLabel))

        // Pre-compute receiver offset once per function instead of per
        // call site.  The receiver is a function-level property, so this
        // avoids repeated SyntheticSymbolScheme lookups when a function
        // contains multiple tail-call rewrites.
        let receiverOffset: Int = {
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(
                for: functionIdentity.symbol
            )
            return (!params.isEmpty && params[0].symbol == receiverSymbol) ? 1 : 0
        }()

        var instructionIndex = loopInsertIndex
        var emittedTailJump = false
        while instructionIndex < body.count {
            let instruction = body[instructionIndex]

            // Skip beginBlock/endBlock — NormalizeBlocksPass may or may not
            // have removed these already; either way we don't need them for
            // the loop-head approach.
            if case .beginBlock = instruction {
                result.append(instruction)
                instructionIndex += 1
                continue
            }

            // --- Value-returning tail call: call(self, args) -> result, then returnValue(result) ---
            if case let .call(symbol, _, arguments, callResult?, _, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, functionIdentity: functionIdentity),
               instructionIndex + 1 < body.count,
               isReturnOfResult(body[instructionIndex + 1], callResult: callResult)
            {
                let check = canOptimizeDefaultStubCall(
                    symbol: symbol, functionIdentity: functionIdentity,
                    arguments: arguments, body: body,
                    callIndex: instructionIndex, arena: arena
                )
                guard check.canOptimize else {
                    result.append(instruction)
                    instructionIndex += 1
                    continue
                }
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    canonicalParamExprs: canonicalParamExprs,
                    defaultMask: check.defaultMask,
                    receiverOffset: receiverOffset,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                emittedTailJump = true
                instructionIndex += 2
                continue
            }

            // --- Unit-returning tail call: call(self, args, nil), then returnUnit ---
            if case let .call(symbol, _, arguments, nil, _, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, functionIdentity: functionIdentity),
               instructionIndex + 1 < body.count,
               isReturnUnitInstruction(body[instructionIndex + 1])
            {
                let check = canOptimizeDefaultStubCall(
                    symbol: symbol, functionIdentity: functionIdentity,
                    arguments: arguments, body: body,
                    callIndex: instructionIndex, arena: arena
                )
                guard check.canOptimize else {
                    result.append(instruction)
                    instructionIndex += 1
                    continue
                }
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    canonicalParamExprs: canonicalParamExprs,
                    defaultMask: check.defaultMask,
                    receiverOffset: receiverOffset,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                emittedTailJump = true
                instructionIndex += 2
                continue
            }

            result.append(instruction)
            instructionIndex += 1
        }

        // Safety: if we emitted a jump but somehow the label is missing
        // (should not happen with the unconditional insert above), leave
        // the body unchanged to avoid producing invalid KIR.
        if emittedTailJump, !result.contains(where: { if case .label(loopLabel) = $0 { return true }; return false }) {
            return body
        }

        return result
    }

    /// Check if a call instruction targets the function being optimized.
    /// Matches by exact symbol identity **or** the `$default` stub variant
    /// generated by `SyntheticSymbolScheme`.  When a recursive call uses
    /// default arguments, the KIR emitter routes through `foo$default`
    /// which carries a different symbol; without this check, tailrec
    /// optimization would miss those calls (LOWER-005).
    private func isSelfRecursiveCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        guard let symbol else { return false }
        if symbol == functionIdentity.symbol { return true }
        let defaultStub = SyntheticSymbolScheme.defaultStubSymbol(for: functionIdentity.symbol)
        return symbol == defaultStub
    }

    /// Check whether the call symbol is the `$default` stub variant (not
    /// the original function symbol itself).
    private func isDefaultStubCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        guard let symbol else { return false }
        return symbol == SyntheticSymbolScheme.defaultStubSymbol(for: functionIdentity.symbol)
    }

    /// Extract the compile-time default mask from a `$default` stub call's
    /// arguments.  The mask is always the last argument and is expected to
    /// be a constant integer literal.  Returns `nil` if the mask cannot be
    /// determined statically.
    ///
    /// The `callIndex` parameter limits the slow-path scan to instructions
    /// that precede the call site, so we only pick up definitions that
    /// dominate the use.
    private func extractDefaultMask(
        arguments: [KIRExprID],
        body: [KIRInstruction],
        callIndex: Int,
        arena: KIRArena
    ) -> Int64? {
        guard let maskExprID = arguments.last else { return nil }
        // Fast path: check the arena expression directly.
        if let exprKind = arena.expr(maskExprID),
           case let .intLiteral(mask) = exprKind
        {
            return mask
        }
        // Slow path: scan backwards from the call site for the closest
        // preceding constValue that defines the mask.  Scanning only
        // instructions before `callIndex` ensures the definition dominates
        // the use.  Stop at control-flow boundaries (labels, jumps,
        // conditional branches) to stay within the same basic block —
        // a linear backward scan cannot guarantee dominance across
        // control flow.
        for i in stride(from: callIndex - 1, through: 0, by: -1) {
            let inst = body[i]
            // Stop at control-flow boundaries to ensure we stay in the
            // same basic block.  Definitions across branches may not
            // dominate the call site.
            switch inst {
            case .label, .jump, .jumpIfEqual, .jumpIfNotNull:
                return nil
            default:
                break
            }
            if case let .constValue(result, .intLiteral(value)) = inst,
               result == maskExprID
            {
                return value
            }
        }
        return nil
    }

    /// Check if the next instruction is `returnValue(r)` where `r` matches
    /// the call result.
    private func isReturnOfResult(
        _ instruction: KIRInstruction, callResult: KIRExprID?
    ) -> Bool {
        guard let callResult else { return false }
        if case let .returnValue(value) = instruction, value == callResult {
            return true
        }
        return false
    }

    private func isReturnUnitInstruction(_ instruction: KIRInstruction) -> Bool {
        if case .returnUnit = instruction {
            return true
        }
        return false
    }

    /// Emit `copy` instructions to reassign the function parameters from
    /// the recursive call arguments.  Also propagates expression types for
    /// the newly created temporaries and symbol refs.
    ///
    /// When `defaultMask` is non-nil, it is expected to be 0 (all
    /// arguments explicitly provided).  The caller skips tailrec for
    /// non-zero masks because we cannot inline default expressions at
    /// this lowering stage.  The mask-bit logic below is retained as
    /// defense-in-depth and will become useful when default-expression
    /// inlining is implemented.
    ///
    /// The default mask bits are 0-indexed on *value parameter* positions
    /// (excluding the receiver).  When the function has a receiver
    /// parameter (detected via `SyntheticSymbolScheme`), the receiver
    /// occupies index 0 in both `params` and `arguments` but is not
    /// counted in the mask.  `receiverOffset` (0 or 1) is pre-computed
    /// once per function in `rewriteTailCalls` and passed in here so
    /// that we avoid repeated `SyntheticSymbolScheme` lookups when a
    /// function has multiple tail-call sites.
    private func emitParameterReassignment(
        arguments: [KIRExprID],
        params: [KIRParameter],
        canonicalParamExprs: [SymbolID: KIRExprID],
        defaultMask: Int64? = nil,
        receiverOffset: Int,
        arena: KIRArena,
        result: inout [KIRInstruction]
    ) {
        // Only copy the first `params.count` arguments; $default calls
        // carry trailing reified-type tokens and a mask that must not
        // participate in parameter reassignment.
        let effectiveCount = min(arguments.count, params.count)

        // First, copy arguments into fresh temporaries to avoid
        // overwriting a parameter that is used in a later argument expression.
        var temporaries: [KIRExprID] = []
        temporaries.reserveCapacity(effectiveCount)
        for i in 0 ..< effectiveCount {
            // Skip sentinel arguments whose default mask bit is set.
            // The mask is indexed on value-parameter positions (excluding
            // the receiver), so subtract `receiverOffset`.  When the
            // mask bit index exceeds Int64.bitWidth (>= 64 value params),
            // we conservatively treat the argument as non-defaulted;
            // this is safe because functions with that many defaulted
            // parameters would use multiple mask words, and the caller
            // already skips tailrec when the mask is unresolvable.
            if let mask = defaultMask {
                let maskBitIndex = i - receiverOffset
                if maskBitIndex >= 0 {
                    if maskBitIndex >= Int64.bitWidth {
                        // Out-of-range bit index — conservatively treat
                        // as non-defaulted (copy the argument through).
                    } else if (mask >> maskBitIndex) & 1 != 0 {
                        temporaries.append(.invalid)
                        continue
                    }
                }
            }
            let arg = arguments[i]
            let argType = arena.exprType(arg)
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: argType)
            result.append(.copy(from: arg, to: temp))
            temporaries.append(temp)
        }

        // Then, assign temporaries to parameter symbol refs.
        for (index, param) in params.enumerated() {
            guard index < temporaries.count else { break }
            let temp = temporaries[index]
            // Skip parameters that were defaulted (sentinel).
            guard temp != .invalid else { continue }
            let paramExpr = canonicalParamExprs[param.symbol]
                ?? arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            result.append(.copy(from: temp, to: paramExpr))
        }
    }

    private func canonicalParameterExprs(
        body: [KIRInstruction],
        params: [KIRParameter]
    ) -> [SymbolID: KIRExprID] {
        let parameterSymbols = Set(params.map(\.symbol))
        var result: [SymbolID: KIRExprID] = [:]
        for instruction in body {
            guard case let .constValue(exprID, .symbolRef(symbol)) = instruction,
                  parameterSymbols.contains(symbol),
                  result[symbol] == nil
            else {
                continue
            }
            result[symbol] = exprID
        }
        return result
    }

    private func loopEntryIndex(body: [KIRInstruction], params: [KIRParameter]) -> Int {
        let parameterSymbols = Set(params.map(\.symbol))
        var index = 0
        if index < body.count, case .beginBlock = body[index] {
            index += 1
        }
        while index < body.count {
            guard case let .constValue(_, .symbolRef(symbol)) = body[index],
                  parameterSymbols.contains(symbol)
            else {
                break
            }
            index += 1
        }
        return index
    }
}
