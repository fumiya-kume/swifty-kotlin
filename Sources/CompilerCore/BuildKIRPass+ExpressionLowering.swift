import Foundation

// Internal visibility is required for cross-file extension decomposition
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
            return lowerForExpr(exprID, iterableExpr: iterableExpr, bodyExpr: bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .whileExpr(let conditionExpr, let bodyExpr, _):
            return lowerWhileExpr(exprID, conditionExpr: conditionExpr, bodyExpr: bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
            return lowerDoWhileExpr(exprID, bodyExpr: bodyExpr, conditionExpr: conditionExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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

        case .localFunDecl(let localFunName, let localFunValueParams, _, let localFunBody, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let sig = sema.symbols.functionSignature(for: symbol)
                let funType: TypeID
                if let sig {
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

                let localFunCalleeName = callableTargetName(for: symbol, sema: sema, interner: interner)

                // Emit the local function body as a KIRFunction declaration.
                let localFunValueParamList: [KIRParameter]
                let localFunReturnType: TypeID
                if let sig {
                    localFunValueParamList = zip(sig.valueParameterSymbols, sig.parameterTypes).map { pair in
                        KIRParameter(symbol: pair.0, type: pair.1)
                    }
                    localFunReturnType = sig.returnType
                } else {
                    localFunValueParamList = localFunValueParams.enumerated().map { index, _ in
                        KIRParameter(
                            symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                            type: sema.types.anyType
                        )
                    }
                    localFunReturnType = sema.types.unitType
                }

                // Compute capture symbols by collecting referenced identifiers
                // from the local function body, filtering to those available in
                // the current scope (analogous to lambda capture analysis).
                var captureBodyExprIDs: [ExprID] = []
                switch localFunBody {
                case .block(let bodyExprIDs, _):
                    captureBodyExprIDs = bodyExprIDs
                case .expr(let bodyExprID, _):
                    captureBodyExprIDs = [bodyExprID]
                case .unit:
                    break
                }

                var referencedSymbols: [SymbolID] = []
                var seenSymbols: Set<SymbolID> = []
                for bodyExprID in captureBodyExprIDs {
                    collectBoundIdentifierSymbols(
                        in: bodyExprID,
                        ast: ast,
                        sema: sema,
                        referenced: &referencedSymbols,
                        seen: &seenSymbols
                    )
                }
                let localFunParamSymbols = Set(localFunValueParamList.map { $0.symbol })
                var captureSymbols = referencedSymbols.filter { sym in
                    if localFunParamSymbols.contains(sym) { return false }
                    if sym == symbol { return false }
                    if localValuesBySymbol[sym] != nil { return true }
                    if sym == currentImplicitReceiverSymbol,
                       currentImplicitReceiverExprID != nil { return true }
                    guard let semanticSymbol = sema.symbols.symbol(sym) else { return false }
                    return semanticSymbol.kind == .valueParameter
                }

                // Implicit receiver (this/super) is not collected by
                // collectBoundIdentifierSymbols, so check separately —
                // mirrors the post-filter in lexicalCaptureSymbolsForLambda.
                if let receiverSymbol = currentImplicitReceiverSymbol,
                   currentImplicitReceiverExprID != nil,
                   !captureSymbols.contains(receiverSymbol) {
                    let needsReceiver = captureBodyExprIDs.contains { bodyExprID in
                        containsImplicitReceiverReference(in: bodyExprID, ast: ast)
                    }
                    if needsReceiver {
                        captureSymbols.append(receiverSymbol)
                    }
                }

                var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID)] = []
                captureBindings.reserveCapacity(captureSymbols.count)
                for (index, capturedSymbol) in captureSymbols.enumerated() {
                    guard let captureValue = captureValueExpr(
                        for: capturedSymbol,
                        sema: sema,
                        arena: arena,
                        instructions: &instructions
                    ) else {
                        continue
                    }
                    let captureType = arena.exprType(captureValue) ?? typeForSymbolReference(capturedSymbol, sema: sema)
                    let captureParamSymbol = syntheticLambdaCaptureParamSymbol(
                        lambdaExprID: exprID,
                        captureIndex: index
                    )
                    let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
                    captureBindings.append((
                        capturedSymbol: capturedSymbol,
                        param: captureParam,
                        valueExpr: captureValue
                    ))
                }

                registerCallableValue(
                    funRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: captureBindings.map { $0.valueExpr }
                )

                let savedLocalValues = localValuesBySymbol
                let savedReceiverExprID = currentImplicitReceiverExprID
                let savedReceiverSymbol = currentImplicitReceiverSymbol
                let savedLoopStack = loopControlStack
                let savedNextLabel = nextLoopLabel
                defer {
                    localValuesBySymbol = savedLocalValues
                    currentImplicitReceiverExprID = savedReceiverExprID
                    currentImplicitReceiverSymbol = savedReceiverSymbol
                    loopControlStack = savedLoopStack
                    nextLoopLabel = savedNextLabel
                }

                localValuesBySymbol.removeAll(keepingCapacity: true)
                currentImplicitReceiverExprID = nil
                currentImplicitReceiverSymbol = nil
                loopControlStack.removeAll(keepingCapacity: true)
                nextLoopLabel = 10_000

                var localFunBodyInstructions: [KIRInstruction] = [.beginBlock]

                // Bind capture parameters so body references resolve correctly.
                for capture in captureBindings {
                    let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
                    localFunBodyInstructions.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
                    localValuesBySymbol[capture.capturedSymbol] = captureExpr
                    if capture.capturedSymbol == savedReceiverSymbol {
                        currentImplicitReceiverExprID = captureExpr
                        currentImplicitReceiverSymbol = capture.param.symbol
                    }
                }

                for param in localFunValueParamList {
                    let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                    localFunBodyInstructions.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
                    localValuesBySymbol[param.symbol] = paramExpr
                }

                // Re-register the local function symbol inside its own body
                // so that recursive calls resolve correctly with capture arguments.
                // Inside the body, capture arguments reference the capture *parameters*
                // (not the outer values) since we're in the body's scope.
                let bodyFunRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                localFunBodyInstructions.append(.constValue(result: bodyFunRef, value: .symbolRef(symbol)))
                localValuesBySymbol[symbol] = bodyFunRef
                registerCallableValue(
                    bodyFunRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: captureBindings.compactMap { localValuesBySymbol[$0.capturedSymbol] }
                )

                switch localFunBody {
                case .block(let bodyExprIDs, _):
                    var lastValue: KIRExprID?
                    var terminatedByReturn = false
                    for bodyExprID in bodyExprIDs {
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case .returnExpr(let value, _) = bodyExpr {
                            if let value {
                                let lowered = lowerExpr(
                                    value,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &localFunBodyInstructions
                                )
                                localFunBodyInstructions.append(.returnValue(lowered))
                            } else {
                                localFunBodyInstructions.append(.returnUnit)
                            }
                            terminatedByReturn = true
                            break
                        }
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case .throwExpr = bodyExpr {
                            _ = lowerExpr(
                                bodyExprID,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &localFunBodyInstructions
                            )
                            terminatedByReturn = true
                            break
                        }
                        lastValue = lowerExpr(
                            bodyExprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &localFunBodyInstructions
                        )
                    }
                    if !terminatedByReturn {
                        if let lastValue {
                            localFunBodyInstructions.append(.returnValue(lastValue))
                        } else {
                            localFunBodyInstructions.append(.returnUnit)
                        }
                    }
                case .expr(let bodyExprID, _):
                    let value = lowerExpr(
                        bodyExprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &localFunBodyInstructions
                    )
                    localFunBodyInstructions.append(.returnValue(value))
                case .unit:
                    localFunBodyInstructions.append(.returnUnit)
                }
                localFunBodyInstructions.append(.endBlock)

                let localFunDeclID = arena.appendDecl(
                    .function(
                        KIRFunction(
                            symbol: symbol,
                            name: localFunName,
                            params: captureBindings.map { $0.param } + localFunValueParamList,
                            returnType: localFunReturnType,
                            body: localFunBodyInstructions,
                            isSuspend: sig?.isSuspend ?? false,
                            isInline: false
                        )
                    )
                )
                pendingGeneratedCallableDeclIDs.append(localFunDeclID)
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
            return lowerArrayAccessExpr(exprID, arrayExpr: arrayExpr, indexExpr: indexExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            return lowerArrayAssignExpr(exprID, arrayExpr: arrayExpr, indexExpr: indexExpr, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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
            return lowerIfExpr(exprID, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            return lowerTryExpr(exprID, bodyExpr: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .binary(let op, let lhs, let rhs, _):
            return lowerBinaryExpr(exprID, op: op, lhs: lhs, rhs: rhs, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .call(let calleeExpr, _, let args, _):
            return lowerCallExpr(exprID, calleeExpr: calleeExpr, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .memberCall(let receiverExpr, let calleeName, _, let args, _):
            return lowerMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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
            return lowerSafeMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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

        case .lambdaLiteral(let params, let bodyExpr, _):
            return lowerLambdaLiteralExpr(
                exprID,
                params: params,
                bodyExpr: bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .callableRef(let receiverExpr, let memberName, _):
            return lowerCallableRefExpr(
                exprID,
                receiverExpr: receiverExpr,
                memberName: memberName,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .objectLiteral(let superTypes, _):
            return lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case .whenExpr(let subject, let branches, let elseExpr, _):
            return lowerWhenExpr(exprID, subject: subject, branches: branches, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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
