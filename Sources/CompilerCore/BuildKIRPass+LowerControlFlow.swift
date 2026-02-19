import Foundation

extension BuildKIRPhase {
    func lowerForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("iterator"),
            arguments: [iterableID],
            result: iteratorID,
            canThrow: false,
            thrownResult: nil
        ))

        let continueLabel = makeLoopLabel()
        let breakLabel = makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("hasNext"),
            arguments: [iteratorID],
            result: hasNextID,
            canThrow: false,
            thrownResult: nil
        ))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { localValuesBySymbol[$0] }
        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("next"),
            arguments: [iteratorID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))
        if let loopVariableSymbol {
            localValuesBySymbol[loopVariableSymbol] = nextValueID
        }

        loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = loopControlStack.popLast()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                localValuesBySymbol[loopVariableSymbol] = previousLoopValue
            } else {
                localValuesBySymbol.removeValue(forKey: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerWhileExpr(
        _ exprID: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let continueLabel = makeLoopLabel()
        let breakLabel = makeLoopLabel()
        instructions.append(.label(continueLabel))

        let conditionID = lowerExpr(
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

        loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = loopControlStack.popLast()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerDoWhileExpr(
        _ exprID: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let bodyLabel = makeLoopLabel()
        let continueLabel = makeLoopLabel()
        let breakLabel = makeLoopLabel()
        instructions.append(.label(bodyLabel))

        loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = loopControlStack.popLast()

        instructions.append(.label(continueLabel))
        let conditionID = lowerExpr(
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
        let conditionID = lowerExpr(
            condition,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let elseLabel = makeLoopLabel()
        let endLabel = makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.errorType)
        let falseVal = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseVal, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseVal, target: elseLabel))
        let thenID = lowerExpr(
            thenExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        instructions.append(.copy(from: thenID, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(elseLabel))
        if let elseExpr {
            let elseID = lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.copy(from: elseID, to: result))
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
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
        let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        let zeroInit = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
        instructions.append(.constValue(result: zeroInit, value: .intLiteral(0)))
        instructions.append(.copy(from: zeroInit, to: exceptionSlot))

        let tryResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

        let catchDispatchLabel = makeLoopLabel()
        let finallyLabel = makeLoopLabel()
        let rethrowLabel = makeLoopLabel()
        let endLabel = makeLoopLabel()

        var clauseLabels: [Int32] = []
        for _ in catchClauses {
            clauseLabels.append(makeLoopLabel())
        }

        var bodyInstructions: [KIRInstruction] = []
        let bodyResultID = lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &bodyInstructions
        )

        for instruction in bodyInstructions {
            if case .call(let symbol, let callee, let arguments, let result, _, let existingThrownResult) = instruction,
               existingThrownResult == nil {
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot
                ))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: catchDispatchLabel))
            } else if case .rethrow(let value) = instruction {
                instructions.append(.copy(from: value, to: exceptionSlot))
                instructions.append(.jump(catchDispatchLabel))
            } else {
                instructions.append(instruction)
            }
        }

        instructions.append(.copy(from: bodyResultID, to: tryResult))
        instructions.append(.jump(finallyLabel))

        instructions.append(.label(catchDispatchLabel))
        if !catchClauses.isEmpty {
            instructions.append(.jump(clauseLabels[0]))

            for (index, clause) in catchClauses.enumerated() {
                instructions.append(.label(clauseLabels[index]))

                if clause.paramName != nil {
                    let paramID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                    instructions.append(.copy(from: exceptionSlot, to: paramID))
                    if let catchParamSymbol = sema.bindings.identifierSymbols[clause.body] {
                        localValuesBySymbol[catchParamSymbol] = paramID
                    }
                }

                let catchBodyResult = lowerExpr(
                    clause.body,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )

                instructions.append(.copy(from: catchBodyResult, to: tryResult))

                let clearVal = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
                instructions.append(.constValue(result: clearVal, value: .intLiteral(0)))
                instructions.append(.copy(from: clearVal, to: exceptionSlot))

                instructions.append(.jump(finallyLabel))
            }
        } else {
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(finallyLabel))
        if let finallyExpr {
            _ = lowerExpr(
                finallyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
        instructions.append(.jump(endLabel))

        instructions.append(.label(rethrowLabel))
        instructions.append(.rethrow(value: exceptionSlot))

        instructions.append(.label(endLabel))
        return tryResult
    }

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
            subjectID = lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let endLabel = makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.errorType)

        var nextBranchLabels: [Int32] = []
        for _ in branches {
            nextBranchLabels.append(makeLoopLabel())
        }

        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))

        for (index, branch) in branches.enumerated() {
            if let conditionExprID = branch.condition {
                let conditionValueID = lowerExpr(
                    conditionExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let matchesID: KIRExprID
                if let subjectID {
                    matchesID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                    instructions.append(.binary(
                        op: .equal,
                        lhs: subjectID,
                        rhs: conditionValueID,
                        result: matchesID
                    ))
                } else {
                    matchesID = conditionValueID
                }
                instructions.append(.jumpIfEqual(lhs: matchesID, rhs: falseID, target: nextBranchLabels[index]))
            }

            let bodyID = lowerExpr(
                branch.body,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.copy(from: bodyID, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nextBranchLabels[index]))
        }

        if let elseExpr {
            let fallbackID = lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.copy(from: fallbackID, to: result))
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
        return result
    }
}
