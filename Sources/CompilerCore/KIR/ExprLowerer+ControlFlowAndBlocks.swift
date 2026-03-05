import Foundation

extension ExprLowerer {
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
        case let .intLiteral(value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case let .longLiteral(value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case let .uintLiteral(value, _):
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let id = arena.appendExpr(.uintLiteral(value), type: boundType ?? uintType)
            instructions.append(.constValue(result: id, value: .uintLiteral(value)))
            return id

        case let .ulongLiteral(value, _):
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let id = arena.appendExpr(.ulongLiteral(value), type: boundType ?? ulongType)
            instructions.append(.constValue(result: id, value: .ulongLiteral(value)))
            return id

        case let .floatLiteral(value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case let .doubleLiteral(value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case let .charLiteral(value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case let .boolLiteral(value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case let .stringLiteral(value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case let .stringTemplate(parts, _):
            var partIDs: [KIRExprID] = []
            for part in parts {
                switch part {
                case let .literal(interned):
                    let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                    instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                    partIDs.append(partID)
                case let .expression(exprID):
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
                        let tag: Int64 = switch sema.types.kind(of: exprType) {
                        case .primitive(.boolean, _):
                            2
                        case .primitive(.string, _):
                            3
                        default:
                            1
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
            for i in 1 ..< partIDs.count {
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

        case let .nameRef(name, _):
            let nullID = interner.intern("null")
            let thisID = interner.intern("this")
            if name == nullID {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if name == thisID,
               let receiverExprID = driver.ctx.currentImplicitReceiverExprID
            {
                return receiverExprID
            }
            // STDLIB-004: Implicit receiver member access (e.g. `length` inside
            // `run { length }` resolves as `this.length`).
            if let memberName = sema.bindings.implicitReceiverMemberNames[exprID],
               let receiverExprID = driver.ctx.currentImplicitReceiverExprID
            {
                let receiverType = arena.exprType(receiverExprID) ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                let memberStr = interner.resolve(memberName)
                let resultType = boundType ?? sema.types.anyType
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)), type: resultType
                )

                // String properties
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    if memberStr == "length" {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_string_length"),
                            arguments: [receiverExprID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                }

                // Collection properties: size, isEmpty
                if memberStr == "size" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_collection_size"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if memberStr == "isEmpty" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_collection_isEmpty"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                // General fallback: try to find a getter symbol for the property
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let localValue = driver.ctx.localValuesBySymbol[symbol]
                {
                    return localValue
                }
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let localValue = driver.ctx.localValuesBySymbol[symbol] {
                    return localValue
                }
                // Inline constant initializers only for immutable (val) properties.
                // Mutable (var) properties must always load from global store at runtime.
                if let constant = propertyConstantInitializers[symbol],
                   let symInfo = sema.symbols.symbol(symbol),
                   !symInfo.flags.contains(.mutable)
                {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                // For top-level property symbols, emit loadGlobal so the
                // backend reads the current value from the global slot.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property || sym.kind == .field,
                   sema.symbols.parentSymbol(for: symbol) == nil || sema.symbols.symbol(sema.symbols.parentSymbol(for: symbol)!)?.kind == .package
                {
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

        case let .forExpr(_, iterableExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerForExpr(exprID, iterableExpr: iterableExpr, bodyExpr: bodyExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .whileExpr(conditionExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerWhileExpr(exprID, conditionExpr: conditionExpr, bodyExpr: bodyExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .doWhileExpr(bodyExpr, conditionExpr, label, _):
            return driver.controlFlowLowerer.lowerDoWhileExpr(exprID, bodyExpr: bodyExpr, conditionExpr: conditionExpr, label: label, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .breakExpr(label, _):
            let targetLabel: Int32? = if let label {
                driver.ctx.loopControlStack.last(where: { $0.name == label })?.breakLabel
            } else {
                driver.ctx.loopControlStack.last?.breakLabel
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .continueExpr(label, _):
            let targetLabel: Int32? = if let label {
                driver.ctx.loopControlStack.last(where: { $0.name == label })?.continueLabel
            } else {
                driver.ctx.loopControlStack.last?.continueLabel
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .localFunDecl(localFunName, localFunValueParams, _, localFunBody, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let sig = sema.symbols.functionSignature(for: symbol)
                let funType: TypeID = if let sig {
                    sema.types.make(.functionType(FunctionType(
                        params: sig.parameterTypes,
                        returnType: sig.returnType,
                        isSuspend: sig.isSuspend,
                        nullability: .nonNull
                    )))
                } else {
                    boundType ?? sema.types.anyType
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
                    localFunValueParamList = localFunValueParams.indices.map { index in
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
                case let .block(bodyExprIDs, _):
                    captureBodyExprIDs = bodyExprIDs
                case let .expr(bodyExprID, _):
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
                let localFunParamSymbols = Set(localFunValueParamList.map(\.symbol))
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
                   !captureSymbols.contains(receiverSymbol)
                {
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
                              let callableInfo = driver.ctx.callableValueInfoByExprID[outerExpr]
                        else {
                            continue
                        }
                        for captureArg in callableInfo.captureArguments {
                            var transitiveSym: SymbolID?
                            if let found = exprIDToSymbol[captureArg] {
                                transitiveSym = found
                            } else if case let .symbolRef(argSym) = arena.expr(captureArg) {
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
                    captureArguments: captureBindings.map(\.valueExpr)
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
                       let bodyCallableExpr = driver.ctx.localValuesBySymbol[capture.capturedSymbol]
                    {
                        var remappedArgs: [KIRExprID] = []
                        var mappingFailed = false
                        for argExpr in outerCallableInfo.captureArguments {
                            if let bodyArgExpr = outerExprToBodyExpr[argExpr] {
                                remappedArgs.append(bodyArgExpr)
                            } else if case let .symbolRef(argSym) = arena.expr(argExpr),
                                      let bodyArgExpr = driver.ctx.localValuesBySymbol[argSym]
                            {
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
                case let .block(bodyExprIDs, _):
                    var lastValue: KIRExprID?
                    var terminatedByReturn = false
                    for bodyExprID in bodyExprIDs {
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case let .returnExpr(value, _, _) = bodyExpr
                        {
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
                           case .throwExpr = bodyExpr
                        {
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
                case let .expr(bodyExprID, _):
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
                            params: captureBindings.map(\.param) + localFunValueParamList,
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

        case let .localDecl(_, _, _, initializer, _):
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

        case let .localAssign(_, valueExpr, _):
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
                // Check if this is a top-level or object-member property assignment.
                // These need a copy to global storage rather than just updating
                // localValuesBySymbol (which wouldn't persist across function calls).
                // Top-level properties have nil or .package parent.
                // Object member properties have .object parent.
                if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property, {
                    let p = sema.symbols.parentSymbol(for: symbol)
                    let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                    return pk == nil || pk == .package || pk == .object
                }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    instructions.append(.copy(from: valueID, to: globalRef))
                } else {
                    if let storageID = driver.ctx.localValuesBySymbol[symbol] {
                        // Mutable local already has storage: emit a copy so the C variable
                        // is updated in place, preserving the value across loop iterations.
                        instructions.append(.copy(from: valueID, to: storageID))
                    } else {
                        driver.ctx.localValuesBySymbol[symbol] = valueID
                    }
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .memberAssign(receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .indexedAccess(receiverExpr, indices, _):
            return driver.callLowerer.lowerIndexedAccessExpr(exprID, receiverExpr: receiverExpr, indices: indices, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .indexedAssign(receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedAssignExpr(exprID, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .returnExpr(value, _, _):
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

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return driver.controlFlowLowerer.lowerIfExpr(exprID, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .tryExpr(bodyExpr, catchClauses, finallyExpr, _):
            return driver.controlFlowLowerer.lowerTryExpr(exprID, bodyExpr: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .binary(op, lhs, rhs, _):
            return driver.callLowerer.lowerBinaryExpr(exprID, op: op, lhs: lhs, rhs: rhs, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .call(calleeExpr, _, args, _):
            return driver.callLowerer.lowerCallExpr(exprID, calleeExpr: calleeExpr, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .memberCall(receiverExpr, calleeName, _, args, _):
            return driver.callLowerer.lowerMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .unaryExpr(op, operandExpr, _):
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

        case let .isCheck(exprToCheck, typeRefID, negated, _):
            let operandID = lowerExpr(
                exprToCheck,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let typeToken: KIRExprID = if let targetType = sema.bindings.isCheckTargetType(for: exprID) {
                lowerTypeCheckTokenExpr(
                    targetType: targetType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            } else {
                lowerIsCheckTypeTokenExpr(
                    typeRefID: typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            }
            let isResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [operandID, typeToken],
                result: isResult,
                canThrow: false,
                thrownResult: nil
            ))
            guard negated else {
                return isResult
            }
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            let negatedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.binary(op: .equal, lhs: isResult, rhs: falseValue, result: negatedResult))
            return negatedResult

        case let .asCast(exprToCast, typeRefID, isSafe, _):
            let operandID = lowerExpr(
                exprToCast,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let typeToken: KIRExprID = if let targetType = sema.bindings.castTargetType(for: exprID) {
                lowerTypeCheckTokenExpr(
                    targetType: targetType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            } else {
                lowerIsCheckTypeTokenExpr(
                    typeRefID: typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(isSafe ? "kk_op_safe_cast" : "kk_op_cast"),
                arguments: [operandID, typeToken],
                result: result,
                canThrow: !isSafe,
                thrownResult: nil
            ))
            return result

        case let .nullAssert(innerExpr, _):
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

        case let .safeMemberCall(receiverExpr, calleeName, _, args, _):
            return driver.callLowerer.lowerSafeMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .compoundAssign(op, _, valueExpr, _):
            let rhsID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let kirOp: KIRBinaryOp = switch op {
            case .plusAssign: .add
            case .minusAssign: .subtract
            case .timesAssign: .multiply
            case .divAssign: .divide
            case .modAssign: .modulo
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                // Top-level or object-member property compound assignment
                // needs a copy to global storage. Top-level properties have
                // nil or .package parent; object members have .object parent.
                if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property, {
                    let p = sema.symbols.parentSymbol(for: symbol)
                    let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                    return pk == nil || pk == .package || pk == .object
                }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    let loadedValue = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.loadGlobal(result: loadedValue, symbol: symbol))
                    let resultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: propType)
                    instructions.append(.binary(op: kirOp, lhs: loadedValue, rhs: rhsID, result: resultID))
                    instructions.append(.copy(from: resultID, to: globalRef))
                } else {
                    if let storageID = driver.ctx.localValuesBySymbol[symbol] {
                        // Compute lhs op rhs and update storage in place so the value
                        // persists across loop iterations.
                        let resultType = arena.exprType(storageID) ?? sema.types.intType
                        let resultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
                        instructions.append(.binary(op: kirOp, lhs: storageID, rhs: rhsID, result: resultID))
                        instructions.append(.copy(from: resultID, to: storageID))
                    } else {
                        // No existing local value — create a symbol reference as lhs
                        // so compound assignment still computes lhs op rhs.
                        let lhsID = arena.appendExpr(.symbolRef(symbol), type: boundType ?? sema.types.anyType)
                        instructions.append(.constValue(result: lhsID, value: .symbolRef(symbol)))
                        let resultType = arena.exprType(lhsID) ?? sema.types.intType
                        let resultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
                        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: resultID))
                        driver.ctx.localValuesBySymbol[symbol] = resultID
                    }
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedCompoundAssignExpr(exprID, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .throwExpr(valueExpr, _):
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

        case let .lambdaLiteral(params, bodyExpr, _, _):
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

        case let .callableRef(receiverExpr, memberName, _):
            // T::class  — emit the type token for the reified type parameter
            if interner.resolve(memberName) == "class",
               sema.bindings.classRefTargetType(for: exprID) != nil
            {
                // The actual lowering (to kk_type_token_simple_name) happens
                // at the enclosing memberCall site (T::class.simpleName).
                // Here we just emit a placeholder unit value; the memberCall
                // lowerer will bypass this and emit the runtime call directly.
                let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.anyType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
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

        case let .objectLiteral(superTypes, _):
            return driver.objectLiteralLowerer.lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case let .whenExpr(subject, branches, elseExpr, _):
            return driver.controlFlowLowerer.lowerWhenExpr(exprID, subject: subject, branches: branches, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case let .blockExpr(statements, trailingExpr, _):
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

        case let .inExpr(lhsExpr, rhsExpr, _):
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

        case let .notInExpr(lhsExpr, rhsExpr, _):
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
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            instructions.append(.binary(op: .equal, lhs: containsResult, rhs: falseValue, result: result))
            return result

        case let .destructuringDecl(names, _, initializer, _):
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
                    name,
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

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, _):
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
