import Foundation

extension BuildKIRPhase {
    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral(let value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case .longLiteral(let value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case .floatLiteral(let value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case .doubleLiteral(let value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case .charLiteral(let value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case .boolLiteral(let value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case .stringLiteral(let value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case .stringTemplate(let parts, _):
            var partIDs: [KIRExprID] = []
            for part in parts {
                switch part {
                case .literal(let interned):
                    let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                    instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                    partIDs.append(partID)
                case .expression(let exprID):
                    let lowered = lowerExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let exprType = sema.bindings.exprTypes[exprID]
                    if let exprType, exprType != stringType {
                        let tag: Int64
                        switch sema.types.kind(of: exprType) {
                        case .primitive(.boolean, _):
                            tag = 2
                        case .primitive(.string, _):
                            tag = 3
                        default:
                            tag = 1
                        }
                        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
                        instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_any_to_string"),
                            arguments: [lowered, tagID],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        partIDs.append(converted)
                    } else {
                        partIDs.append(lowered)
                    }
                }
            }
            if partIDs.isEmpty {
                let emptyStr = interner.intern("")
                let id = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: id, value: .stringLiteral(emptyStr)))
                return id
            }
            var accumulated = partIDs[0]
            for i in 1..<partIDs.count {
                let concatResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [accumulated, partIDs[i]],
                    result: concatResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                accumulated = concatResult
            }
            return accumulated

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if interner.resolve(name) == "this",
               let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let localValue = localValuesBySymbol[symbol] {
                    return localValue
                }
                if let constant = propertyConstantInitializers[symbol] {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: id, value: .unit))
            return id

        case .forExpr(_, let iterableExpr, let bodyExpr, _):
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

        case .whileExpr(let conditionExpr, let bodyExpr, _):
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

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
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

        case .breakExpr:
            if let breakLabel = loopControlStack.last?.breakLabel {
                instructions.append(.jump(breakLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .continueExpr:
            if let continueLabel = loopControlStack.last?.continueLabel {
                instructions.append(.jump(continueLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localFunDecl(_, _, _, _, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let funType: TypeID
                if let sig = sema.symbols.functionSignature(for: symbol) {
                    funType = sema.types.make(.functionType(FunctionType(
                        params: sig.parameterTypes,
                        returnType: sig.returnType,
                        isSuspend: sig.isSuspend,
                        nullability: .nonNull
                    )))
                } else {
                    funType = boundType ?? sema.types.anyType
                }
                let funRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                instructions.append(.constValue(result: funRef, value: .symbolRef(symbol)))
                localValuesBySymbol[symbol] = funRef
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localDecl(_, _, _, let initializer, _):
            if let initializer {
                let initializerID = lowerExpr(
                    initializer,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if let symbol = sema.bindings.identifierSymbols[exprID] {
                    localValuesBySymbol[symbol] = initializerID
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localAssign(_, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .arrayAccess(let arrayExpr, let indexExpr, _):
            let arrayID = lowerExpr(
                arrayExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let indexID = lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [arrayID, indexID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            let arrayID = lowerExpr(
                arrayExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let indexID = lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexID, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .returnExpr(let value, _):
            if let value {
                let lowered = lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.returnValue(lowered))
            } else {
                instructions.append(.returnUnit)
            }
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
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

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
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



        case .binary(let op, let lhs, let rhs, _):
            let lhsID = lowerExpr(
                lhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
            if let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil {
                let normalizedResult = normalizedCallArguments(
                    providedArguments: [rhsID],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    spreadFlags: [false],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                var finalArguments = normalizedResult.arguments
                finalArguments.insert(lhsID, at: 0)
                if normalizedResult.defaultMask != 0 {
                    if let sig = sema.symbols.functionSignature(for: callBinding.chosenCallee),
                       !sig.reifiedTypeParameterIndices.isEmpty {
                        for index in sig.reifiedTypeParameterIndices.sorted() {
                            let concreteType = index < callBinding.substitutedTypeArguments.count
                                ? callBinding.substitutedTypeArguments[index]
                                : sema.types.anyType
                            let tokenExpr = arena.appendExpr(
                                .intLiteral(Int64(concreteType.rawValue)),
                                type: intType
                            )
                            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                            finalArguments.append(tokenExpr)
                        }
                    }
                    let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                    instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                    finalArguments.append(maskExpr)
                    let stubName = interner.intern(
                        (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                    )
                    let stubSym = defaultStubSymbol(for: callBinding.chosenCallee)
                    instructions.append(.call(
                        symbol: stubSym,
                        callee: stubName,
                        arguments: finalArguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    if let sig = sema.symbols.functionSignature(for: callBinding.chosenCallee),
                       !sig.reifiedTypeParameterIndices.isEmpty {
                        for index in sig.reifiedTypeParameterIndices.sorted() {
                            let concreteType = index < callBinding.substitutedTypeArguments.count
                                ? callBinding.substitutedTypeArguments[index]
                                : sema.types.anyType
                            let tokenExpr = arena.appendExpr(
                                .intLiteral(Int64(concreteType.rawValue)),
                                type: intType
                            )
                            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                            finalArguments.append(tokenExpr)
                        }
                    }
                    let loweredCalleeName: InternedString
                    if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                       !externalLinkName.isEmpty {
                        loweredCalleeName = interner.intern(externalLinkName)
                    } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                        loweredCalleeName = symbol.name
                    } else {
                        loweredCalleeName = binaryOperatorFunctionName(for: op, interner: interner)
                    }
                    instructions.append(.call(
                        symbol: callBinding.chosenCallee,
                        callee: loweredCalleeName,
                        arguments: finalArguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
            if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: interner.intern("kk_string_concat"),
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                return result
            }
            if let runtimeCallee = builtinBinaryRuntimeCallee(for: op, interner: interner) {
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                return result
            }
            let kirOp: KIRBinaryOp
            switch op {
            case .add:
                kirOp = .add
            case .subtract:
                kirOp = .subtract
            case .multiply:
                kirOp = .multiply
            case .divide:
                kirOp = .divide
            case .modulo:
                kirOp = .modulo
            case .equal:
                kirOp = .equal
            case .notEqual:
                kirOp = .notEqual
            case .lessThan:
                kirOp = .lessThan
            case .lessOrEqual:
                kirOp = .lessOrEqual
            case .greaterThan:
                kirOp = .greaterThan
            case .greaterOrEqual:
                kirOp = .greaterOrEqual
            case .logicalAnd:
                kirOp = .logicalAnd
            case .logicalOr:
                kirOp = .logicalOr
            case .elvis:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_elvis"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            case .rangeTo:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_rangeTo"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
            return result

        case .call(let calleeExpr, _, let args, _):
            let calleeName: InternedString
            if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
                calleeName = name
            } else {
                calleeName = sema.symbols.allSymbols().first?.name ?? InternedString()
            }
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            let callNormalized = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArgIDs = callNormalized.arguments
            if callNormalized.defaultMask != 0, let chosen {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                if let callBinding,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArgIDs.append(tokenExpr)
                    }
                }
                let maskExpr = arena.appendExpr(.intLiteral(Int64(callNormalized.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(callNormalized.defaultMask))))
                finalArgIDs.append(maskExpr)
                let stubName = interner.intern(interner.resolve(calleeName) + "$default")
                let stubSym = defaultStubSymbol(for: chosen)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                if let callBinding, let chosen,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArgIDs.append(tokenExpr)
                    }
                }
                let loweredCalleeName: InternedString
                if let chosen,
                   let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if chosen == nil {
                    loweredCalleeName = loweredRuntimeBuiltinCallee(
                        for: calleeName,
                        argumentCount: finalArgIDs.count,
                        interner: interner
                    ) ?? calleeName
                } else {
                    loweredCalleeName = calleeName
                }
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredCalleeName,
                    arguments: finalArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result

        case .memberCall(let receiverExpr, let calleeName, _, let args, _):
            let loweredReceiverID = lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            let memberNormalized = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = memberNormalized.arguments
            if let chosen,
               let signature = sema.symbols.functionSignature(for: chosen),
               signature.receiverType != nil {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
            if memberNormalized.defaultMask != 0, let chosen {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                if let callBinding,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArguments.append(tokenExpr)
                    }
                }
                let maskExpr = arena.appendExpr(.intLiteral(Int64(memberNormalized.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(memberNormalized.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(interner.resolve(calleeName) + "$default")
                let stubSym = defaultStubSymbol(for: chosen)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                if let callBinding, let chosen,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArguments.append(tokenExpr)
                    }
                }
                let loweredMemberCalleeName: InternedString
                if let chosen,
                   let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                   !externalLinkName.isEmpty {
                    loweredMemberCalleeName = interner.intern(externalLinkName)
                } else {
                    loweredMemberCalleeName = calleeName
                }
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result

        case .unaryExpr(let op, let operandExpr, _):
            let operandID = lowerExpr(
                operandExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            switch op {
            case .unaryPlus:
                return operandID
            case .unaryMinus:
                let zero = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? intType)
                instructions.append(.binary(op: .subtract, lhs: zero, rhs: operandID, result: result))
                return result
            case .not:
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
                instructions.append(.binary(op: .equal, lhs: operandID, rhs: falseValue, result: result))
                return result
            }

        case .isCheck(let exprToCheck, _, _, _):
            let operandID = lowerExpr(
                exprToCheck,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .asCast(let exprToCast, _, _, _):
            let operandID = lowerExpr(
                exprToCast,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_cast"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .nullAssert(let innerExpr, _):
            let operandID = lowerExpr(
                innerExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.nullAssert(operand: operandID, result: result))
            return result

        case .safeMemberCall(let receiverExpr, let calleeName, _, let args, _):
            let loweredReceiverID = lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            let safeNormalized = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = safeNormalized.arguments
            if let chosen,
               let signature = sema.symbols.functionSignature(for: chosen),
               signature.receiverType != nil {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
            if safeNormalized.defaultMask != 0, let chosen {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                if let callBinding,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArguments.append(tokenExpr)
                    }
                }
                let maskExpr = arena.appendExpr(.intLiteral(Int64(safeNormalized.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(safeNormalized.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(interner.resolve(calleeName) + "$default")
                let stubSym = defaultStubSymbol(for: chosen)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                if let callBinding, let chosen,
                   let sig = sema.symbols.functionSignature(for: chosen),
                   !sig.reifiedTypeParameterIndices.isEmpty {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    for index in sig.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(Int64(concreteType.rawValue)),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                        finalArguments.append(tokenExpr)
                    }
                }
                let loweredMemberCalleeName: InternedString
                if let chosen,
                   let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                   !externalLinkName.isEmpty {
                    loweredMemberCalleeName = interner.intern(externalLinkName)
                } else {
                    loweredMemberCalleeName = calleeName
                }
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result

        case .compoundAssign(_, _, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .throwExpr(let valueExpr, _):
            let thrownValue = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.rethrow(value: thrownValue))
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .whenExpr(let subject, let branches, let elseExpr, _):
            let subjectID = lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
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
                    let matchesID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                    instructions.append(.binary(
                        op: .equal,
                        lhs: subjectID,
                        rhs: conditionValueID,
                        result: matchesID
                    ))
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

        case .blockExpr(let statements, let trailingExpr, _):
            for stmt in statements {
                _ = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            if let trailingExpr {
                return lowerExpr(
                    trailingExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .superRef:
            if let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .thisRef:
            if let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
    }
}
