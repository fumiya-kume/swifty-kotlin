import Foundation

extension CallLowerer {
    func lowerRepeatCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .repeatLoop,
              args.count == 2
        else {
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
        let unitType = sema.types.unitType
        let lessThanCallee = interner.intern("kk_op_lt")
        let addCallee = interner.intern("kk_op_add")
        let unboxIntCallee = interner.intern("kk_unbox_int")

        let countExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        let oneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: indexExpr, value: .intLiteral(0)))
        instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let conditionLabel = driver.ctx.makeLoopLabel()
        let exitLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(conditionLabel))

        let conditionExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: lessThanCallee,
            arguments: [indexExpr, countExpr],
            result: conditionExpr,
            canThrow: true,
            thrownResult: nil
        ))
        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: exitLabel))

        if let actionExprNode = ast.arena.expr(args[1].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline repeat's lambda body so suspend calls inside the loop body
            // stay in the enclosing suspend function and can be coroutine-lowered.
            let lambdaParamSymbol = driver.lambdaLowerer.syntheticLambdaParamSymbol(
                lambdaExprID: args[1].expr,
                paramIndex: 0
            )
            let previousLocalValue = driver.ctx.localValue(for: lambdaParamSymbol)
            driver.ctx.setLocalValue(indexExpr, for: lambdaParamSymbol)
            _ = driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let previousLocalValue {
                driver.ctx.setLocalValue(previousLocalValue, for: lambdaParamSymbol)
            } else {
                driver.ctx.clearLocalValue(for: lambdaParamSymbol)
            }
        } else {
            let actionExpr = driver.lowerExpr(
                args[1].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
                instructions.append(.call(
                    symbol: callableInfo.symbol,
                    callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments + [indexExpr],
                    result: actionResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }

        let nextIndexBoxedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: addCallee,
            arguments: [indexExpr, oneExpr],
            result: nextIndexBoxedExpr,
            canThrow: true,
            thrownResult: nil
        ))
        let nextIndexExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: unboxIntCallee,
            arguments: [nextIndexBoxedExpr],
            result: nextIndexExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: nextIndexExpr, to: indexExpr))
        instructions.append(.jump(conditionLabel))
        instructions.append(.label(exitLabel))

        let unitExpr = arena.appendExpr(.unit, type: unitType)
        instructions.append(.constValue(result: unitExpr, value: .unit))
        return unitExpr
    }

    func lowerMeasureTimeMillisCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTimeMillis,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let currentTimeCallee = interner.intern("kk_system_currentTimeMillis")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: currentTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
                let thrownResult = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureTimeMillis is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureTimeMillisCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: currentTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }

    func lowerMeasureNanoTimeCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureNanoTime,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let nanoTimeCallee = interner.intern("kk_system_nanoTime")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: nanoTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
                let thrownResult = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureNanoTime is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureNanoTimeCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: nanoTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }

    func lowerMeasureTimeMicrosCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTimeMicros,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let microTimeCallee = interner.intern("kk_system_getTimeMicros")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: microTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
                let thrownResult = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureTimeMicros is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureTimeMicrosCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: microTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }

    func lowerMeasureTimeCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTime,
              args.count == 1
        else {
            return nil
        }

        // Resolve the Duration class type for the result.
        let durationFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("Duration")]
        let resultType: TypeID
        if let durationSymbol = sema.symbols.lookup(fqName: durationFQName) {
            resultType = sema.types.make(.classType(ClassType(
                classSymbol: durationSymbol, args: [], nullability: .nonNull
            )))
        } else {
            resultType = sema.types.anyType
        }

        // Emit start nanoTime (shared by both inline and non-inline paths).
        let startTimeExpr = emitNanoTimeCall(sema: sema, arena: arena, interner: interner, instructions: &instructions)

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline approach: lower the lambda body directly between two
            // nanoTime calls, then compute elapsed nanoseconds and wrap in a
            // Duration via kk_duration_from_nanoseconds (matching the
            // measureTimeMillis pattern but producing a Duration instead of Long).
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            // Non-inline: the argument is a callable reference. Call the
            // callable between nanoTime calls to produce a Duration.
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            guard let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) else {
                // The sema phase guarantees the argument is a callable
                // (lambda or callable reference) when .measureTime is
                // marked.  Degrade gracefully in Release builds (the
                // Duration will measure zero elapsed time).
                return emitDurationFromElapsed(
                    startTimeExpr: startTimeExpr, resultType: resultType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
            let unitType = sema.types.unitType
            let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            instructions.append(.call(
                symbol: callableInfo.symbol, callee: callableInfo.callee,
                arguments: callableInfo.captureArguments,
                result: actionResult, canThrow: true, thrownResult: thrownResult
            ))
            // Propagate exceptions thrown by the callable so they are not
            // silently swallowed.  If thrownResult is non-null the callable
            // threw, so rethrow immediately.
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let continueLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            instructions.append(.jump(continueLabel))
            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: thrownResult))
            instructions.append(.label(continueLabel))
        }

        // Emit end nanoTime, subtract, and box into Duration (shared epilogue).
        return emitDurationFromElapsed(
            startTimeExpr: startTimeExpr, resultType: resultType,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
    }

    // MARK: - measureTimedValue (STDLIB-660)

    func lowerMeasureTimedValueCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTimedValue,
              args.count == 1
        else {
            return nil
        }

        // Resolve the TimedValue class type for the result.
        let timedValueFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("TimedValue")]
        let resultType: TypeID
        if let timedValueSymbol = sema.symbols.lookup(fqName: timedValueFQName) {
            resultType = sema.types.make(.classType(ClassType(
                classSymbol: timedValueSymbol, args: [], nullability: .nonNull
            )))
        } else {
            resultType = sema.types.anyType
        }

        // Emit start nanoTime.
        let startTimeExpr = emitNanoTimeCall(sema: sema, arena: arena, interner: interner, instructions: &instructions)

        // Lower the block and capture its return value.
        let blockResultExpr: KIRExprID

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline: lower the lambda body directly.
            let bodyResult = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            blockResultExpr = bodyResult
        } else {
            // Non-inline: the argument is a callable reference.
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            guard let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) else {
                // Degrade gracefully: return a TimedValue with zero duration.
                let durationExpr = emitDurationFromElapsed(
                    startTimeExpr: startTimeExpr, resultType: sema.types.anyType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                return emitTimedValueNew(
                    valueExpr: nullExpr, durationExpr: durationExpr, resultType: resultType,
                    arena: arena, interner: interner, instructions: &instructions
                )
            }
            let callResultType = sema.types.makeNullable(sema.types.anyType)
            let callResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: callResultType)
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            instructions.append(.call(
                symbol: callableInfo.symbol, callee: callableInfo.callee,
                arguments: callableInfo.captureArguments,
                result: callResult, canThrow: true, thrownResult: thrownResult
            ))
            // Propagate exceptions.
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let continueLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            instructions.append(.jump(continueLabel))
            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: thrownResult))
            instructions.append(.label(continueLabel))
            blockResultExpr = callResult
        }

        // Emit end nanoTime, compute elapsed, box into Duration.
        let durationFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("Duration")]
        let durationType: TypeID
        if let durationSymbol = sema.symbols.lookup(fqName: durationFQName) {
            durationType = sema.types.make(.classType(ClassType(
                classSymbol: durationSymbol, args: [], nullability: .nonNull
            )))
        } else {
            durationType = sema.types.anyType
        }
        let durationExpr = emitDurationFromElapsed(
            startTimeExpr: startTimeExpr, resultType: durationType,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )

        // Create TimedValue(value, duration) via kk_timedvalue_new.
        return emitTimedValueNew(
            valueExpr: blockResultExpr, durationExpr: durationExpr, resultType: resultType,
            arena: arena, interner: interner, instructions: &instructions
        )
    }

    /// Emits a `kk_timedvalue_new(value, duration)` call.
    private func emitTimedValueNew(
        valueExpr: KIRExprID,
        durationExpr: KIRExprID,
        resultType: TypeID,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let newCallee = interner.intern("kk_timedvalue_new")
        let timedValueExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil, callee: newCallee, arguments: [valueExpr, durationExpr],
            result: timedValueExpr, canThrow: false, thrownResult: nil
        ))
        return timedValueExpr
    }

    // MARK: - Helpers

    /// Emits a `kk_system_nanoTime()` call and returns the result expression.
    private func emitNanoTimeCall(
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let nanoTimeCallee = interner.intern("kk_system_nanoTime")
        let longType = sema.types.longType
        let timeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: nanoTimeCallee, arguments: [],
            result: timeExpr, canThrow: false, thrownResult: nil
        ))
        return timeExpr
    }

    /// Emits end-nanoTime, elapsed subtraction, and `kk_duration_from_nanoseconds`
    /// boxing.  Shared epilogue for both inline and non-inline measureTime paths.
    private func emitDurationFromElapsed(
        startTimeExpr: KIRExprID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let endTimeExpr = emitNanoTimeCall(sema: sema, arena: arena, interner: interner, instructions: &instructions)

        let longType = sema.types.longType
        let subCallee = interner.intern("kk_op_sub")
        let elapsedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: elapsedExpr, canThrow: false, thrownResult: nil
        ))

        let fromNanosCallee = interner.intern("kk_duration_from_nanoseconds")
        let durationExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil, callee: fromNanosCallee, arguments: [elapsedExpr],
            result: durationExpr, canThrow: false, thrownResult: nil
        ))

        return durationExpr
    }
}
