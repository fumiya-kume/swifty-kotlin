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

        let measureTimeCallee = interner.intern("kk_measureTime")

        // Build the closure/callable argument pair for the kk_measureTime runtime call.
        // kk_measureTime(fnPtr, closureRaw, outThrown) -> Duration handle
        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline approach: lower the lambda body directly, then wrap
            // with a kk_measureTime call. For inline lambdas we lower the
            // body between two nanoTime calls, creating the Duration box
            // manually at the KIR level (matching measureTimeMillis pattern
            // but producing a Duration instead of Long).
            let nanoTimeCallee = interner.intern("kk_system_nanoTime")
            let longType = sema.types.longType

            let startTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
            instructions.append(.call(
                symbol: nil, callee: nanoTimeCallee, arguments: [],
                result: startTimeExpr, canThrow: false, thrownResult: nil
            ))

            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            let endTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
            instructions.append(.call(
                symbol: nil, callee: nanoTimeCallee, arguments: [],
                result: endTimeExpr, canThrow: false, thrownResult: nil
            ))

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
        } else {
            // Non-inline: the argument is a callable reference. Call the lambda
            // directly between nanoTime calls to produce a Duration, matching
            // the inline pattern. (kk_measureTime expects fnPtr/closureRaw which
            // are not available through callableValueInfo.)
            let nanoTimeCallee = interner.intern("kk_system_nanoTime")
            let longType = sema.types.longType

            let startTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
            instructions.append(.call(
                symbol: nil, callee: nanoTimeCallee, arguments: [],
                result: startTimeExpr, canThrow: false, thrownResult: nil
            ))

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
                assertionFailure("lowerMeasureTimeCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }

            let endTimeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: longType)
            instructions.append(.call(
                symbol: nil, callee: nanoTimeCallee, arguments: [],
                result: endTimeExpr, canThrow: false, thrownResult: nil
            ))

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

        let fallbackExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        return fallbackExpr
    }
}
