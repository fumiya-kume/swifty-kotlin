import Foundation

/// Delegate class for KIR lowering: ExprLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class ExprLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

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
               let receiverExprID = driver.ctx.currentImplicitReceiverExprID {
                return receiverExprID
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let localValue = driver.ctx.localValuesBySymbol[symbol] {
                    return localValue
                }
                // Inline constant initializers only for immutable (val) properties.
                // Mutable (var) properties must always load from global store at runtime.
                if let constant = propertyConstantInitializers[symbol],
                   let symInfo = sema.symbols.symbol(symbol),
                   !symInfo.flags.contains(.mutable) {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                // For top-level property symbols, emit loadGlobal so the
                // backend reads the current value from the global slot.
                if let sym = sema.symbols.symbol(symbol),
                   (sym.kind == .property || sym.kind == .field),
                   sema.symbols.parentSymbol(for: symbol) == nil || sema.symbols.symbol(sema.symbols.parentSymbol(for: symbol)!)?.kind == .package {
                    let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                    instructions.append(.loadGlobal(result: id, symbol: symbol))
                    return id
                }
                let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: id, value: .unit))
            return id

        case .forExpr(_, let iterableExpr, let bodyExpr, let label, _):
            return driver.controlFlowLowerer.lowerForExpr(exprID, iterableExpr: iterableExpr, bodyExpr: bodyExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .whileExpr(let conditionExpr, let bodyExpr, let label, _):
            return driver.controlFlowLowerer.lowerWhileExpr(exprID, conditionExpr: conditionExpr, bodyExpr: bodyExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .doWhileExpr(let bodyExpr, let conditionExpr, let label, _):
            return driver.controlFlowLowerer.lowerDoWhileExpr(exprID, bodyExpr: bodyExpr, conditionExpr: conditionExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .breakExpr(let label, _):
            let targetLabel: Int32?
            if let label {
                targetLabel = driver.ctx.loopControlStack.last(where: { $0.name == label })?.breakLabel
            } else {
                targetLabel = driver.ctx.loopControlStack.last?.breakLabel
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .continueExpr(let label, _):
            let targetLabel: Int32?
            if let label {
                targetLabel = driver.ctx.loopControlStack.last(where: { $0.name == label })?.continueLabel
            } else {
                targetLabel = driver.ctx.loopControlStack.last?.continueLabel
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
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
                driver.ctx.localValuesBySymbol[symbol] = funRef

                let localFunCalleeName = driver.lambdaLowerer.callableTargetName(for: symbol, sema: sema, interner: interner)

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
                            symbol: driver.lambdaLowerer.syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
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
                    driver.lambdaLowerer.collectBoundIdentifierSymbols(
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
                    if driver.ctx.localValuesBySymbol[sym] != nil { return true }
                    if sym == driver.ctx.currentImplicitReceiverSymbol,
                       driver.ctx.currentImplicitReceiverExprID != nil { return true }
                    guard let semanticSymbol = sema.symbols.symbol(sym) else { return false }
                    return semanticSymbol.kind == .valueParameter
                }

                // Implicit receiver (this/super) is not collected by
                // collectBoundIdentifierSymbols, so check separately —
                // mirrors the post-filter in lexicalCaptureSymbolsForLambda.
                if let receiverSymbol = driver.ctx.currentImplicitReceiverSymbol,
                   driver.ctx.currentImplicitReceiverExprID != nil,
                   !captureSymbols.contains(receiverSymbol) {
                    let needsReceiver = captureBodyExprIDs.contains { bodyExprID in
                        driver.lambdaLowerer.containsImplicitReceiverReference(in: bodyExprID, ast: ast)
                    }
                    if needsReceiver {
                        captureSymbols.append(receiverSymbol)
                    }
                }

                // Transitive capture: if a captured symbol is a callable with
                // its own captures, also capture those dependencies so call
                // sites inside the body can forward correct capture arguments.
                // Build a deterministic reverse map (KIRExprID → SymbolID) from
                // driver.ctx.localValuesBySymbol so we avoid nondeterministic Dictionary
                // iteration with first(where:).
                var exprIDToSymbol: [KIRExprID: SymbolID] = [:]
                for (sym, expr) in driver.ctx.localValuesBySymbol {
                    exprIDToSymbol[expr] = sym
                }
                var transitiveChanged = true
                while transitiveChanged {
                    transitiveChanged = false
                    for sym in captureSymbols {
                        guard let outerExpr = driver.ctx.localValuesBySymbol[sym],
                              let callableInfo = driver.ctx.callableValueInfoByExprID[outerExpr] else {
                            continue
                        }
                        for captureArg in callableInfo.captureArguments {
                            var transitiveSym: SymbolID?
                            if let found = exprIDToSymbol[captureArg] {
                                transitiveSym = found
                            } else if case .symbolRef(let argSym) = arena.expr(captureArg) {
                                transitiveSym = argSym
                            } else if captureArg == driver.ctx.currentImplicitReceiverExprID {
                                transitiveSym = driver.ctx.currentImplicitReceiverSymbol
                            }
                            if let transitiveSym, !captureSymbols.contains(transitiveSym) {
                                captureSymbols.append(transitiveSym)
                                transitiveChanged = true
                            }
                        }
                    }
                }

                var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID)] = []
                captureBindings.reserveCapacity(captureSymbols.count)
                for (index, capturedSymbol) in captureSymbols.enumerated() {
                    guard let captureValue = driver.lambdaLowerer.captureValueExpr(
                        for: capturedSymbol,
                        sema: sema,
                        arena: arena,
                        instructions: &instructions
                    ) else {
                        continue
                    }
                    let captureType = arena.exprType(captureValue) ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
                    let captureParamSymbol = driver.lambdaLowerer.syntheticLambdaCaptureParamSymbol(
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

                driver.ctx.registerCallableValue(
                    funRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: captureBindings.map { $0.valueExpr }
                )

                let scopeSnapshot = driver.ctx.saveScope()
                let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
                defer { driver.ctx.restoreScope(scopeSnapshot) }
                driver.ctx.resetScopeForFunction()

                var localFunBodyInstructions: [KIRInstruction] = [.beginBlock]

                // Bind capture parameters so body references resolve correctly.
                for capture in captureBindings {
                    let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
                    localFunBodyInstructions.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
                    driver.ctx.localValuesBySymbol[capture.capturedSymbol] = captureExpr
                    if capture.capturedSymbol == savedReceiverSymbol {
                        driver.ctx.currentImplicitReceiverExprID = captureExpr
                        driver.ctx.currentImplicitReceiverSymbol = capture.param.symbol
                    }
                }

                for param in localFunValueParamList {
                    let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                    localFunBodyInstructions.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
                    driver.ctx.localValuesBySymbol[param.symbol] = paramExpr
                }

                // Propagate callable value info for captured callables so that
                // calls inside the body find correct capture arguments.
                // Build a direct outer-expr → body-expr mapping from capture
                // bindings. This works for any expression kind (symbolRef,
                // intLiteral, etc.) without needing reverse lookups.
                var outerExprToBodyExpr: [KIRExprID: KIRExprID] = [:]
                for capture in captureBindings {
                    if let bodyExpr = driver.ctx.localValuesBySymbol[capture.capturedSymbol] {
                        outerExprToBodyExpr[capture.valueExpr] = bodyExpr
                    }
                }
                for capture in captureBindings {
                    if let outerCallableInfo = driver.ctx.callableValueInfoByExprID[capture.valueExpr],
                       let bodyCallableExpr = driver.ctx.localValuesBySymbol[capture.capturedSymbol] {
                        var remappedArgs: [KIRExprID] = []
                        var mappingFailed = false
                        for argExpr in outerCallableInfo.captureArguments {
                            if let bodyArgExpr = outerExprToBodyExpr[argExpr] {
                                remappedArgs.append(bodyArgExpr)
                            } else if case .symbolRef(let argSym) = arena.expr(argExpr),
                                      let bodyArgExpr = driver.ctx.localValuesBySymbol[argSym] {
                                remappedArgs.append(bodyArgExpr)
                            } else {
                                assertionFailure("BuildKIRPhase: failed to remap capture argument for local function body")
                                mappingFailed = true
                                break
                            }
                        }
                        if !mappingFailed {
                            driver.ctx.registerCallableValue(
                                bodyCallableExpr,
                                symbol: outerCallableInfo.symbol,
                                callee: outerCallableInfo.callee,
                                captureArguments: remappedArgs
                            )
                        }
                    }
                }

                // Re-register the local function symbol inside its own body
                // so that recursive calls resolve correctly with capture arguments.
                // Inside the body, capture arguments reference the capture *parameters*
                // (not the outer values) since we're in the body's scope.
                let bodyFunRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                localFunBodyInstructions.append(.constValue(result: bodyFunRef, value: .symbolRef(symbol)))
                driver.ctx.localValuesBySymbol[symbol] = bodyFunRef
                let recursiveCaptureArguments: [KIRExprID] = captureBindings.map { binding in
                    guard let value = driver.ctx.localValuesBySymbol[binding.capturedSymbol] else {
                        preconditionFailure("BuildKIRPhase: missing capture binding for recursive local function '\(symbol)'")
                    }
                    return value
                }
                driver.ctx.registerCallableValue(
                    bodyFunRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: recursiveCaptureArguments
                )

                switch localFunBody {
                case .block(let bodyExprIDs, _):
                    var lastValue: KIRExprID?
                    var terminatedByReturn = false
                    for bodyExprID in bodyExprIDs {
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case .returnExpr(let value, _, _) = bodyExpr {
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
                        // Detect nested termination (e.g., if/when/try with return in all branches)
                        if let lastValue, driver.controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                            terminatedByReturn = true
                            break
                        }
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
                driver.ctx.pendingGeneratedCallableDeclIDs.append(localFunDeclID)
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
                    driver.ctx.localValuesBySymbol[symbol] = initializerID
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
                // Check if this is a top-level property assignment (not a local variable).
                // Top-level properties need a copy to global storage rather than just
                // updating localValuesBySymbol (which wouldn't persist across function calls).
                // Top-level properties have no parentSymbol (nil) or parent is a package.
                // Class member properties always have parentSymbol set to a class/object.
                if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property, {
                    let p = sema.symbols.parentSymbol(for: symbol)
                    let pk = p.flatMap({ sema.symbols.symbol($0) })?.kind
                    return pk == nil || pk == .package
                }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    instructions.append(.copy(from: valueID, to: globalRef))
                } else {
                    driver.ctx.localValuesBySymbol[symbol] = valueID
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .indexedAccess(let receiverExpr, let indices, _):
            return driver.callLowerer.lowerIndexedAccessExpr(exprID, receiverExpr: receiverExpr, indices: indices, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .indexedAssign(let receiverExpr, let indices, let valueExpr, _):
            return driver.callLowerer.lowerIndexedAssignExpr(exprID, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .returnExpr(let value, _, _):
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
            return driver.controlFlowLowerer.lowerIfExpr(exprID, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            return driver.controlFlowLowerer.lowerTryExpr(exprID, bodyExpr: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .binary(let op, let lhs, let rhs, _):
            return driver.callLowerer.lowerBinaryExpr(exprID, op: op, lhs: lhs, rhs: rhs, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .call(let calleeExpr, _, let args, _):
            return driver.callLowerer.lowerCallExpr(exprID, calleeExpr: calleeExpr, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .memberCall(let receiverExpr, let calleeName, _, let args, _):
            return driver.callLowerer.lowerMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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
            return driver.callLowerer.lowerSafeMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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
                // Top-level property compound assignment needs a copy to global storage.
                // Top-level properties have no parentSymbol (nil) or parent is a package.
                // Class member properties always have parentSymbol set to a class/object.
                if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property, {
                    let p = sema.symbols.parentSymbol(for: symbol)
                    let pk = p.flatMap({ sema.symbols.symbol($0) })?.kind
                    return pk == nil || pk == .package
                }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    instructions.append(.copy(from: valueID, to: globalRef))
                } else {
                    driver.ctx.localValuesBySymbol[symbol] = valueID
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .indexedCompoundAssign(_, let receiverExpr, let indices, let valueExpr, _):
            return driver.callLowerer.lowerIndexedCompoundAssignExpr(exprID, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

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

        case .lambdaLiteral(let params, let bodyExpr, _, _):
            return driver.lambdaLowerer.lowerLambdaLiteralExpr(
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
            return driver.lambdaLowerer.lowerCallableRefExpr(
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
            return driver.objectLiteralLowerer.lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case .whenExpr(let subject, let branches, let elseExpr, _):
            return driver.controlFlowLowerer.lowerWhenExpr(exprID, subject: subject, branches: branches, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .blockExpr(let statements, let trailingExpr, _):
            for stmt in statements {
                let loweredStmt = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // If the statement is a terminator (return/throw), stop lowering
                if driver.controlFlowLowerer.isTerminatedExpr(loweredStmt, arena: arena, sema: sema) {
                    return loweredStmt
                }
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
            if let receiverExprID = driver.ctx.currentImplicitReceiverExprID {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .thisRef:
            if let receiverExprID = driver.ctx.currentImplicitReceiverExprID {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .inExpr(let lhsExpr, let rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [rhsID, lhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .notInExpr(let lhsExpr, let rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let containsResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [rhsID, lhsID],
                result: containsResult,
                canThrow: false,
                thrownResult: nil
            ))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.unary(op: .not, operand: containsResult, result: result))
            return result

        case .destructuringDecl(let names, _, let initializer, _):
            // Lower: val (a, b) = expr  →  tmp = expr; a = tmp.component1(); b = tmp.component2()
            let rhsID = lowerExpr(
                initializer, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            for (index, name) in names.enumerated() {
                guard let name else {
                    // Underscore — skip
                    continue
                }
                let componentIndex = index + 1
                let componentName = interner.intern("component\(componentIndex)")

                // Look up the symbol defined by Sema for this variable first,
                // so we can use its per-component type (not the expression-level Unit type)
                let candidates = sema.symbols.lookupAll(fqName: [
                    interner.intern("__destructuring_\(exprID.rawValue)"),
                    name
                ])
                let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
                let componentResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: componentType)
                instructions.append(.call(
                    symbol: nil,
                    callee: componentName,
                    arguments: [rhsID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                // Bind the destructured variable to the component result
                if let symbol = candidates.first {
                    driver.ctx.localValuesBySymbol[symbol] = componentResult
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .forDestructuringExpr(let names, let iterableExpr, let bodyExpr, _):
            // Lower as a regular for-loop, but inside the body, destructure the element
            // Delegate to control flow lowerer for loop structure
            return driver.controlFlowLowerer.lowerForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }
}
