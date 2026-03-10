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

        let countExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let indexExpr = arena.appendExpr(.symbolRef(indexSymbol), type: intType)
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
        let oneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
        instructions.append(.copy(from: zeroExpr, to: indexExpr))

        let conditionLabel = driver.ctx.makeLoopLabel()
        let exitLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(conditionLabel))

        let conditionExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(
            op: .lessThan,
            lhs: indexExpr,
            rhs: countExpr,
            result: conditionExpr
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
            let previousLocalValue = driver.ctx.localValuesBySymbol[lambdaParamSymbol]
            driver.ctx.localValuesBySymbol[lambdaParamSymbol] = indexExpr
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
                driver.ctx.localValuesBySymbol[lambdaParamSymbol] = previousLocalValue
            } else {
                driver.ctx.localValuesBySymbol.removeValue(forKey: lambdaParamSymbol)
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
            if let callableInfo = driver.ctx.callableValueInfoByExprID[actionExpr] {
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

        let nextIndexExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.binary(
            op: .add,
            lhs: indexExpr,
            rhs: oneExpr,
            result: nextIndexExpr
        ))
        instructions.append(.copy(from: nextIndexExpr, to: indexExpr))
        instructions.append(.jump(conditionLabel))
        instructions.append(.label(exitLabel))

        let unitExpr = arena.appendExpr(.unit, type: unitType)
        instructions.append(.constValue(result: unitExpr, value: .unit))
        return unitExpr
    }
}
