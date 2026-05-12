import Foundation

extension CallLowerer {
    func lowerAtomicIntArrayFactoryCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .atomicIntArrayFactory,
              args.count == 2
        else {
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
        let unitType = sema.types.unitType
        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let createCallee = interner.intern("kk_atomic_int_array_create")
        let storeAtCallee = interner.intern("kk_atomic_int_array_storeAt")
        let lessThanCallee = interner.intern("kk_op_lt")
        let addCallee = interner.intern("kk_op_add")
        let unboxIntCallee = interner.intern("kk_unbox_int")

        let sizeExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let arrayExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [sizeExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

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
            arguments: [indexExpr, sizeExpr],
            result: conditionExpr,
            canThrow: true,
            thrownResult: nil
        ))
        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: exitLabel))

        var lambdaResultExpr: KIRExprID?
        if let actionExprNode = ast.arena.expr(args[1].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            let lambdaParamSymbol = driver.lambdaLowerer.syntheticLambdaParamSymbol(
                lambdaExprID: args[1].expr,
                paramIndex: 0
            )
            let previousLocalValue = driver.ctx.localValue(for: lambdaParamSymbol)
            driver.ctx.setLocalValue(indexExpr, for: lambdaParamSymbol)
            lambdaResultExpr = driver.lowerExpr(
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
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                instructions.append(.call(
                    symbol: callableInfo.symbol,
                    callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments + [indexExpr],
                    result: actionResult,
                    canThrow: true,
                    thrownResult: nil
                ))
                lambdaResultExpr = actionResult
            }
        }

        if let lambdaResult = lambdaResultExpr {
            let storeResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: unitType)
            instructions.append(.call(
                symbol: nil,
                callee: storeAtCallee,
                arguments: [arrayExpr, indexExpr, lambdaResult],
                result: storeResult,
                canThrow: false,
                thrownResult: nil
            ))
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

        return arrayExpr
    }
}
