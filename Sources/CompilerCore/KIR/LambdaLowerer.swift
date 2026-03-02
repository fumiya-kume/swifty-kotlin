import Foundation

struct KIRCallableValueInfo {
    let symbol: SymbolID
    let callee: InternedString
    let captureArguments: [KIRExprID]
}

/// Delegate class for KIR lowering: LambdaLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class LambdaLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerLambdaLiteralExpr(
        _ exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let functionType = boundType.flatMap { typeID -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                return nil
            }
            return functionType
        }

        let lambdaSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)

        let lambdaParameterTypes: [TypeID] = params.indices.map { index in
            if let functionType, index < functionType.params.count {
                return functionType.params[index]
            }
            return sema.types.anyType
        }
        let lambdaReturnType = functionType?.returnType
            ?? sema.bindings.exprTypes[bodyExpr]
            ?? sema.types.anyType

        let captureSymbols = computeCaptureSymbolsForLambda(
            lambdaExprID: exprID,
            lambdaParamCount: params.count,
            lambdaBodyExprID: bodyExpr,
            ast: ast,
            sema: sema
        )

        var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID)] = []
        captureBindings.reserveCapacity(captureSymbols.count)
        for (index, symbol) in captureSymbols.enumerated() {
            guard let captureValueExpr = captureValueExpr(
                for: symbol,
                sema: sema,
                arena: arena,
                instructions: &instructions
            ) else {
                continue
            }
            let captureType = arena.exprType(captureValueExpr) ?? typeForSymbolReference(symbol, sema: sema)
            let captureParamSymbol = syntheticLambdaCaptureParamSymbol(
                lambdaExprID: exprID,
                captureIndex: index
            )
            let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
            captureBindings.append((
                capturedSymbol: symbol,
                param: captureParam,
                valueExpr: captureValueExpr
            ))
        }

        let lambdaParameters: [KIRParameter] = params.indices.map { index in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        let scopeSnapshot = driver.ctx.saveScope()
        let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in captureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            driver.ctx.localValuesBySymbol[capture.capturedSymbol] = captureExpr
            if capture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.currentImplicitReceiverExprID = captureExpr
                driver.ctx.currentImplicitReceiverSymbol = capture.param.symbol
            }
        }
        for lambdaParam in lambdaParameters {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.localValuesBySymbol[lambdaParam.symbol] = paramExpr
        }

        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
        lambdaBody.append(.returnValue(loweredBody))
        lambdaBody.append(.endBlock)

        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: captureBindings.map(\.param) + lambdaParameters,
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: functionType?.isSuspend ?? false,
                    isInline: false
                )
            )
        )
        driver.ctx.pendingGeneratedCallableDeclIDs.append(lambdaDecl)

        let lambdaValueType = boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: functionType?.isSuspend ?? false,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: captureBindings.map(\.valueExpr)
        )
        return lambdaValueExpr
    }

    func lowerCallableRefExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        var captureArguments: [KIRExprID] = []
        if let receiverExpr {
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            captureArguments.append(loweredReceiver)
        }

        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )

        let callableSymbol: SymbolID
        let callableName: InternedString
        if let targetSymbol {
            callableSymbol = targetSymbol
            callableName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
        } else {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let fallbackFunctionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                    return nil
                }
                return functionType
            }
            let fallbackValueParamTypes = fallbackFunctionType?.params ?? []
            let fallbackReturnType = fallbackFunctionType?.returnType ?? sema.types.anyType

            let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(captureExpr) ?? sema.types.anyType
                )
            }
            let valueParams: [KIRParameter] = fallbackValueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            var body: [KIRInstruction] = [.beginBlock]
            switch sema.types.kind(of: fallbackReturnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                let zero = arena.appendExpr(.intLiteral(0), type: fallbackReturnType)
                body.append(.constValue(result: zero, value: .intLiteral(0)))
                body.append(.returnValue(zero))
            }
            body.append(.endBlock)

            let fallbackDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: captureParams + valueParams,
                        returnType: fallbackReturnType,
                        body: body,
                        isSuspend: fallbackFunctionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.pendingGeneratedCallableDeclIDs.append(fallbackDecl)
        }

        let callableType = boundType ?? typeForSymbolReference(callableSymbol, sema: sema)
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: captureArguments
        )
        return callableExpr
    }

    func syntheticLambdaName(for exprID: ExprID, interner: StringInterner) -> InternedString {
        interner.intern("kk_lambda_\(exprID.rawValue)")
    }

    func syntheticLambdaParamSymbol(lambdaExprID: ExprID, paramIndex: Int) -> SymbolID {
        boundedNegativeSyntheticSymbol(
            Int64(-1_000_000)
                - Int64(lambdaExprID.rawValue) * 256
                - Int64(paramIndex)
        )
    }

    func syntheticLambdaCaptureParamSymbol(lambdaExprID: ExprID, captureIndex: Int) -> SymbolID {
        boundedNegativeSyntheticSymbol(
            Int64(-2_000_000)
                - Int64(lambdaExprID.rawValue) * 256
                - Int64(captureIndex)
        )
    }

    private func boundedNegativeSyntheticSymbol(_ rawValue: Int64) -> SymbolID {
        let bounded = min(Int64(-2), max(Int64(Int32.min), rawValue))
        return SymbolID(rawValue: Int32(bounded))
    }

    func callableTargetName(
        for symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        if let externalLinkName = sema.symbols.externalLinkName(for: symbol),
           !externalLinkName.isEmpty
        {
            return interner.intern(externalLinkName)
        }
        return sema.symbols.symbol(symbol)?.name ?? interner.intern("kk_unknown_callable")
    }

    func typeForSymbolReference(_ symbol: SymbolID, sema: SemaModule) -> TypeID {
        if let functionSignature = sema.symbols.functionSignature(for: symbol) {
            return sema.types.make(
                .functionType(
                    FunctionType(
                        receiver: functionSignature.receiverType,
                        params: functionSignature.parameterTypes,
                        returnType: functionSignature.returnType,
                        isSuspend: functionSignature.isSuspend,
                        nullability: .nonNull
                    )
                )
            )
        }
        if let propertyType = sema.symbols.propertyType(for: symbol) {
            return propertyType
        }
        if let valueParameterType = typeForValueParameterSymbol(symbol, sema: sema) {
            return valueParameterType
        }
        return sema.types.anyType
    }

    private func typeForValueParameterSymbol(_ symbol: SymbolID, sema: SemaModule) -> TypeID? {
        let kinds: [SymbolKind] = [.function, .constructor]
        for kind in kinds {
            for candidateID in sema.symbols.symbols(ofKind: kind) {
                guard let signature = sema.symbols.functionSignature(for: candidateID),
                      let index = signature.valueParameterSymbols.firstIndex(of: symbol),
                      index < signature.parameterTypes.count
                else {
                    continue
                }
                return signature.parameterTypes[index]
            }
        }
        return nil
    }

    private func resolveCallableRefTargetSymbol(
        exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        sema: SemaModule
    ) -> SymbolID? {
        if let bound = sema.bindings.identifierSymbols[exprID] {
            return bound
        }

        var candidates: [SymbolID] = []
        if let receiverExpr,
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           let receiverSymbol = nominalSymbol(for: receiverType, types: sema.types)
        {
            var ownerQueue: [SymbolID] = [receiverSymbol]
            var visitedOwners: Set<SymbolID> = []
            while let owner = ownerQueue.first {
                ownerQueue.removeFirst()
                guard visitedOwners.insert(owner).inserted,
                      let ownerSymbol = sema.symbols.symbol(owner)
                else {
                    continue
                }
                let fqName = ownerSymbol.fqName + [memberName]
                let ownerCandidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID)
                    else {
                        return false
                    }
                    return signature.receiverType != nil
                }
                candidates.append(contentsOf: ownerCandidates)
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
            }

            if candidates.isEmpty {
                let extensionCandidates = sema.symbols.lookupAll(fqName: [memberName]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return true
                }
                candidates.append(contentsOf: extensionCandidates)
            }
        } else {
            candidates = sema.symbols.lookupAll(fqName: [memberName]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }

        if candidates.isEmpty {
            candidates = sema.symbols.lookupByShortName(memberName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }

        return candidates.sorted(by: { lhs, rhs in
            lhs.rawValue < rhs.rawValue
        }).first
    }

    private func nominalSymbol(for typeID: TypeID, types: TypeSystem) -> SymbolID? {
        guard case let .classType(classType) = types.kind(of: typeID) else {
            return nil
        }
        return classType.classSymbol
    }

    private func computeCaptureSymbolsForLambda(
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        lambdaBodyExprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID] {
        if let boundCaptures = sema.bindings.captureSymbolsByExpr[lambdaExprID] {
            var captures = uniqueSymbolsPreservingOrder(boundCaptures).filter { symbol in
                canCaptureSymbolForLambda(
                    symbol,
                    lambdaExprID: lambdaExprID,
                    lambdaParamCount: lambdaParamCount,
                    sema: sema
                )
            }
            if let receiverSymbol = driver.ctx.currentImplicitReceiverSymbol,
               containsImplicitReceiverReference(in: lambdaBodyExprID, ast: ast),
               canCaptureSymbolForLambda(
                   receiverSymbol,
                   lambdaExprID: lambdaExprID,
                   lambdaParamCount: lambdaParamCount,
                   sema: sema
               ),
               !captures.contains(receiverSymbol)
            {
                captures.append(receiverSymbol)
            }
            return captures
        }
        return lexicalCaptureSymbolsForLambda(
            lambdaExprID: lambdaExprID,
            lambdaParamCount: lambdaParamCount,
            lambdaBodyExprID: lambdaBodyExprID,
            ast: ast,
            sema: sema
        )
    }

    private func lexicalCaptureSymbolsForLambda(
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        lambdaBodyExprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID] {
        var referenced: [SymbolID] = []
        var seen: Set<SymbolID> = []
        collectBoundIdentifierSymbols(
            in: lambdaBodyExprID,
            ast: ast,
            sema: sema,
            referenced: &referenced,
            seen: &seen
        )
        var captures = referenced.filter { symbol in
            canCaptureSymbolForLambda(
                symbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: lambdaParamCount,
                sema: sema
            )
        }
        if let receiverSymbol = driver.ctx.currentImplicitReceiverSymbol,
           containsImplicitReceiverReference(in: lambdaBodyExprID, ast: ast),
           canCaptureSymbolForLambda(
               receiverSymbol,
               lambdaExprID: lambdaExprID,
               lambdaParamCount: lambdaParamCount,
               sema: sema
           ),
           !captures.contains(receiverSymbol)
        {
            captures.append(receiverSymbol)
        }
        return captures
    }

    func captureValueExpr(
        for symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if let localValue = driver.ctx.localValuesBySymbol[symbol] {
            return localValue
        }
        if symbol == driver.ctx.currentImplicitReceiverSymbol,
           let receiverExprID = driver.ctx.currentImplicitReceiverExprID
        {
            return receiverExprID
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol),
              semanticSymbol.kind == .valueParameter
        else {
            return nil
        }

        let symbolType = typeForSymbolReference(symbol, sema: sema)
        let symbolExpr = arena.appendExpr(.symbolRef(symbol), type: symbolType)
        instructions.append(.constValue(result: symbolExpr, value: .symbolRef(symbol)))
        return symbolExpr
    }
}
