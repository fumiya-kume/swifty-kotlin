import Foundation

/// Delegate class for KIR lowering: ControlFlowLowerer.
/// Holds an unowned reference to the driver for mutual recursion.

extension ControlFlowLowerer {
    func appendThrowAwareInstructions(
        _ loweredInstructions: KIRLoweringEmitContext,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        arena: KIRArena,
        emit instructions: inout KIRLoweringEmitContext
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        for instruction in loweredInstructions {
            switch instruction {
            case .call(let symbol, let callee, let arguments, let result, _, let thrownResult, let isSuperCall)
                where thrownResult == nil:
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot,
                    isSuperCall: isSuperCall
                ))
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case .virtualCall(let symbol, let callee, let receiver, let arguments, let result, _, let thrownResult, let dispatch)
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
            case .rethrow(let value):
                instructions.append(.copy(from: value, to: exceptionSlot))
                let tokenValue = Int64((arena.exprType(value) ?? sema.types.anyType).rawValue)
                let thrownTypeToken = arena.appendExpr(.intLiteral(tokenValue), type: intType)
                instructions.append(.constValue(result: thrownTypeToken, value: .intLiteral(tokenValue)))
                instructions.append(.copy(from: thrownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(thrownTarget))
            default:
                instructions.append(instruction)
            }
        }
    }

    func resolveCatchClauseBinding(
        _ clause: CatchClause,
        sema: SemaModule,
        interner: StringInterner
    ) -> CatchClauseBinding {
        if let binding = sema.bindings.catchClauseBinding(for: clause.body) {
            return binding
        }
        let fallbackType = resolveLegacyCatchClauseType(
            clause.paramTypeName,
            sema: sema,
            interner: interner
        )
        let fallbackSymbol = sema.bindings.identifierSymbols[clause.body] ?? .invalid
        return CatchClauseBinding(parameterSymbol: fallbackSymbol, parameterType: fallbackType)
    }

    func resolveLegacyCatchClauseType(
        _ typeName: InternedString?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let typeName else {
            return sema.types.anyType
        }
        switch interner.resolve(typeName) {
        case "Int":
            return sema.types.make(.primitive(.int, .nonNull))
        case "Long":
            return sema.types.make(.primitive(.long, .nonNull))
        case "Float":
            return sema.types.make(.primitive(.float, .nonNull))
        case "Double":
            return sema.types.make(.primitive(.double, .nonNull))
        case "Boolean":
            return sema.types.make(.primitive(.boolean, .nonNull))
        case "Char":
            return sema.types.make(.primitive(.char, .nonNull))
        case "String":
            return sema.types.make(.primitive(.string, .nonNull))
        case "Any":
            return sema.types.anyType
        case "Unit":
            return sema.types.unitType
        case "Nothing":
            return sema.types.nothingType
        default:
            let candidates = sema.symbols.lookupAll(fqName: [typeName])
                .filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                .sorted { $0.rawValue < $1.rawValue }
            guard let symbol = candidates.first else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        }
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule) -> Bool {
        type == sema.types.anyType || type == sema.types.nullableAnyType
    }

    func lowerForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            shared: shared, emit: &instructions
        )
        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_iterator"),
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
            symbol: nil,
            callee: interner.intern("kk_range_hasNext"),
            arguments: [iteratorID],
            result: hasNextID,
            canThrow: false,
            thrownResult: nil
        ))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        // Get next element
        let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_next"),
            arguments: [iteratorID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))

        // Destructure: call componentN on the element
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
                name
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: componentType)
            instructions.append(.call(
                symbol: nil,
                callee: componentName,
                arguments: [nextValueID],
                result: componentResult,
                canThrow: false,
                thrownResult: nil
            ))

            if let symbol = candidates.first {
                previousValues.append((symbol, driver.ctx.localValuesBySymbol[symbol]))
                driver.ctx.localValuesBySymbol[symbol] = componentResult
            }
        }

        driver.ctx.loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel, name: nil))
        _ = driver.lowerExpr(
            bodyExpr,
            shared: shared, emit: &instructions
        )
        _ = driver.ctx.loopControlStack.popLast()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        // Restore previous values
        for (symbol, previous) in previousValues {
            if let previous {
                driver.ctx.localValuesBySymbol[symbol] = previous
            } else {
                driver.ctx.localValuesBySymbol.removeValue(forKey: symbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerWhenExpr(
        _ exprID: ExprID,
        subject: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let boundType = sema.bindings.exprTypes[exprID]
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        var subjectID: KIRExprID?
        if let subject {
            subjectID = driver.lowerExpr(
                subject,
                shared: shared, emit: &instructions
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
                let bodyLabel: Int32 = driver.ctx.makeLoopLabel()
                // Hoist the true constant outside the loop so it's reused for all non-last conditions.
                let hoistedTrueID = arena.appendExpr(.boolLiteral(true), type: boolType)
                instructions.append(.constValue(result: hoistedTrueID, value: .boolLiteral(true)))

                for (condIdx, conditionExprID) in branch.conditions.enumerated() {
                    let conditionValueID = driver.lowerExpr(
                        conditionExprID,
                        shared: shared, emit: &instructions
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
                    let isLastCondition = condIdx == branch.conditions.count - 1
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
                let conditionValueID = driver.lowerExpr(
                    conditionExprID,
                    shared: shared, emit: &instructions
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

            let bodyID = driver.lowerExpr(
                branch.body,
                shared: shared, emit: &instructions
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
                shared: shared, emit: &instructions
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
        if allBranchesTerminated && elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }
}
