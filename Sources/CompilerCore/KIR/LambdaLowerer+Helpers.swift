import Foundation

// Helper methods for LambdaLowerer: symbol naming, type resolution,
// capture analysis, and callable-reference target resolution.

extension LambdaLowerer {
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

    // swiftlint:disable:next function_body_length
    func resolveCallableRefTargetSymbol(
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

    func nominalSymbol(for typeID: TypeID, types: TypeSystem) -> SymbolID? {
        guard case let .classType(classType) = types.kind(of: typeID) else {
            return nil
        }
        return classType.classSymbol
    }

    func computeCaptureSymbolsForLambda(
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
