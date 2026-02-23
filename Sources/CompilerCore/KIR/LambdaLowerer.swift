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
            guard case .functionType(let functionType) = sema.types.kind(of: typeID) else {
                return nil
            }
            return functionType
        }

        let lambdaSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)

        let lambdaParameterTypes: [TypeID] = params.enumerated().map { index, _ in
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

        let lambdaParameters: [KIRParameter] = params.enumerated().map { index, _ in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        let savedLocalValues = driver.ctx.localValuesBySymbol
        let savedReceiverExprID = driver.ctx.currentImplicitReceiverExprID
        let savedReceiverSymbol = driver.ctx.currentImplicitReceiverSymbol
        let savedLoopStack = driver.ctx.loopControlStack
        let savedNextLabel = driver.ctx.nextLoopLabel
        defer {
            driver.ctx.localValuesBySymbol = savedLocalValues
            driver.ctx.currentImplicitReceiverExprID = savedReceiverExprID
            driver.ctx.currentImplicitReceiverSymbol = savedReceiverSymbol
            driver.ctx.loopControlStack = savedLoopStack
            driver.ctx.nextLoopLabel = savedNextLabel
        }

        driver.ctx.localValuesBySymbol.removeAll(keepingCapacity: true)
        driver.ctx.currentImplicitReceiverExprID = nil
        driver.ctx.currentImplicitReceiverSymbol = nil
        driver.ctx.loopControlStack.removeAll(keepingCapacity: true)
        driver.ctx.nextLoopLabel = 10_000

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
                    params: captureBindings.map { $0.param } + lambdaParameters,
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
            captureArguments: captureBindings.map { $0.valueExpr }
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
                guard case .functionType(let functionType) = sema.types.kind(of: typeID) else {
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
            case .unit, .nothing:
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
           !externalLinkName.isEmpty {
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
        for semanticSymbol in sema.symbols.allSymbols() {
            guard (semanticSymbol.kind == .function || semanticSymbol.kind == .constructor),
                  let signature = sema.symbols.functionSignature(for: semanticSymbol.id),
                  let index = signature.valueParameterSymbols.firstIndex(of: symbol),
                  index < signature.parameterTypes.count else {
                continue
            }
            return signature.parameterTypes[index]
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
           let receiverSymbol = nominalSymbol(for: receiverType, types: sema.types) {
            var ownerQueue: [SymbolID] = [receiverSymbol]
            var visitedOwners: Set<SymbolID> = []
            while let owner = ownerQueue.first {
                ownerQueue.removeFirst()
                guard visitedOwners.insert(owner).inserted,
                      let ownerSymbol = sema.symbols.symbol(owner) else {
                    continue
                }
                let fqName = ownerSymbol.fqName + [memberName]
                let ownerCandidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID) else {
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
                          signature.receiverType != nil else {
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
            candidates = sema.symbols.allSymbols().compactMap { symbol in
                guard symbol.name == memberName,
                      symbol.kind == .function || symbol.kind == .constructor else {
                    return nil
                }
                return symbol.id
            }
        }

        return candidates.sorted(by: { lhs, rhs in
            lhs.rawValue < rhs.rawValue
        }).first
    }

    private func nominalSymbol(for typeID: TypeID, types: TypeSystem) -> SymbolID? {
        guard case .classType(let classType) = types.kind(of: typeID) else {
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
               !captures.contains(receiverSymbol) {
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
           !captures.contains(receiverSymbol) {
            captures.append(receiverSymbol)
        }
        return captures
    }

    private func canCaptureSymbolForLambda(
        _ symbol: SymbolID,
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        sema: SemaModule
    ) -> Bool {
        if (0..<lambdaParamCount).contains(where: { index in
            symbol == syntheticLambdaParamSymbol(lambdaExprID: lambdaExprID, paramIndex: index)
        }) {
            return false
        }
        if driver.ctx.localValuesBySymbol[symbol] != nil {
            return true
        }
        if symbol == driver.ctx.currentImplicitReceiverSymbol,
           driver.ctx.currentImplicitReceiverExprID != nil {
            return true
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return false
        }
        return semanticSymbol.kind == .valueParameter
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
           let receiverExprID = driver.ctx.currentImplicitReceiverExprID {
            return receiverExprID
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol),
              semanticSymbol.kind == .valueParameter else {
            return nil
        }

        let symbolType = typeForSymbolReference(symbol, sema: sema)
        let symbolExpr = arena.appendExpr(.symbolRef(symbol), type: symbolType)
        instructions.append(.constValue(result: symbolExpr, value: .symbolRef(symbol)))
        return symbolExpr
    }

    private func uniqueSymbolsPreservingOrder(_ symbols: [SymbolID]) -> [SymbolID] {
        var seen: Set<SymbolID> = []
        var ordered: [SymbolID] = []
        ordered.reserveCapacity(symbols.count)
        for symbol in symbols where seen.insert(symbol).inserted {
            ordered.append(symbol)
        }
        return ordered
    }

    func collectBoundIdentifierSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        referenced: inout [SymbolID],
        seen: inout Set<SymbolID>
    ) {
        if let symbol = sema.bindings.identifierSymbols[exprID], seen.insert(symbol).inserted {
            referenced.append(symbol)
        }
        guard let expr = ast.arena.expr(exprID) else {
            return
        }

        switch expr {
        case .intLiteral,
             .longLiteral,
             .floatLiteral,
             .doubleLiteral,
             .charLiteral,
             .boolLiteral,
             .stringLiteral,
             .nameRef,
             .breakExpr,
             .continueExpr,
             .objectLiteral,
             .superRef,
             .thisRef:
            return

        case .stringTemplate(let parts, _):
            for part in parts {
                guard case .expression(let nestedExprID) = part else {
                    continue
                }
                collectBoundIdentifierSymbols(
                    in: nestedExprID,
                    ast: ast,
                    sema: sema,
                    referenced: &referenced,
                    seen: &seen
                )
            }

        case .forExpr(_, let iterableExpr, let bodyExpr, _):
            collectBoundIdentifierSymbols(in: iterableExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .whileExpr(let conditionExpr, let bodyExpr, _):
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .localDecl(_, _, _, let initializer, _):
            if let initializer {
                collectBoundIdentifierSymbols(in: initializer, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .localAssign(_, let valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            collectBoundIdentifierSymbols(in: arrayExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: indexExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .call(let calleeExpr, _, let args, _):
            collectBoundIdentifierSymbols(in: calleeExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .memberCall(let receiverExpr, _, _, let args, _),
             .safeMemberCall(let receiverExpr, _, _, let args, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .arrayAccess(let arrayExpr, let indexExpr, _):
            collectBoundIdentifierSymbols(in: arrayExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: indexExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .binary(_, let lhs, let rhs, _):
            collectBoundIdentifierSymbols(in: lhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .whenExpr(let subjectExpr, let branches, let elseExpr, _):
            if let subjectExpr {
                collectBoundIdentifierSymbols(in: subjectExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            for branch in branches {
                if let condition = branch.condition {
                    collectBoundIdentifierSymbols(in: condition, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
                }
                collectBoundIdentifierSymbols(in: branch.body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let elseExpr {
                collectBoundIdentifierSymbols(in: elseExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .returnExpr(let value, _):
            if let value {
                collectBoundIdentifierSymbols(in: value, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            collectBoundIdentifierSymbols(in: condition, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: thenExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            if let elseExpr {
                collectBoundIdentifierSymbols(in: elseExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for catchClause in catchClauses {
                collectBoundIdentifierSymbols(in: catchClause.body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let finallyExpr {
                collectBoundIdentifierSymbols(in: finallyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .unaryExpr(_, let operandExpr, _),
             .isCheck(let operandExpr, _, _, _),
             .asCast(let operandExpr, _, _, _),
             .nullAssert(let operandExpr, _),
             .throwExpr(let operandExpr, _):
            collectBoundIdentifierSymbols(in: operandExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .compoundAssign(_, _, let valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .lambdaLiteral(_, let bodyExpr, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .callableRef(let receiverExpr, _, _):
            if let receiverExpr {
                collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .localFunDecl(_, _, _, let functionBody, _):
            switch functionBody {
            case .block(let exprIDs, _):
                for nestedExpr in exprIDs {
                    collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
                }
            case .expr(let nestedExpr, _):
                collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            case .unit:
                break
            }

        case .blockExpr(let statements, let trailingExpr, _):
            for statement in statements {
                collectBoundIdentifierSymbols(in: statement, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let trailingExpr {
                collectBoundIdentifierSymbols(in: trailingExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .inExpr(let lhsExpr, let rhsExpr, _),
             .notInExpr(let lhsExpr, let rhsExpr, _):
            collectBoundIdentifierSymbols(in: lhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
        }
    }

    func containsImplicitReceiverReference(in exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        switch expr {
        case .thisRef, .superRef:
            return true

        case .intLiteral,
             .longLiteral,
             .floatLiteral,
             .doubleLiteral,
             .charLiteral,
             .boolLiteral,
             .stringLiteral,
             .nameRef,
             .breakExpr,
             .continueExpr,
             .objectLiteral:
            return false

        case .stringTemplate(let parts, _):
            for part in parts {
                guard case .expression(let nestedExprID) = part else {
                    continue
                }
                if containsImplicitReceiverReference(in: nestedExprID, ast: ast) {
                    return true
                }
            }
            return false

        case .forExpr(_, let iterableExpr, let bodyExpr, _):
            return containsImplicitReceiverReference(in: iterableExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .whileExpr(let conditionExpr, let bodyExpr, _):
            return containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)
                || containsImplicitReceiverReference(in: conditionExpr, ast: ast)

        case .localDecl(_, _, _, let initializer, _):
            guard let initializer else {
                return false
            }
            return containsImplicitReceiverReference(in: initializer, ast: ast)

        case .localAssign(_, let valueExpr, _):
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            return containsImplicitReceiverReference(in: arrayExpr, ast: ast)
                || containsImplicitReceiverReference(in: indexExpr, ast: ast)
                || containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case .call(let calleeExpr, _, let args, _):
            if containsImplicitReceiverReference(in: calleeExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case .memberCall(let receiverExpr, _, _, let args, _),
             .safeMemberCall(let receiverExpr, _, _, let args, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case .arrayAccess(let arrayExpr, let indexExpr, _):
            return containsImplicitReceiverReference(in: arrayExpr, ast: ast)
                || containsImplicitReceiverReference(in: indexExpr, ast: ast)

        case .binary(_, let lhsExpr, let rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)

        case .whenExpr(let subjectExpr, let branches, let elseExpr, _):
            if let subjectExpr,
               containsImplicitReceiverReference(in: subjectExpr, ast: ast) {
                return true
            }
            for branch in branches {
                if let condition = branch.condition,
                   containsImplicitReceiverReference(in: condition, ast: ast) {
                    return true
                }
                if containsImplicitReceiverReference(in: branch.body, ast: ast) {
                    return true
                }
            }
            if let elseExpr,
               containsImplicitReceiverReference(in: elseExpr, ast: ast) {
                return true
            }
            return false

        case .returnExpr(let value, _):
            guard let value else {
                return false
            }
            return containsImplicitReceiverReference(in: value, ast: ast)

        case .ifExpr(let conditionExpr, let thenExpr, let elseExpr, _):
            if containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: thenExpr, ast: ast) {
                return true
            }
            if let elseExpr {
                return containsImplicitReceiverReference(in: elseExpr, ast: ast)
            }
            return false

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            if containsImplicitReceiverReference(in: bodyExpr, ast: ast) {
                return true
            }
            for catchClause in catchClauses where containsImplicitReceiverReference(in: catchClause.body, ast: ast) {
                return true
            }
            if let finallyExpr {
                return containsImplicitReceiverReference(in: finallyExpr, ast: ast)
            }
            return false

        case .unaryExpr(_, let operandExpr, _),
             .isCheck(let operandExpr, _, _, _),
             .asCast(let operandExpr, _, _, _),
             .nullAssert(let operandExpr, _),
             .compoundAssign(_, _, let operandExpr, _),
             .throwExpr(let operandExpr, _):
            return containsImplicitReceiverReference(in: operandExpr, ast: ast)

        case .lambdaLiteral(_, let bodyExpr, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .callableRef(let receiverExpr, _, _):
            guard let receiverExpr else {
                return false
            }
            return containsImplicitReceiverReference(in: receiverExpr, ast: ast)

        case .localFunDecl(_, _, _, let functionBody, _):
            switch functionBody {
            case .block(let exprIDs, _):
                return exprIDs.contains { containsImplicitReceiverReference(in: $0, ast: ast) }
            case .expr(let nestedExprID, _):
                return containsImplicitReceiverReference(in: nestedExprID, ast: ast)
            case .unit:
                return false
            }

        case .blockExpr(let statements, let trailingExpr, _):
            if statements.contains(where: { containsImplicitReceiverReference(in: $0, ast: ast) }) {
                return true
            }
            if let trailingExpr {
                return containsImplicitReceiverReference(in: trailingExpr, ast: ast)
            }
            return false

        case .inExpr(let lhsExpr, let rhsExpr, _),
             .notInExpr(let lhsExpr, let rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)
        }
    }
}
