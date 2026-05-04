import Foundation

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

    /// Check if a lowered expression is a terminator (return/throw/Nothing type).
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
        // CORO-075: Detect Channel iterables and route to channel-specific
        // iterator functions that perform blocking-suspend receive internally.
        let iterableType = sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType
        if isChannelType(iterableType, sema: sema, interner: interner) {
            return lowerChannelForExpr(
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
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)
        let isUIntRangeLike = sema.bindings.isUIntRangeExpr(iterableExpr) || nonNullIterableType == sema.types.uintType
        let isULongRangeLike = sema.bindings.isULongRangeExpr(iterableExpr) || nonNullIterableType == sema.types.ulongType

        // STDLIB-OP-032: Resolve custom operator fun iterator() on the iterable type.
        // If the iterable has a user-defined iterator(), dispatch to it instead of
        // the built-in kk_range_iterator runtime function.
        let customIterator = resolveCustomIteratorOperator(
            iterableType: iterableType,
            sema: sema,
            interner: interner
        )

        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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

        let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
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
        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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
        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: loopBinding.iteratorType)
        instructions.append(.call(
            symbol: loopBinding.iteratorCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.iteratorCall, sema: sema, interner: interner, fallback: "iterator"),
            arguments: [iterableID],
            result: iteratorID,
            canThrow: false,
            thrownResult: nil
        ))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.call(
            symbol: loopBinding.hasNextCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.hasNextCall, sema: sema, interner: interner, fallback: "hasNext"),
            arguments: [iteratorID],
            result: hasNextID,
            canThrow: false,
            thrownResult: nil
        ))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: loopBinding.elementType)
        instructions.append(.call(
            symbol: loopBinding.nextCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.nextCall, sema: sema, interner: interner, fallback: "next"),
            arguments: [iteratorID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))
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

    // MARK: - Channel For-Loop (CORO-075)

    /// Lower a `for (value in channel)` loop by receiving one value at a time.
    /// `kk_channel_receive` is recognized by `CoroutineLoweringPass`, so this
    /// path can suspend without leaking the runtime suspension marker into the
    /// loop body.
    private func lowerChannelForExpr(
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
        let intType = sema.types.intType
        // Lower the channel expression.
        let channelID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let receivedValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_channel_receive"),
            arguments: [channelID],
            result: receivedValueID,
            canThrow: false,
            thrownResult: nil
        ))
        let closedTokenID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_channel_is_closed_token"),
            arguments: [receivedValueID],
            result: closedTokenID,
            canThrow: false,
            thrownResult: nil
        ))
        let trueTokenID = arena.appendExpr(.intLiteral(1), type: intType)
        instructions.append(.constValue(result: trueTokenID, value: .intLiteral(1)))
        instructions.append(.jumpIfEqual(lhs: closedTokenID, rhs: trueTokenID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(receivedValueID, for: loopVariableSymbol)
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

    // MARK: - Custom Iterator Resolution (STDLIB-OP-032)

    /// Resolved custom iterator operator chain: iterator(), hasNext(), next().
    private struct CustomIteratorResolution {
        let iteratorSymbol: SymbolID
        let hasNextSymbol: SymbolID
        let nextSymbol: SymbolID
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
        // Only resolve for user-defined class types, not primitives or built-in ranges.
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let classSymbol = sema.symbols.symbol(classType.classSymbol),
              !classSymbol.flags.contains(.synthetic)
        else {
            return nil
        }

        let helpers = TypeCheckHelpers()
        let iteratorName = interner.intern("iterator")
        let iteratorCandidates = helpers.collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        guard let iteratorSymbol = iteratorCandidates.first,
              let iteratorSignature = sema.symbols.functionSignature(for: iteratorSymbol)
        else {
            return nil
        }

        let iteratorReturnType = iteratorSignature.returnType

        // Resolve hasNext() and next() on the iterator type.
        let hasNextName = interner.intern("hasNext")
        let hasNextCandidates = helpers.collectMemberFunctionCandidates(
            named: hasNextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let _ = sema.symbols.symbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        let nextName = interner.intern("next")
        let nextCandidates = helpers.collectMemberFunctionCandidates(
            named: nextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let _ = sema.symbols.symbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
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

    /// Returns true if `type` is a Channel type.
    private func isChannelType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func lowerWhileExpr(
        _: ExprID,
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

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerDoWhileExpr(
        _: ExprID,
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

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
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
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.errorType)
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
        let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.nullableAnyType)
        let exceptionTypeSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: nullExceptionValue, value: .null))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let tryResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.errorType)

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

                let matchResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                    // Cancellation check only needs falseValue for the jump;
                    // trueValue/sharedUnknownToken are not used.
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_throwable_is_cancellation"),
                        arguments: [exceptionSlot],
                        result: matchResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
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
                        falseValue: falseValue,
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
                let paramID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: binding.parameterType)
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
                    let matchResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                    if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                        // Cancellation check only needs falseValue for the jump;
                        // trueValue/sharedUnknownToken are not used.
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_throwable_is_cancellation"),
                            arguments: [exceptionSlot],
                            result: matchResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
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
                            falseValue: fv,
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
                    let paramID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: binding.parameterType)
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
                case .call(_, _, _, _, _, _, _, _),
                     .virtualCall(_, _, _, _, _, _, _, _),
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
                let finallyExSlot = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                let finallyExTypeSlot = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
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
        let cancellationCheckResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_throwable_is_cancellation"),
            arguments: [exceptionSlot],
            result: cancellationCheckResult,
            canThrow: false,
            thrownResult: nil
        ))
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
        falseValue: KIRExprID,
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
        let typeMatches = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        let typeUnknown = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)

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
        let runtimeResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
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

        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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
                canThrow: false,
                thrownResult: nil
            ))
        }

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
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
                callee: interner.intern("kk_range_hasNext"),
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
        }
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        // Get next element
        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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
                callee: interner.intern("kk_range_next"),
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // Destructure: call componentN on the element
        // Determine the element type so we can resolve external link names (e.g. kk_pair_first)
        let isRangeExpr = ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
        let elementType: TypeID = TypeCheckHelpers().iterableElementType(
            for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: interner
        ) ?? sema.types.anyType
        let nonNullElementType = sema.types.makeNonNullable(elementType)

        // Detect if iterating over a Map type. The map iterator yields keys, so
        // for destructuring we need special handling: component1 = key (from next),
        // component2 = kk_map_get(map, key).
        let isMapIteration: Bool = {
            guard case let .classType(ct) = sema.types.kind(of: sema.types.makeNonNullable(iterableType)),
                  let sym = sema.symbols.symbol(ct.classSymbol)
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
            let componentResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: componentType)

            if isMapIteration, componentIndex == 1 {
                // Map destructuring component1 = key, which is the iterator next value
                instructions.append(.copy(from: nextValueID, to: componentResult))
            } else if isMapIteration, componentIndex == 2 {
                // Map destructuring component2 = value, obtained via kk_map_get(map, key)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_map_get"),
                    arguments: [iterableID, nextValueID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Resolve componentN to externalLinkName when available (Pair, Triple, etc.)
                let memberCandidates = TypeCheckHelpers().collectMemberFunctionCandidates(
                    named: componentName,
                    receiverType: nonNullElementType,
                    sema: sema,
                    interner: interner
                )
                let resolvedCallee: InternedString = if let chosen = memberCandidates.first,
                                                        let linkName = sema.symbols.externalLinkName(for: chosen),
                                                        !linkName.isEmpty
                {
                    interner.intern(linkName)
                } else {
                    componentName
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: resolvedCallee,
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
        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: loopBinding.iteratorType)
        instructions.append(.call(
            symbol: loopBinding.iteratorCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.iteratorCall, sema: sema, interner: interner, fallback: "iterator"),
            arguments: [iterableID],
            result: iteratorID,
            canThrow: false,
            thrownResult: nil
        ))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.call(
            symbol: loopBinding.hasNextCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.hasNextCall, sema: sema, interner: interner, fallback: "hasNext"),
            arguments: [iteratorID],
            result: hasNextID,
            canThrow: false,
            thrownResult: nil
        ))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: loopBinding.elementType)
        instructions.append(.call(
            symbol: loopBinding.nextCall.chosenCallee,
            callee: resolvedLoopCallee(for: loopBinding.nextCall, sema: sema, interner: interner, fallback: "next"),
            arguments: [iteratorID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))

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
            let componentResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: componentType)

            let memberCandidates = TypeCheckHelpers().collectMemberFunctionCandidates(
                named: componentName,
                receiverType: nonNullElementType,
                sema: sema,
                interner: interner
            )
            let resolvedCallee: InternedString = if let chosen = memberCandidates.first,
                                                    let linkName = sema.symbols.externalLinkName(for: chosen),
                                                    !linkName.isEmpty
            {
                interner.intern(linkName)
            } else {
                componentName
            }
            instructions.append(.call(
                symbol: nil,
                callee: resolvedCallee,
                arguments: [nextValueID],
                result: componentResult,
                canThrow: false,
                thrownResult: nil
            ))

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
