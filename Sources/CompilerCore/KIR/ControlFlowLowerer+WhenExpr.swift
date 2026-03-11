import Foundation

extension ControlFlowLowerer {
    func lowerWhenExpr(
        _ exprID: ExprID,
        subject: ExprID?,
        branches: [WhenBranch],
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
        var subjectID: KIRExprID?
        if let subject {
            subjectID = driver.lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.errorType)

        var nextBranchLabels: [Int32] = []
        for _ in branches {
            nextBranchLabels.append(driver.ctx.makeLoopLabel())
        }

        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))

        // Vacuously true when branches is empty (only else exists).
        var allBranchesTerminated = true
        for (index, branch) in branches.enumerated() {
            if branch.conditions.count > 1 {
                // Multiple conditions: build an OR-chain that jumps to the body label
                // as soon as any condition is true.
                // CTRL-001: Deduplicate conditions to avoid redundant comparisons.
                let deduplicatedConditions = deduplicateWhenConditions(
                    branch.conditions, ast: ast, sema: sema, interner: interner
                )
                let bodyLabel: Int32 = driver.ctx.makeLoopLabel()
                // Hoist the true constant outside the loop so it's reused for all non-last conditions.
                let hoistedTrueID = arena.appendExpr(.boolLiteral(true), type: boolType)
                instructions.append(.constValue(result: hoistedTrueID, value: .boolLiteral(true)))

                for (condIdx, conditionExprID) in deduplicatedConditions.enumerated() {
                    let matchesID = lowerWhenConditionMatch(
                        conditionExprID: conditionExprID,
                        subjectExprID: subject,
                        loweredSubjectID: subjectID,
                        falseID: falseID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let isLastCondition = condIdx == deduplicatedConditions.count - 1
                    if isLastCondition {
                        // Last condition: if false, jump to next branch
                        instructions.append(.jumpIfEqual(lhs: matchesID, rhs: falseID, target: nextBranchLabels[index]))
                    } else {
                        // Not last condition: if true, jump to body (short-circuit OR)
                        instructions.append(.jumpIfEqual(lhs: matchesID, rhs: hoistedTrueID, target: bodyLabel))
                    }
                }

                instructions.append(.label(bodyLabel))
            } else if !branch.conditions.isEmpty {
                // Single condition: no OR-chain, just evaluate and branch on false.
                let conditionExprID = branch.conditions[0]
                let matchesID = lowerWhenConditionMatch(
                    conditionExprID: conditionExprID,
                    subjectExprID: subject,
                    loweredSubjectID: subjectID,
                    falseID: falseID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.jumpIfEqual(lhs: matchesID, rhs: falseID, target: nextBranchLabels[index]))
            }

            let bodyID = driver.lowerExpr(
                branch.body,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let branchTerminated = isTerminatedExpr(bodyID, arena: arena, sema: sema)
            if !branchTerminated {
                instructions.append(.copy(from: bodyID, to: result))
                instructions.append(.jump(endLabel))
                allBranchesTerminated = false
            }
            instructions.append(.label(nextBranchLabels[index]))
        }

        var elseTerminated = false
        if let elseExpr {
            let fallbackID = driver.lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            elseTerminated = isTerminatedExpr(fallbackID, arena: arena, sema: sema)
            if !elseTerminated {
                instructions.append(.copy(from: fallbackID, to: result))
            }
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
        // Propagate Nothing type when all branches (including else) terminate
        if allBranchesTerminated, elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }

    private func lowerWhenConditionMatch(
        conditionExprID: ExprID,
        subjectExprID: ExprID?,
        loweredSubjectID: KIRExprID?,
        falseID: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        if let loweredSubjectID,
           let conditionExpr = ast.arena.expr(conditionExprID),
           case let .isCheck(checkedExprID, _, negated, _) = conditionExpr,
           isSameWhenSubjectExpression(checkedExprID, subjectExprID: subjectExprID, sema: sema)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let typeTokenLiteral: Int64 = if let targetType = sema.bindings.isCheckTargetType(for: conditionExprID) {
                RuntimeTypeCheckToken.encode(type: targetType, sema: sema, interner: interner)
            } else {
                RuntimeTypeCheckToken.unknownBase
            }
            let typeToken = arena.appendExpr(.intLiteral(typeTokenLiteral), type: intType)
            instructions.append(.constValue(result: typeToken, value: .intLiteral(typeTokenLiteral)))

            let isResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [loweredSubjectID, typeToken],
                result: isResult,
                canThrow: false,
                thrownResult: nil
            ))
            guard negated else {
                return isResult
            }
            let negatedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.binary(op: .equal, lhs: isResult, rhs: falseID, result: negatedResult))
            return negatedResult
        }

        let conditionValueID = driver.lowerExpr(
            conditionExprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if let loweredSubjectID {
            let matchesID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.binary(
                op: .equal,
                lhs: loweredSubjectID,
                rhs: conditionValueID,
                result: matchesID
            ))
            return matchesID
        }

        return conditionValueID
    }

    private func isSameWhenSubjectExpression(
        _ checkedExprID: ExprID,
        subjectExprID: ExprID?,
        sema: SemaModule
    ) -> Bool {
        guard let subjectExprID else {
            return false
        }
        if checkedExprID == subjectExprID {
            return true
        }
        guard let checkedSymbolID = sema.bindings.identifierSymbols[checkedExprID],
              let subjectSymbolID = sema.bindings.identifierSymbols[subjectExprID]
        else {
            return false
        }
        return checkedSymbolID == subjectSymbolID
    }
}
