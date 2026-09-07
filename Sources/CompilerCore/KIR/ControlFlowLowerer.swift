
final class ControlFlowLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    private func resolvedLoopCallee(
        for binding: CallBinding,
        sema: SemaModule,
        interner: StringInterner,
        fallback: String
    ) -> InternedString {
        if let linkName = sema.symbols.externalLinkName(for: binding.chosenCallee),
           !linkName.isEmpty {
            return interner.intern(linkName)
        }
        if let symbol = sema.symbols.symbol(binding.chosenCallee) {
            return symbol.name
        }
        return interner.intern(fallback)
    }

    /// Emit a member call for a for-loop iterator/hasNext/next invocation.
    /// Uses virtual dispatch when the chosen callee is a non-external member
    /// of an interface or class, falling back to a direct `.call` otherwise.
    private func emitForLoopMemberCall(
        callBinding: CallBinding,
        fallback: String,
        receiverExpr: ExprID?,
        receiverID: KIRExprID,
        runtimeCalleeOverride: String? = nil,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        if let runtimeCalleeOverride {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeCalleeOverride),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return
        }
        let calleeName = resolvedLoopCallee(for: callBinding, sema: sema, interner: interner, fallback: fallback)
        // Virtual dispatch is only possible when we have a source expression
        // whose static type can be used to resolve an itable/vtable slot.
        // hasNext()/next() on the stdlib Iterator use runtime itable lookup,
        // so they continue to use a direct .call when there is no receiver expr.
        //
        // Member functions (class/interface/object) receive their `this` through
        // the virtual call receiver; extension functions receive it as the first
        // explicit argument, so tryEmitVirtualDispatch strips it. Pass the
        // argument list that matches this contract to avoid double receivers.
        let isClassMember: Bool
        let chosenCallee = callBinding.chosenCallee
        if let parentSymbolID = sema.symbols.parentSymbol(for: chosenCallee),
           let parentSymbol = sema.symbols.symbol(parentSymbolID) {
            switch parentSymbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                isClassMember = true
            default:
                isClassMember = false
            }
        } else {
            isClassMember = false
        }
        let virtualArguments: [KIRExprID] = isClassMember ? [] : [receiverID]
        if let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
            chosenCallee: callBinding.chosenCallee,
            calleeName: calleeName,
            receiverExpr: receiverExpr,
            loweredReceiverID: receiverID,
            isSuperCall: false,
            finalArguments: virtualArguments,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner
        ) {
            instructions.append(virtualInstruction)
        } else {
            instructions.append(.call(
                symbol: callBinding.chosenCallee,
                callee: calleeName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    /// When true, no instructions should follow in the same linear block.
    func isTerminatedExpr(_ exprID: KIRExprID, arena: KIRArena, sema: SemaModule) -> Bool {
        arena.exprType(exprID) == sema.types.nothingType
    }

    func lowerForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // KSP-678: `for (v in channel)` lowers through the bundled Kotlin
        // `Channel<T>.iterator()` operator (Channels.kt) via the custom-iterator
        // path below, the same way ranges do, instead of a channel-specific
        // structural lowering.
        let iterableType = sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType
        // ARCH-012: IntRange has a fixed positive step of one, so a proven
        // closed Int range can use an i64 induction variable without changing
        // the progression iterator semantics. Keep the BUG-198 runtime path
        // below for Long/Char/progression and other signed range shapes.
        if isBuiltInIntRange(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        ) {
            return lowerBuiltInIntRangeForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        // BUG-198: Keep the KSP-452 source iterator as the semantic contract, but
        // use a direct runtime loop for the closed signed ranges that the compiler
        // can prove are built-in. The generic iterator path allocates a source
        // iterator object and pays two levels of dispatch on every element. This
        // fast path is deliberately restricted to compiler-marked built-in range
        // expressions and nominal range classes, so custom operators and
        // interface-typed iterables retain their semantics.
        if isBuiltInSignedRange(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        ) {
            return lowerBuiltInSignedRangeForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        if let loopBinding = sema.bindings.loopIterationBinding(for: exprID) {
            return lowerCustomForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                loopBinding: loopBinding,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // DEBT-KIR-005: Array types (Array<T>, IntArray, ByteArray, etc.) have no
        // real (non-synthetic) `iterator()` member, so bindLoopIterationOperators
        // never produces a LoopIterationBinding for them (see
        // ControlFlowTypeChecker.bindLoopIterationOperators, which filters out
        // `.synthetic` iterator() candidates). Without that binding they would
        // otherwise fall into the range-iterator intrinsics below, which
        // silently misinterpret the array object as a range and never enter
        // the loop body (hasNext reads unrelated memory as the range bound).
        // Lower directly to an index-based loop instead, matching how arrays
        // are already indexed everywhere else (__kk_array_size / kk_array_get_inbounds).
        if ReceiverClassifier(sema: sema, interner: interner)
            .isArrayLikeType(sema.types.makeNonNullable(iterableType))
        {
            return lowerArrayForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // BUG-167: Iterables whose `iterator()` can only be resolved at runtime
        // (see usesDynamicIteratorDispatch) get no LoopIterationBinding from
        // Sema, so — like arrays above — they would fall into the range
        // intrinsics below, which reinterpret the collection object as a range
        // and yield garbage elements (or none at all). Lower them like an
        // explicit `val it = xs.iterator()` loop instead.
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)
        let isIterableInterfaceResult = ReceiverClassifier(sema: sema, interner: interner)
            .isIterableLikeType(nonNullIterableType)
        if usesDynamicIteratorDispatch(iterableType, sema: sema, interner: interner)
            || isIterableInterfaceResult
        {
            return lowerDynamicIteratorForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let isUIntRangeLike = sema.bindings.isUIntRangeExpr(iterableExpr) || nonNullIterableType == sema.types.uintType
        let isULongRangeLike = sema.bindings.isULongRangeExpr(iterableExpr) || nonNullIterableType == sema.types.ulongType

        // STDLIB-OP-032: Resolve custom operator fun iterator() on the iterable type.
        // If the iterable has a user-defined iterator(), dispatch to it instead of
        // the built-in kk_range_iterator runtime function.
        let customIterator = resolveCustomIteratorOperator(
            iterableType: iterableType,
            sema: sema,
            interner: interner
        ) ?? resolveDirectRangeIteratorOperator(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        )

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        if let customIter = customIterator {
            let calleeName: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.iteratorSymbol),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.iteratorSymbol) {
                sym.name
            } else {
                interner.intern("iterator")
            }
            instructions.append(.call(
                symbol: customIter.iteratorSymbol,
                callee: calleeName,
                arguments: [iterableID],
                result: iteratorID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: isULongRangeLike
                    ? interner.intern("kk_ulong_range_iterator")
                    : (isUIntRangeLike ? interner.intern("kk_uint_range_iterator") : interner.intern("kk_range_iterator")),
                arguments: [iterableID],
                result: iteratorID,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        if let customIter = customIterator {
            let hasNextCallee: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.hasNextSymbol),
                                                   !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.hasNextSymbol) {
                sym.name
            } else {
                interner.intern("hasNext")
            }
            instructions.append(.call(
                symbol: customIter.hasNextSymbol,
                callee: hasNextCallee,
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: isULongRangeLike
                    ? interner.intern("kk_ulong_range_hasNext")
                    : (isUIntRangeLike ? interner.intern("kk_uint_range_hasNext") : interner.intern("kk_range_hasNext")),
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
        }
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        if let customIter = customIterator {
            let nextCallee: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.nextSymbol),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.nextSymbol) {
                sym.name
            } else {
                interner.intern("next")
            }
            instructions.append(.call(
                symbol: customIter.nextSymbol,
                callee: nextCallee,
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: isULongRangeLike
                    ? interner.intern("kk_ulong_range_next")
                    : (isUIntRangeLike ? interner.intern("kk_uint_range_next") : interner.intern("kk_range_next")),
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: false,
                thrownResult: nil
            ))
        }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// ARCH-012: Restrict the LLVM induction-variable loop to the exact
    /// IntRange contract. Direct `..` expressions are represented as an Int
    /// element type plus a semantic range marker, while a value held in an
    /// IntRange variable retains its nominal class type. `until`, `downTo`,
    /// `step`, Long/Char ranges, and unsigned ranges keep their iterator path.
    private func isBuiltInIntRange(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        guard nonNullType != sema.types.uintType,
              nonNullType != sema.types.ulongType,
              nonNullType != sema.types.charType,
              !sema.bindings.isUIntRangeExpr(iterableExpr),
              !sema.bindings.isULongRangeExpr(iterableExpr),
              !sema.bindings.isCharRangeExpr(iterableExpr),
              !sema.bindings.isFloatingPointRangeExpr(iterableExpr)
        else {
            return false
        }

        if case let .binary(op, _, _, _) = ast.arena.expr(iterableExpr), op == .rangeTo {
            return nonNullType == sema.types.intType
                && (sema.bindings.isRangeExpr(iterableExpr)
                    || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast))
        }

        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              isRangeLikeClass(symbol, sema: sema, interner: interner)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "IntRange"
    }

    /// ARCH-012: Lower a proven IntRange to an induction variable. The range
    /// Direct `Int..Int` operands are lowered without a range object; a typed
    /// IntRange is materialized once and its bounds are read once. The loop
    /// body then uses only native comparison/addition instructions. The
    /// explicit last-element flag avoids incrementing Int.MAX_VALUE and also
    /// makes `continue` terminate correctly on the final element.
    private func lowerBuiltInIntRangeForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let firstID: KIRExprID
        let lastID: KIRExprID
        if case let .binary(op, lhs, rhs, _) = ast.arena.expr(iterableExpr), op == .rangeTo {
            // A direct `Int..Int` expression has no observable range object
            // between evaluating its operands and entering the loop.
            firstID = driver.lowerExpr(
                lhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            lastID = driver.lowerExpr(
                rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let iterableID = driver.lowerExpr(
                iterableExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            firstID = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_range_first"),
                arg: iterableID,
                result: firstID,
                into: &instructions
            )
            lastID = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_range_last"),
                arg: iterableID,
                result: lastID,
                into: &instructions
            )
        }

        let currentSlot = arena.appendTemporary(type: intType)
        instructions.append(.copy(from: firstID, to: currentSlot))
        let hasMoreSlot = arena.appendTemporary(type: boolType)
        let trueID = arena.appendExpr(.boolLiteral(true), type: boolType)
        instructions.append(.constValue(result: trueID, value: .boolLiteral(true)))
        instructions.append(.copy(from: trueID, to: hasMoreSlot))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        let lastValueLabel = driver.ctx.makeLoopLabel()
        let bodyLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasMoreSlot, rhs: falseID, target: breakLabel))

        // Compiler-internal aliases are lowered by NativeEmitter to LLVM
        // icmp/add instructions and are never emitted as runtime calls.
        let hasMoreID = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_int_range_induction_le"),
            arguments: [currentSlot, lastID],
            result: hasMoreID,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.jumpIfEqual(lhs: hasMoreID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? intType
        let elementID = arena.appendTemporary(type: loopVarType)
        instructions.append(.copy(from: currentSlot, to: elementID))

        // Do not increment after the final element. This is the same
        // monotonicity/overflow guard as IntProgressionIterator.next().
        instructions.append(.jumpIfEqual(lhs: currentSlot, rhs: lastID, target: lastValueLabel))
        let oneID = arena.appendExpr(.intLiteral(1), type: intType)
        instructions.append(.constValue(result: oneID, value: .intLiteral(1)))
        let nextValueID = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_int_range_induction_add"),
            arguments: [currentSlot, oneID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: nextValueID, to: currentSlot))
        instructions.append(.jump(bodyLabel))

        instructions.append(.label(lastValueLabel))
        instructions.append(.copy(from: falseID, to: hasMoreSlot))
        instructions.append(.label(bodyLabel))

        if let loopVariableSymbol {
            driver.ctx.setLocalValue(elementID, for: loopVariableSymbol)
        }
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// BUG-198: Lowers a proven built-in signed range directly through a small
    /// runtime iterator. The runtime implementation follows the monotonicity and
    /// overflow behavior of `RangeIterators.kt` without exposing that fast path to
    /// explicit `range.iterator()` calls or dynamically typed iterables.
    private func lowerBuiltInSignedRangeForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_iterator"),
            arg: iterableID,
            result: iteratorID,
            into: &instructions
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_hasNext"),
            arg: iteratorID,
            result: hasNextID,
            into: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_next"),
            arg: iteratorID,
            result: nextValueID,
            into: &instructions
        )
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// DEBT-KIR-005: Lowers `for (x in array)` to an index-based loop
    /// (`i = 0; while (i < __kk_array_size(array)) { x = kk_array_get_inbounds(array, i); i += 1; ... }`)
    /// rather than the range-iterator intrinsics used by lowerForExpr's
    /// general path, since arrays have no real `iterator()` member for Sema
    /// to bind (see the DEBT-KIR-005 comment at the lowerForExpr call site).
    /// The index is advanced before the body runs (mirroring how the
    /// iterator-based loop's next() call both reads and advances ahead of
    /// the body) so that `continue` — which jumps back to continueLabel —
    /// re-checks the bound against the already-advanced index.
    private func lowerArrayForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let arrayID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let sizeID = arena.appendTemporary(type: intType)
        emitNonThrowingCall(
            callee: interner.intern("__kk_array_size"),
            arg: arrayID,
            result: sizeID,
            into: &instructions
        )

        let indexSlot = arena.appendTemporary(type: intType)
        let zeroID = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: zeroID, value: .intLiteral(0)))
        instructions.append(.copy(from: zeroID, to: indexSlot))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasMoreID = arena.appendTemporary(type: boolType)
        instructions.append(.binary(op: .lessThan, lhs: indexSlot, rhs: sizeID, result: hasMoreID))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasMoreID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let elementID = arena.appendTemporary(type: loopVarType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [arrayID, indexSlot],
            result: elementID,
            canThrow: false,
            thrownResult: nil
        ))

        let oneID = arena.appendExpr(.intLiteral(1), type: intType)
        instructions.append(.constValue(result: oneID, value: .intLiteral(1)))
        let nextIndexID = arena.appendTemporary(type: intType)
        instructions.append(.binary(op: .add, lhs: indexSlot, rhs: oneID, result: nextIndexID))
        instructions.append(.copy(from: nextIndexID, to: indexSlot))

        if let loopVariableSymbol {
            driver.ctx.setLocalValue(elementID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// BUG-167: True when `for (x in type)` must resolve `iterator()`
    /// dynamically because neither `bindLoopIterationOperators` nor
    /// `resolveCustomIteratorOperator` can bind it: the `kotlin.collections`
    /// iterable interfaces (whose `iterator()` is only a synthetic stub), and
    /// source-declared classes implementing `Iterable` whose `iterator()`
    /// override carries no `.operatorFunction` flag of its own (it inherits
    /// `operator` from the interface declaration). Types that do bind an
    /// iterator — and the concrete runtime-backed collections, which the
    /// collection-literal pass rewrites to their own iterator intrinsics —
    /// never reach here.
    private func usesDynamicIteratorDispatch(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        if sema.types.isSubtype(nonNullType, sema.types.stringType) {
            return false
        }
        if let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol {
            let charSequenceType = sema.types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
            if sema.types.isSubtype(nonNullType, charSequenceType) {
                return false
            }
        }
        if ReceiverClassifier(sema: sema, interner: interner).isIterableInterfaceType(nonNullType) {
            return true
        }
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              !symbol.flags.contains(.synthetic),
              // KSP-697: List (and other migrated collection shells) are now
              // Kotlin source-backed, so their class symbol no longer carries
              // `.synthetic`. Without this check they would be mistaken for an
              // arbitrary non-synthetic Iterable-implementing class and lose the
              // dedicated kk_list_iterator_next fast path below.
              !KnownCompilerNames(interner: interner).isCollectionLikeSymbol(symbol),
              resolveCustomIteratorOperator(
                  iterableType: nonNullType,
                  sema: sema,
                  interner: interner
              ) == nil,
              let iterableSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("collections"),
                  interner.intern("Iterable"),
              ])
        else {
            return false
        }
        return kirTransitiveInterfaceSupertypes(of: classType.classSymbol, sema: sema)
            .contains(iterableSymbol)
    }

    /// BUG-167/KSP-998: Lowers `for (x in iterable)` for an iterable whose
    /// `iterator()` is only known at runtime. The throwing Iterable bridge keeps
    /// iterator acquisition lazy and preserves source exceptions for the
    /// enclosing Kotlin try/catch. `hasNext()`/`next()` go through the generic
    /// `kk_iterator_*` intrinsics, which handle every iterator representation.
    private func lowerDynamicIteratorForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_iterable_iterator"),
            arguments: [iterableID],
            result: iteratorID,
            canThrow: true,
            thrownResult: thrownResult
        ))
        let continueAfterIteratorLabel = driver.ctx.makeLoopLabel()
        let rethrowIteratorLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowIteratorLabel))
        instructions.append(.jump(continueAfterIteratorLabel))
        instructions.append(.label(rethrowIteratorLabel))
        instructions.append(.rethrow(value: thrownResult))
        instructions.append(.label(continueAfterIteratorLabel))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitThrowingCall(
            callee: interner.intern("kk_iterator_hasNext"),
            arg: iteratorID,
            result: hasNextID,
            into: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        if let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
            for: loopVarType,
            types: sema.types,
            requireNonNull: true
        ) {
            let boxedID = arena.appendTemporary(type: sema.types.anyType)
            emitThrowingCall(
                callee: interner.intern("kk_iterator_next"),
                arg: iteratorID,
                result: boxedID,
                into: &instructions
            )
            emitNonThrowingCall(
                callee: unboxCallee,
                arg: boxedID,
                result: nextValueID,
                into: &instructions
            )
        } else {
            emitThrowingCall(
                callee: interner.intern("kk_iterator_next"),
                arg: iteratorID,
                result: nextValueID,
                into: &instructions
            )
        }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func lowerCustomForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        loopBinding: LoopIterationBinding,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let iteratorID: KIRExprID
        if let iteratorCall = loopBinding.iteratorCall {
            let iteratorTemp = arena.appendTemporary(type: loopBinding.iteratorType)
            emitForLoopMemberCall(
                callBinding: iteratorCall,
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorTemp,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            iteratorID = iteratorTemp
        } else {
            // The iterable value is itself an Iterator; no iterator() call is needed.
            iteratorID = iterableID
        }
        let listIteratorFastPath = concreteListIteratorFastPath(
            loopBinding: loopBinding,
            iterableType: sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitForLoopMemberCall(
            callBinding: loopBinding.hasNextCall,
            fallback: "hasNext",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.hasNext,
            result: hasNextID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let nextValueID = arena.appendTemporary(type: loopBinding.elementType)
        emitForLoopMemberCall(
            callBinding: loopBinding.nextCall,
            fallback: "next",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.next,
            result: nextValueID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Preserve the concrete List for-loop fast path after Collection.iterator
    /// becomes source-backed. Collection/Iterable receivers must keep the
    /// generic iterator ABI because their runtime box can be list- or set-backed.
    private func concreteListIteratorFastPath(
        loopBinding: LoopIterationBinding,
        iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (hasNext: String, next: String)? {
        guard let iteratorCall = loopBinding.iteratorCall,
              interner.resolve(
                  resolvedLoopCallee(
                      for: iteratorCall,
                      sema: sema,
                      interner: interner,
                      fallback: "iterator"
                  )
              ) == "kk_list_iterator",
              MemberRuntimeDispatch.collectionReceiverKind(
                  receiverType: iterableType,
                  sema: sema,
                  interner: interner
              ) == .list
        else {
            return nil
        }
        return ("kk_list_iterator_hasNext", "kk_list_iterator_next")
    }

    // MARK: - Custom Iterator Resolution (STDLIB-OP-032)

    /// Restricts BUG-198 to the signed range/progression classes and direct
    /// signed range expressions. Unsigned ranges, OpenEndRange, custom classes,
    /// and interface-typed values must continue through their existing lowering.
    private func isBuiltInSignedRange(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        if sema.bindings.isUIntRangeExpr(iterableExpr)
            || sema.bindings.isULongRangeExpr(iterableExpr)
            || nonNullType == sema.types.uintType
            || nonNullType == sema.types.ulongType {
            return false
        }
        if sema.bindings.isRangeExpr(iterableExpr)
            || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
            || isBuiltInRangeMemberCall(iterableExpr, ast: ast, sema: sema, interner: interner) {
            if nonNullType == sema.types.intType
                || nonNullType == sema.types.longType
                || nonNullType == sema.types.charType
            {
                return true
            }
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
                  isRangeLikeClass(symbol, sema: sema, interner: interner)
            else {
                return false
            }
            let shortName = interner.resolve(symbol.name)
            return shortName == "IntRange"
                || shortName == "IntProgression"
                || shortName == "LongRange"
                || shortName == "LongProgression"
                || shortName == "CharRange"
                || shortName == "CharProgression"
        }
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              isRangeLikeClass(symbol, sema: sema, interner: interner)
        else {
            return false
        }
        let shortName = interner.resolve(symbol.name)
        return shortName == "IntRange"
            || shortName == "IntProgression"
            || shortName == "LongRange"
            || shortName == "LongProgression"
            || shortName == "CharRange"
            || shortName == "CharProgression"
    }

    /// `downTo` and `step` are represented as member-call nodes by the parser
    /// even though they are built-in range constructors. Use their resolved
    /// runtime links so a source-defined function with the same name is not
    /// mistaken for a built-in range.
    private func isBuiltInRangeMemberCall(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .memberCall(receiver, callee, _, _, _) = ast.arena.expr(exprID),
              ["until", "rangeUntil", "downTo", "step"].contains(interner.resolve(callee)),
              let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee,
              let linkName = sema.symbols.externalLinkName(for: chosen)
        else {
            return false
        }
        let signedLinks = [
            "__kk_op_rangeUntil",
            "__kk_op_downTo",
            "__kk_op_step",
            "__kk_char_range_step",
        ]
        guard signedLinks.contains(linkName) else {
            return false
        }
        if linkName == "__kk_op_step" || linkName == "__kk_char_range_step" {
            return isBuiltInSignedRange(
                iterableExpr: receiver,
                iterableType: sema.bindings.exprType(for: receiver) ?? sema.types.anyType,
                ast: ast,
                sema: sema,
                interner: interner
            )
        }
        return true
    }

    /// Resolved custom iterator operator chain: iterator(), hasNext(), next().
    private struct CustomIteratorResolution {
        let iteratorSymbol: SymbolID
        let hasNextSymbol: SymbolID
        let nextSymbol: SymbolID
    }

    /// Returns true when the class symbol is one of the built-in Range / Progression
    /// classes in `kotlin.ranges` that now provide bundled Kotlin `iterator()`
    /// operators. These synthetic classes are allowed to resolve a custom iterator
    /// so that `for-in` over a range is lowered through `.iterator()` instead of
    /// the legacy `kk_range_iterator` runtime path.
    private func isRangeLikeClass(_ classSymbol: SemanticSymbol, sema: SemaModule, interner: StringInterner) -> Bool {
        guard classSymbol.fqName.count >= 2,
              interner.resolve(classSymbol.fqName[0]) == "kotlin",
              interner.resolve(classSymbol.fqName[1]) == "ranges"
        else {
            return false
        }
        let shortName = interner.resolve(classSymbol.fqName.last!)
        switch shortName {
        case "IntRange", "LongRange", "CharRange",
             "IntProgression", "LongProgression", "CharProgression":
            return true
        default:
            return false
        }
    }

    /// Looks for a non-synthetic bundled `operator fun Receiver.<name>()` extension
    /// (no value parameters) declared in the same package as the receiver's class.
    /// This is how KSP-312's `RangeIterators.kt` and KSP-678's `Channels.kt`
    /// iterator-layer operators are discovered for `for-in` lowering, since
    /// extension operators are not found through class-hierarchy member lookup.
    private func resolveBundledOperatorExtension(
        named name: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let classSymbol = resolveClassTypeSymbol(nonNullReceiverType, sema: sema)?.1
        let isCharSequenceLike = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
            || (sema.types.charSequenceInterfaceSymbol.map { symbol in
                let charSequenceType = sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
                return sema.types.isSubtype(nonNullReceiverType, charSequenceType)
            } ?? false)
        guard isCharSequenceLike || classSymbol != nil else {
            return nil
        }
        var packageFQNames: [[InternedString]] = classSymbol.map { [Array($0.fqName.dropLast())] } ?? []
        if isCharSequenceLike {
            let textPackage = [interner.intern("kotlin"), interner.intern("text")]
            if !packageFQNames.contains(textPackage) {
                packageFQNames.append(textPackage)
            }
        }
        for packageFQName in packageFQNames {
            for candidate in sema.symbols.lookupAll(fqName: packageFQName + [name]) {
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      candidateSymbol.flags.contains(.operatorFunction),
                      (!candidateSymbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let candidateReceiverType = signature.receiverType
                else {
                    continue
                }
                if sema.types.isSubtype(receiverType, candidateReceiverType) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// KSP-452: a direct range expression (`for (i in 1..10)`, `downTo`, `until`,
    /// `step`) is typed as its element primitive plus a semantic range marker
    /// rather than as `kotlin.ranges.IntRange`, so the class-based lookup in
    /// `resolveCustomIteratorOperator` cannot see the bundled `iterator()`
    /// operator. Resolve it against the nominal range class instead, so a direct
    /// range loop uses the same `.iterator()` chain as a range held in an
    /// `IntRange` / `LongRange` / `CharRange` typed value. Unsigned ranges keep
    /// the legacy `kk_uint_range_*` / `kk_ulong_range_*` intrinsics: they have no
    /// bundled iterator yet.
    private func resolveDirectRangeIteratorOperator(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> CustomIteratorResolution? {
        guard sema.bindings.isRangeExpr(iterableExpr)
            || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
        else {
            return nil
        }
        let nonNullType = sema.types.makeNonNullable(iterableType)
        let rangeClassName: String
        if sema.bindings.isCharRangeExpr(iterableExpr) || nonNullType == sema.types.charType {
            rangeClassName = "CharRange"
        } else if nonNullType == sema.types.longType {
            rangeClassName = "LongRange"
        } else if nonNullType == sema.types.intType {
            rangeClassName = "IntRange"
        } else {
            return nil
        }
        guard let rangeClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern(rangeClassName),
        ]) else {
            return nil
        }
        let rangeType = sema.types.make(.classType(ClassType(
            classSymbol: rangeClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        return resolveCustomIteratorOperator(
            iterableType: rangeType,
            sema: sema,
            interner: interner
        )
    }

    /// Resolves user-defined `operator fun iterator()` on the iterable type,
    /// then resolves `hasNext()` and `next()` on the iterator return type.
    /// Returns nil if no custom iterator operator is defined.
    private func resolveCustomIteratorOperator(
        iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> CustomIteratorResolution? {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        let isCharSequenceLike: Bool = {
            if sema.types.isSubtype(nonNullType, sema.types.stringType) {
                return true
            }
            guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol else {
                return false
            }
            let charSequenceType = sema.types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
            return sema.types.isSubtype(nonNullType, charSequenceType)
        }()
        // Only resolve for user-defined class types and bundled Range/Progression,
        // Channel, or source Sequence/Iterator classes whose `iterator()` operators
        // are now supplied by Kotlin source.
        let classSymbol = resolveClassTypeSymbol(nonNullType, sema: sema)?.1
        guard isCharSequenceLike || {
            guard let classSymbol else { return false }
            return !classSymbol.flags.contains(.synthetic)
                || isRangeLikeClass(classSymbol, sema: sema, interner: interner)
                || KnownCompilerNames(interner: interner).isChannelSymbol(classSymbol)
                || KnownCompilerNames(interner: interner).isSequenceSymbol(classSymbol)
                || sema.symbols.isSourceBackedSymbol(classSymbol.id)
        }() else {
            return nil
        }
        // KSP-441: Allow synthetic Sequence/Iterator symbols to resolve source `iterator()`.
        // Range-like types still fall through to the dedicated range intrinsics when
        // they have no operator iterator() candidate.

        let helpers = TypeCheckHelpers()
        let iteratorName = interner.intern("iterator")
        var iteratorCandidates = helpers.collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  (!symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        // Built-in Range/Progression and Channel classes expose their `iterator()`
        // as a bundled Kotlin extension rather than as a class member, so
        // `collectMemberFunctionCandidates` will not find it through
        // class-hierarchy lookup.
        if iteratorCandidates.isEmpty,
           let bundledIterator = resolveBundledOperatorExtension(
               named: iteratorName,
               receiverType: nonNullType,
               sema: sema,
               interner: interner
           )
        {
            iteratorCandidates = [bundledIterator]
        }

        guard let iteratorSymbol = iteratorCandidates.first,
              let iteratorSignature = sema.symbols.functionSignature(for: iteratorSymbol)
        else {
            return nil
        }

        let iteratorReturnType = iteratorSignature.returnType

        // Resolve hasNext() and next() on the iterator type. These may be real
        // members (e.g. kotlin.collections.Iterator) or bundled Kotlin extension
        // operators (e.g. the Channel iterator layer in Channels.kt).
        let hasNextName = interner.intern("hasNext")
        var hasNextCandidates = helpers.collectMemberFunctionCandidates(
            named: hasNextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard sema.symbols.symbol(candidate) != nil,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }
        if hasNextCandidates.isEmpty,
           let bundledHasNext = resolveBundledOperatorExtension(
               named: hasNextName,
               receiverType: iteratorReturnType,
               sema: sema,
               interner: interner
           )
        {
            hasNextCandidates = [bundledHasNext]
        }

        let nextName = interner.intern("next")
        var nextCandidates = helpers.collectMemberFunctionCandidates(
            named: nextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard sema.symbols.symbol(candidate) != nil,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }
        if nextCandidates.isEmpty,
           let bundledNext = resolveBundledOperatorExtension(
               named: nextName,
               receiverType: iteratorReturnType,
               sema: sema,
               interner: interner
           )
        {
            nextCandidates = [bundledNext]
        }

        guard let hasNextSymbol = hasNextCandidates.first,
              let nextSymbol = nextCandidates.first
        else {
            return nil
        }

        return CustomIteratorResolution(
            iteratorSymbol: iteratorSymbol,
            hasNextSymbol: hasNextSymbol,
            nextSymbol: nextSymbol
        )
    }

    func lowerWhileExpr(
        _ id: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let conditionID = driver.lowerExpr(
            conditionExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        let resultType = sema.bindings.exprTypes[id] ?? sema.types.unitType
        let unit = arena.appendExpr(.unit, type: resultType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerDoWhileExpr(
        _ id: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let bodyLabel = driver.ctx.makeLoopLabel()
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(bodyLabel))

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()

        instructions.append(.label(continueLabel))
        let conditionID = driver.lowerExpr(
            conditionExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))
        instructions.append(.jump(bodyLabel))
        instructions.append(.label(breakLabel))

        let resultType = sema.bindings.exprTypes[id] ?? sema.types.unitType
        let unit = arena.appendExpr(.unit, type: resultType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIfExpr(
        _ exprID: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let conditionID = driver.lowerExpr(
            condition,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let elseLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendTemporary(type: boundType ?? sema.types.errorType)
        let falseVal = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseVal, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseVal, target: elseLabel))
        let thenID = driver.lowerExpr(
            thenExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let thenTerminated = isTerminatedExpr(thenID, arena: arena, sema: sema)
        if !thenTerminated {
            instructions.append(.copy(from: thenID, to: result))
            instructions.append(.jump(endLabel))
        }
        instructions.append(.label(elseLabel))
        var elseTerminated = false
        if let elseExpr {
            let elseID = driver.lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            elseTerminated = isTerminatedExpr(elseID, arena: arena, sema: sema)
            if !elseTerminated {
                instructions.append(.copy(from: elseID, to: result))
            }
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
        // If both branches terminate, propagate Nothing type to the result
        if thenTerminated, elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }

    func lowerTryExpr(
        _ exprID: ExprID,
        bodyExpr: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
        let exceptionTypeSlot = arena.appendTemporary(type: intType)
        let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: nullExceptionValue, value: .null))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let tryResult = arena.appendTemporary(type: boundType ?? sema.types.errorType)

        let catchDispatchLabel = driver.ctx.makeLoopLabel()
        let finallyLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let catchBindings = catchClauses.map { resolveCatchClauseBinding($0, sema: sema, interner: interner) }
        let catchCheckLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let catchMissLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let catchBodyLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let unmatchedCatchLabel = driver.ctx.makeLoopLabel()

        // CODE-001: Push finally block so that return/break/continue inside the
        // try body or catch bodies will inline the finally code before transferring.
        // The block is popped explicitly before lowering the finally body itself
        // (see the pop site below) so that the finally body does not see itself
        // on the stack.
        if let finallyExpr {
            driver.ctx.pushFinallyBlock(finallyExpr)
        }

        var bodyInstructions: [KIRInstruction] = []
        let bodyResultID = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &bodyInstructions
        )

        // CODE-001: Wrap the body's throw-routing output in a finally-guard
        // region so that, if this try is itself nested inside an outer
        // try/catch body, the outer's own appendThrowAwareInstructions pass
        // does not re-wrap calls that are already routed to this try's
        // exceptionSlot. Without this, the outer pass would insert its own
        // jumpIfNotNull immediately after such a call — racing ahead of this
        // try's own follow-up (catch dispatch / finally) and skipping it
        // whenever the exception is actually thrown.
        instructions.append(.beginFinallyGuard)
        appendThrowAwareInstructions(
            bodyInstructions,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: catchDispatchLabel,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions
        )
        instructions.append(.endFinallyGuard)

        let bodyTerminated = isTerminatedExpr(bodyResultID, arena: arena, sema: sema)
        if !bodyTerminated {
            instructions.append(.copy(from: bodyResultID, to: tryResult))
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(catchDispatchLabel))
        if catchClauses.isEmpty {
            instructions.append(.jump(finallyLabel))
        } else if catchClauses.count == 1 {
            let clause = catchClauses[0]
            let binding = catchBindings[0]

            let noMatchLabel = driver.ctx.makeLoopLabel()
            if !isCatchAllType(binding.parameterType, sema: sema, interner: interner) {
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))

                let matchResult = arena.appendTemporary(type: boolType)
                if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                    // Cancellation check only needs falseValue for the jump;
                    // trueValue/sharedUnknownToken are not used.
                    emitNonThrowingCall(
                        callee: interner.intern("kk_throwable_is_cancellation"),
                        arg: exceptionSlot,
                        result: matchResult,
                        into: &instructions
                    )
                } else {
                    // Only emit trueValue/sharedUnknownToken when actually needed
                    // by emitExceptionTypeCheck (avoids dead constValue instructions).
                    let trueValue = arena.appendExpr(.boolLiteral(true), type: boolType)
                    let sharedUnknownToken = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: trueValue, value: .boolLiteral(true)))
                    instructions.append(.constValue(result: sharedUnknownToken, value: .intLiteral(0)))

                    emitExceptionTypeCheck(
                        catchType: binding.parameterType,
                        exceptionSlot: exceptionSlot,
                        exceptionTypeSlot: exceptionTypeSlot,
                        matchResult: matchResult,
                        unknownTypeToken: sharedUnknownToken,
                        trueValue: trueValue,
                        boolType: boolType,
                        intType: intType,
                        sema: sema,
                        interner: interner,
                        arena: arena,
                        instructions: &instructions
                    )
                }
                instructions.append(.jumpIfEqual(lhs: matchResult, rhs: falseValue, target: noMatchLabel))
            }

            var previousCatchParamValue: KIRExprID?
            if clause.paramName != nil, binding.parameterSymbol != .invalid {
                let paramID = arena.appendTemporary(type: binding.parameterType)
                instructions.append(.copy(from: exceptionSlot, to: paramID))
                previousCatchParamValue = driver.ctx.localValue(for: binding.parameterSymbol)
                driver.ctx.setLocalValue(paramID, for: binding.parameterSymbol)
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            var catchBodyInstructions: [KIRInstruction] = []
            let catchBodyResult = driver.lowerExpr(
                clause.body,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &catchBodyInstructions
            )
            // CODE-001: see the matching guard around the body's own
            // appendThrowAwareInstructions call above — a nested try inside
            // this catch body would otherwise have its exception routing
            // re-wrapped (and its own finally skipped) by an outer try.
            instructions.append(.beginFinallyGuard)
            appendThrowAwareInstructions(
                catchBodyInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.endFinallyGuard)

            if clause.paramName != nil, binding.parameterSymbol != .invalid {
                if let previousCatchParamValue {
                    driver.ctx.setLocalValue(previousCatchParamValue, for: binding.parameterSymbol)
                } else {
                    driver.ctx.clearLocalValue(for: binding.parameterSymbol)
                }
            }

            let catchTerminated = isTerminatedExpr(catchBodyResult, arena: arena, sema: sema)
            if !catchTerminated {
                instructions.append(.copy(from: catchBodyResult, to: tryResult))
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
            instructions.append(.jump(finallyLabel))

            instructions.append(.label(noMatchLabel))
            instructions.append(.jump(finallyLabel))
        } else {
            // Emit shared falseValue for any non-catch-all clause (used by
            // both cancellation checks and runtime type checks for the jump).
            let hasTypedCatch = catchBindings.contains { binding in
                !isCatchAllType(binding.parameterType, sema: sema, interner: interner)
            }
            // Only emit trueValue/sharedUnknownToken when at least one clause
            // actually needs emitExceptionTypeCheck (i.e., non-catch-all AND
            // non-cancellation-exception). This avoids dead constValue
            // instructions when all typed clauses are cancellation checks.
            let needsRuntimeTypeCheck = catchBindings.contains { binding in
                !isCatchAllType(binding.parameterType, sema: sema, interner: interner)
                    && !isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner)
            }
            var falseValue: KIRExprID?
            var trueValue: KIRExprID?
            var sharedUnknownToken: KIRExprID?
            if hasTypedCatch {
                let fv = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: fv, value: .boolLiteral(false)))
                falseValue = fv
            }
            if needsRuntimeTypeCheck {
                let tv = arena.appendExpr(.boolLiteral(true), type: boolType)
                let ut = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: tv, value: .boolLiteral(true)))
                instructions.append(.constValue(result: ut, value: .intLiteral(0)))
                trueValue = tv
                sharedUnknownToken = ut
            }
            instructions.append(.jump(catchCheckLabels[0]))

            for index in catchClauses.indices {
                let clause = catchClauses[index]
                let binding = catchBindings[index]
                instructions.append(.label(catchCheckLabels[index]))

                if !isCatchAllType(binding.parameterType, sema: sema, interner: interner) {
                    // Safe to force-unwrap: hasTypedCatch guarantees falseValue is set
                    let fv = falseValue!
                    let matchResult = arena.appendTemporary(type: boolType)
                    if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                        // Cancellation check only needs falseValue for the jump;
                        // trueValue/sharedUnknownToken are not used.
                        emitNonThrowingCall(
                            callee: interner.intern("kk_throwable_is_cancellation"),
                            arg: exceptionSlot,
                            result: matchResult,
                            into: &instructions
                        )
                    } else {
                        // Safe to force-unwrap: needsRuntimeTypeCheck guarantees these are set
                        let tv = trueValue!
                        let ut = sharedUnknownToken!
                        emitExceptionTypeCheck(
                            catchType: binding.parameterType,
                            exceptionSlot: exceptionSlot,
                            exceptionTypeSlot: exceptionTypeSlot,
                            matchResult: matchResult,
                            unknownTypeToken: ut,
                            trueValue: tv,
                            boolType: boolType,
                            intType: intType,
                            sema: sema,
                            interner: interner,
                            arena: arena,
                            instructions: &instructions
                        )
                    }
                    instructions.append(.jumpIfEqual(lhs: matchResult, rhs: fv, target: catchMissLabels[index]))
                }
                instructions.append(.jump(catchBodyLabels[index]))
                instructions.append(.label(catchBodyLabels[index]))

                var previousCatchParamValue: KIRExprID?
                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    let paramID = arena.appendTemporary(type: binding.parameterType)
                    instructions.append(.copy(from: exceptionSlot, to: paramID))
                    previousCatchParamValue = driver.ctx.localValue(for: binding.parameterSymbol)
                    driver.ctx.setLocalValue(paramID, for: binding.parameterSymbol)
                }
                instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
                instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

                var catchBodyInstructions: [KIRInstruction] = []
                let catchBodyResult = driver.lowerExpr(
                    clause.body,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &catchBodyInstructions
                )
                // CODE-001: see the matching guard around the body's own
                // appendThrowAwareInstructions call above — a nested try
                // inside this catch body would otherwise have its exception
                // routing re-wrapped (and its own finally skipped) by an
                // outer try.
                instructions.append(.beginFinallyGuard)
                appendThrowAwareInstructions(
                    catchBodyInstructions,
                    exceptionSlot: exceptionSlot,
                    exceptionTypeSlot: exceptionTypeSlot,
                    thrownTarget: finallyLabel,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.endFinallyGuard)

                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    if let previousCatchParamValue {
                        driver.ctx.setLocalValue(previousCatchParamValue, for: binding.parameterSymbol)
                    } else {
                        driver.ctx.clearLocalValue(for: binding.parameterSymbol)
                    }
                }

                let catchTerminated = isTerminatedExpr(catchBodyResult, arena: arena, sema: sema)
                if !catchTerminated {
                    instructions.append(.copy(from: catchBodyResult, to: tryResult))
                }
                instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
                instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(finallyLabel))

                instructions.append(.label(catchMissLabels[index]))
                if index + 1 < catchClauses.count {
                    instructions.append(.jump(catchCheckLabels[index + 1]))
                } else {
                    instructions.append(.jump(unmatchedCatchLabel))
                }
            }

            instructions.append(.label(unmatchedCatchLabel))
            instructions.append(.jump(finallyLabel))
        }

        // CODE-001: Pop the finally block before lowering the finally label itself,
        // so that the finally body lowering does not see itself on the stack.
        if finallyExpr != nil {
            driver.ctx.popFinallyBlock()
        }

        instructions.append(.label(finallyLabel))
        if let finallyExpr {
            var finallyInstructions: [KIRInstruction] = []
            _ = driver.lowerExpr(
                finallyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &finallyInstructions
            )

            let hasThrowableCall = finallyInstructions.contains { (instr: KIRInstruction) -> Bool in
                switch instr {
                case .call,
                     .virtualCall,
                     .rethrow:
                    return true
                default:
                    return false
                }
            }

            if hasThrowableCall {
                // Allocate separate slots for exceptions thrown *inside* the
                // finally body.  Using the outer exceptionSlot would destroy
                // the pending exception when a finally call succeeds (writes
                // null to the slot), silently swallowing the in-flight error.
                let finallyExSlot = arena.appendTemporary(type: sema.types.nullableAnyType
                )
                let finallyExTypeSlot = arena.appendTemporary(type: intType
                )
                let finallyNullValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                let finallyZeroValue = arena.appendExpr(.intLiteral(0), type: intType)

                // Wrap with guard sentinels so that an outer
                // appendThrowAwareInstructions pass does not double-wrap the
                // already-routed exception handling inside this finally block.
                instructions.append(.beginFinallyGuard)

                instructions.append(.constValue(result: finallyNullValue, value: .null))
                instructions.append(.constValue(result: finallyZeroValue, value: .intLiteral(0)))
                instructions.append(.copy(from: finallyNullValue, to: finallyExSlot))
                instructions.append(.copy(from: finallyZeroValue, to: finallyExTypeSlot))

                let finallyRethrowLabel = driver.ctx.makeLoopLabel()
                let finallyAfterLabel = driver.ctx.makeLoopLabel()

                appendThrowAwareInstructions(
                    finallyInstructions,
                    exceptionSlot: finallyExSlot,
                    exceptionTypeSlot: finallyExTypeSlot,
                    thrownTarget: finallyRethrowLabel,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.jump(finallyAfterLabel))
                instructions.append(.endFinallyGuard)

                // Finally body itself threw — rethrow that exception (replaces
                // the original in-flight exception per Kotlin semantics).
                instructions.append(.label(finallyRethrowLabel))
                instructions.append(.rethrow(value: finallyExSlot))

                instructions.append(.label(finallyAfterLabel))
            } else {
                // No throwable calls — append the finally body directly.
                instructions.append(contentsOf: finallyInstructions)
            }
        }
        instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
        instructions.append(.jump(endLabel))

        instructions.append(.label(rethrowLabel))
        let cancellationCheckResult = arena.appendTemporary(type: boolType)
        emitNonThrowingCall(
            callee: interner.intern("kk_throwable_is_cancellation"),
            arg: exceptionSlot,
            result: cancellationCheckResult,
            into: &instructions
        )
        instructions.append(.rethrow(value: exceptionSlot))

        instructions.append(.label(endLabel))
        return tryResult
    }

    /// Emits instructions to check whether a caught exception matches a specific catch clause type.
    ///
    /// This first performs a fast integer comparison against the encoded catch type token.
    /// When the exact token comparison misses, it falls back to `kk_op_is`, because a
    /// known thrown subtype token can still match a catch clause for one of its supertypes.
    /// The runtime fallback also handles UNKNOWN (0) tokens from external/runtime calls.
    ///
    /// Generated control flow:
    /// ```
    ///   typeMatches = (exceptionTypeSlot == catchTypeToken)
    ///   if typeMatches -> matchResult = true
    ///   typeUnknown = (exceptionTypeSlot == 0)
    ///   matchResult = kk_op_is(exceptionSlot, catchTypeToken)  // subtype/unknown fallback
    /// ```
    ///
    /// Shared boolean/int constants (`unknownTypeToken`, `trueValue`, `falseValue`) are
    /// created once per try/catch block by the caller and passed in to avoid emitting
    /// duplicate `constValue` instructions for each catch clause.
    private func emitExceptionTypeCheck(
        catchType: TypeID,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        matchResult: KIRExprID,
        unknownTypeToken: KIRExprID,
        trueValue: KIRExprID,
        boolType: TypeID,
        intType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) {
        // Per-catch: only the encoded type token is unique to each clause.
        let encodedToken = RuntimeTypeCheckToken.encode(type: catchType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
        let typeMatches = arena.appendTemporary(type: boolType)
        let typeUnknown = arena.appendTemporary(type: boolType)

        let exactMatchLabel = driver.ctx.makeLoopLabel()
        let doneLabel = driver.ctx.makeLoopLabel()

        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))

        // Fast path: exact token match (exception type is known and matches)
        instructions.append(.binary(
            op: .equal,
            lhs: exceptionTypeSlot,
            rhs: tokenExpr,
            result: typeMatches
        ))
        instructions.append(.jumpIfEqual(lhs: typeMatches, rhs: trueValue, target: exactMatchLabel))

        // Keep the UNKNOWN comparison explicit for KIR diagnostics and to make
        // external/runtime-call fallback visible in dumps.
        instructions.append(.binary(
            op: .equal,
            lhs: exceptionTypeSlot,
            rhs: unknownTypeToken,
            result: typeUnknown
        ))

        // Runtime fallback: handles UNKNOWN tokens and known subtype/supertype matches.
        let runtimeResult = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_op_is"),
            arguments: [exceptionSlot, tokenExpr],
            result: runtimeResult,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: runtimeResult, to: matchResult))
        instructions.append(.jump(doneLabel))

        // Exact match: set matchResult = true
        instructions.append(.label(exactMatchLabel))
        instructions.append(.copy(from: trueValue, to: matchResult))
        instructions.append(.jump(doneLabel))

        instructions.append(.label(doneLabel))
    }

    func appendThrowAwareInstructions(
        _ loweredInstructions: [KIRInstruction],
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        // Track nested finally-guard depth so that instructions inside
        // an already-wrapped finally region are passed through verbatim,
        // preventing double-wrapping (CODE-001).
        var finallyGuardDepth = 0
        for instruction in loweredInstructions {
            if case .beginFinallyGuard = instruction {
                finallyGuardDepth += 1
                instructions.append(instruction)
                continue
            }
            if case .endFinallyGuard = instruction {
                finallyGuardDepth -= 1
                instructions.append(instruction)
                continue
            }
            // Inside a finally guard region: pass through verbatim.
            if finallyGuardDepth > 0 {
                instructions.append(instruction)
                continue
            }
            switch instruction {
            case let .call(symbol, callee, arguments, result, _, thrownResult, isSuperCall, qualifiedSuperType)
                where thrownResult == nil:
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult?, isSuperCall, qualifiedSuperType):
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                if thrownResult != exceptionSlot {
                    instructions.append(.copy(from: thrownResult, to: exceptionSlot))
                }
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .virtualCall(symbol, callee, receiver, arguments, result, _, thrownResult, dispatch)
                where thrownResult == nil:
                instructions.append(.virtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot,
                    dispatch: dispatch
                ))
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult?, dispatch):
                instructions.append(.virtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    dispatch: dispatch
                ))
                if thrownResult != exceptionSlot {
                    instructions.append(.copy(from: thrownResult, to: exceptionSlot))
                }
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .rethrow(value):
                instructions.append(.copy(from: value, to: exceptionSlot))
                let rethrowType = arena.exprType(value) ?? sema.types.anyType
                let tokenValue = RuntimeTypeCheckToken.encode(type: rethrowType, sema: sema, interner: interner)
                let thrownTypeToken = arena.appendExpr(.intLiteral(tokenValue), type: intType)
                instructions.append(.constValue(result: thrownTypeToken, value: .intLiteral(tokenValue)))
                instructions.append(.copy(from: thrownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(thrownTarget))
            default:
                instructions.append(instruction)
            }
        }
    }

    func lowerForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let loopBinding = sema.bindings.loopIterationBinding(for: exprID) {
            return lowerCustomForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                loopBinding: loopBinding,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // STDLIB-OP-032: Resolve custom operator fun iterator() on the iterable type.
        let iterableType = sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType
        let customIterator = resolveCustomIteratorOperator(
            iterableType: iterableType,
            sema: sema,
            interner: interner
        )
        // BUG-167: `kk_range_*` only understands range and list iterators, so a
        // dynamically resolved `iterator()` needs the generic intrinsics.
        let dynamicIterator = customIterator == nil
            && usesDynamicIteratorDispatch(iterableType, sema: sema, interner: interner)

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        if let customIter = customIterator {
            let calleeName: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.iteratorSymbol),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.iteratorSymbol) {
                sym.name
            } else {
                interner.intern("iterator")
            }
            instructions.append(.call(
                symbol: customIter.iteratorSymbol,
                callee: calleeName,
                arguments: [iterableID],
                result: iteratorID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_range_iterator"),
                arguments: [iterableID],
                result: iteratorID,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        if let customIter = customIterator {
            let hasNextCallee: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.hasNextSymbol),
                                                   !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.hasNextSymbol) {
                sym.name
            } else {
                interner.intern("hasNext")
            }
            instructions.append(.call(
                symbol: customIter.hasNextSymbol,
                callee: hasNextCallee,
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(dynamicIterator ? "kk_iterator_hasNext" : "kk_range_hasNext"),
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: dynamicIterator,
                thrownResult: nil
            ))
        }
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        // Get next element
        let nextValueID = arena.appendTemporary(type: sema.types.anyType)
        if let customIter = customIterator {
            let nextCallee: InternedString = if let linkName = sema.symbols.externalLinkName(for: customIter.nextSymbol),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(customIter.nextSymbol) {
                sym.name
            } else {
                interner.intern("next")
            }
            instructions.append(.call(
                symbol: customIter.nextSymbol,
                callee: nextCallee,
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(dynamicIterator ? "kk_iterator_next" : "kk_range_next"),
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: dynamicIterator,
                thrownResult: nil
            ))
        }

        // Destructure: call componentN on the element
        // Determine the element type so we can resolve external link names (e.g. __kk_pair_first)
        let isRangeExpr = ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
        let elementType: TypeID = TypeCheckHelpers().iterableElementType(
            for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: interner
        ) ?? sema.types.anyType
        let nonNullElementType = sema.types.makeNonNullable(elementType)

        // Detect if iterating over a Map type. The map iterator yields keys, so
        // for destructuring we need special handling: component1 = key (from next),
        // component2 = kk_map_get(map, key).
        let isMapIteration: Bool = {
            guard let (_, sym) = resolveClassTypeSymbol(iterableType, sema: sema)
            else { return false }
            let mapName = interner.intern("Map")
            let mutableMapName = interner.intern("MutableMap")
            return sym.name == mapName || sym.name == mutableMapName
        }()

        var previousValues: [(SymbolID, KIRExprID?)] = []
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            // Look up the symbol first so we can use the per-component type
            let candidates = sema.symbols.lookupAll(fqName: [
                interner.intern("__for_destructuring_\(exprID.rawValue)"),
                name,
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendTemporary(type: componentType)

            if isMapIteration, componentIndex == 1 {
                // Map destructuring component1 = key, which is the iterator next value
                instructions.append(.copy(from: nextValueID, to: componentResult))
            } else if isMapIteration, componentIndex == 2 {
                // Map destructuring component2 = value, obtained via __kk_map_get(map, key)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_map_get"),
                    arguments: [iterableID, nextValueID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Resolve componentN to externalLinkName when available (Pair, Triple, etc.)
                let resolved = resolveDestructuringComponentCallee(
                    componentName: componentName,
                    receiverType: nonNullElementType,
                    sema: sema,
                    interner: interner
                )
                instructions.append(.call(
                    symbol: resolved.symbol,
                    callee: resolved.callee,
                    arguments: [nextValueID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            if let symbol = candidates.first {
                previousValues.append((symbol, driver.ctx.localValue(for: symbol)))
                driver.ctx.setLocalValue(componentResult, for: symbol)
            }
        }

        let loopLabel = ast.arena.loopLabel(for: exprID)
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: loopLabel)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        // Restore previous values
        for (symbol, previous) in previousValues {
            if let previous {
                driver.ctx.setLocalValue(previous, for: symbol)
            } else {
                driver.ctx.clearLocalValue(for: symbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func lowerCustomForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        loopBinding: LoopIterationBinding,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let iteratorID: KIRExprID
        if let iteratorCall = loopBinding.iteratorCall {
            let iteratorTemp = arena.appendTemporary(type: loopBinding.iteratorType)
            emitForLoopMemberCall(
                callBinding: iteratorCall,
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorTemp,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            iteratorID = iteratorTemp
        } else {
            // The iterable value is itself an Iterator; no iterator() call is needed.
            iteratorID = iterableID
        }
        let listIteratorFastPath = concreteListIteratorFastPath(
            loopBinding: loopBinding,
            iterableType: sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitForLoopMemberCall(
            callBinding: loopBinding.hasNextCall,
            fallback: "hasNext",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.hasNext,
            result: hasNextID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let nextValueID = arena.appendTemporary(type: loopBinding.elementType)
        emitForLoopMemberCall(
            callBinding: loopBinding.nextCall,
            fallback: "next",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.next,
            result: nextValueID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let nonNullElementType = sema.types.makeNonNullable(loopBinding.elementType)
        var previousValues: [(SymbolID, KIRExprID?)] = []
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")
            let candidates = sema.symbols.lookupAll(fqName: [
                interner.intern("__for_destructuring_\(exprID.rawValue)"),
                name,
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendTemporary(type: componentType)

            let resolved = resolveDestructuringComponentCallee(
                componentName: componentName,
                receiverType: nonNullElementType,
                sema: sema,
                interner: interner
            )
            emitNonThrowingCall(
                callee: resolved.callee,
                arg: nextValueID,
                result: componentResult,
                symbol: resolved.symbol,
                into: &instructions
            )

            if let symbol = candidates.first {
                previousValues.append((symbol, driver.ctx.localValue(for: symbol)))
                driver.ctx.setLocalValue(componentResult, for: symbol)
            }
        }

        let loopLabel = ast.arena.loopLabel(for: exprID)
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: loopLabel)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        for (symbol, previous) in previousValues {
            if let previous {
                driver.ctx.setLocalValue(previous, for: symbol)
            } else {
                driver.ctx.clearLocalValue(for: symbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
