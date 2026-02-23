import Foundation

/// Delegate class for KIR lowering: ControlFlowLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class ControlFlowLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
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
        let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("iterator"),
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
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValuesBySymbol[$0] }
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
            driver.ctx.localValuesBySymbol[loopVariableSymbol] = nextValueID
        }

        driver.ctx.loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.loopControlStack.popLast()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.localValuesBySymbol[loopVariableSymbol] = previousLoopValue
            } else {
                driver.ctx.localValuesBySymbol.removeValue(forKey: loopVariableSymbol)
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

        driver.ctx.loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.loopControlStack.popLast()
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
        let bodyLabel = driver.ctx.makeLoopLabel()
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(bodyLabel))

        driver.ctx.loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.loopControlStack.popLast()

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
        if thenTerminated && elseTerminated {
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
        let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        let exceptionTypeSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        let zeroValue = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: zeroValue, value: .intLiteral(0)))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: zeroValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let tryResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

        let catchDispatchLabel = driver.ctx.makeLoopLabel()
        let finallyLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let catchBindings = catchClauses.map { resolveCatchClauseBinding($0, sema: sema, interner: interner) }
        let catchCheckLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let catchBodyLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let unmatchedCatchLabel = driver.ctx.makeLoopLabel()

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
        } else {
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            instructions.append(.jump(catchCheckLabels[0]))

            for index in catchClauses.indices {
                let clause = catchClauses[index]
                let binding = catchBindings[index]
                instructions.append(.label(catchCheckLabels[index]))

                if !isCatchAllType(binding.parameterType, sema: sema) {
                    let tokenExpr = arena.appendExpr(.intLiteral(Int64(binding.parameterType.rawValue)), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(binding.parameterType.rawValue))))
                    let matchResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                    instructions.append(.binary(
                        op: .equal,
                        lhs: exceptionTypeSlot,
                        rhs: tokenExpr,
                        result: matchResult
                    ))
                    let nextLabel = index + 1 < catchClauses.count
                        ? catchCheckLabels[index + 1]
                        : unmatchedCatchLabel
                    instructions.append(.jumpIfEqual(lhs: matchResult, rhs: falseValue, target: nextLabel))
                }
                instructions.append(.jump(catchBodyLabels[index]))
                instructions.append(.label(catchBodyLabels[index]))

                var previousCatchParamValue: KIRExprID?
                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    let paramID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: binding.parameterType)
                    instructions.append(.copy(from: exceptionSlot, to: paramID))
                    previousCatchParamValue = driver.ctx.localValuesBySymbol[binding.parameterSymbol]
                    driver.ctx.localValuesBySymbol[binding.parameterSymbol] = paramID
                }

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
                    arena: arena,
                    instructions: &instructions
                )

                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    if let previousCatchParamValue {
                        driver.ctx.localValuesBySymbol[binding.parameterSymbol] = previousCatchParamValue
                    } else {
                        driver.ctx.localValuesBySymbol.removeValue(forKey: binding.parameterSymbol)
                    }
                }

                let catchTerminated = isTerminatedExpr(catchBodyResult, arena: arena, sema: sema)
                if !catchTerminated {
                    instructions.append(.copy(from: catchBodyResult, to: tryResult))
                }
                instructions.append(.copy(from: zeroValue, to: exceptionSlot))
                instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(finallyLabel))
            }

            instructions.append(.label(unmatchedCatchLabel))
            instructions.append(.jump(finallyLabel))
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
            appendThrowAwareInstructions(
                finallyInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: rethrowLabel,
                sema: sema,
                arena: arena,
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

    private func appendThrowAwareInstructions(
        _ loweredInstructions: [KIRInstruction],
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
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

    private func resolveCatchClauseBinding(
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

    private func resolveLegacyCatchClauseType(
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

    private func isCatchAllType(_ type: TypeID, sema: SemaModule) -> Bool {
        type == sema.types.anyType || type == sema.types.nullableAnyType
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
            if let conditionExprID = branch.condition {
                let conditionValueID = driver.lowerExpr(
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
        if allBranchesTerminated && elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }
}
