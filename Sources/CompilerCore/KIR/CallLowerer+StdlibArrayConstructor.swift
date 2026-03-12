import Foundation

extension CallLowerer {
    func lowerArrayConstructorCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .arrayConstructor,
              args.count == 2
        else {
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
        let anyType = sema.types.anyType
        let arrayNewCallee = interner.intern("kk_array_new")
        let arraySetCallee = interner.intern("kk_array_set")
        let lessThanCallee = interner.intern("kk_op_lt")
        let addCallee = interner.intern("kk_op_add")
        let unboxIntCallee = interner.intern("kk_unbox_int")

        // 1. Lower the size argument
        let sizeExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // 2. Create the array: kk_array_new(size)
        let arrayExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
        instructions.append(.call(
            symbol: nil,
            callee: arrayNewCallee,
            arguments: [sizeExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // 3. Loop setup: index = 0
        let indexExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        let oneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: indexExpr, value: .intLiteral(0)))
        instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let conditionLabel = driver.ctx.makeLoopLabel()
        let exitLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(conditionLabel))

        // 4. Loop condition: index < size
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

        // 5. Call init lambda with index, get result
        var lambdaResultExpr: KIRExprID?
        if let actionExprNode = ast.arena.expr(args[1].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline the lambda body (same pattern as repeat)
            let lambdaParamSymbol = driver.lambdaLowerer.syntheticLambdaParamSymbol(
                lambdaExprID: args[1].expr,
                paramIndex: 0
            )
            let previousLocalValue = driver.ctx.localValuesBySymbol[lambdaParamSymbol]
            driver.ctx.localValuesBySymbol[lambdaParamSymbol] = indexExpr
            let bodyResult = driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            lambdaResultExpr = bodyResult
            if let previousLocalValue {
                driver.ctx.localValuesBySymbol[lambdaParamSymbol] = previousLocalValue
            } else {
                driver.ctx.localValuesBySymbol.removeValue(forKey: lambdaParamSymbol)
            }
        } else {
            // Non-inline: lower the lambda and call it
            let actionExpr = driver.lowerExpr(
                args[1].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfoByExprID[actionExpr] {
                let actionResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
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

        // 6. kk_array_set(array, index, lambdaResult)
        if let lambdaResult = lambdaResultExpr {
            let setResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
            instructions.append(.call(
                symbol: nil,
                callee: arraySetCallee,
                arguments: [arrayExpr, indexExpr, lambdaResult],
                result: setResult,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // 7. index = index + 1
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

        // 8. Return the array
        return arrayExpr
    }
}
