import Foundation

extension KIRLoweringDriver {
    /// Lower a top-level function declaration into KIR declarations.
    func lowerTopLevelFunDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        ctx.currentFunctionSymbol = symbol
        let signature = sema.symbols.functionSignature(for: symbol)
        var params: [KIRParameter] = []
        if let signature {
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.currentImplicitReceiverSymbol = receiverSymbol
                ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            }
            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })
        }
        if function.isInline, let signature,
           !signature.reifiedTypeParameterIndices.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
            }
        }
        let returnType = signature?.returnType ?? sema.types.unitType
        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverExpr = ctx.currentImplicitReceiverExprID,
           let receiverSymbol = ctx.currentImplicitReceiverSymbol
        {
            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        }
        lowerFunDeclBody(function, shared: shared, body: &body)
        body.append(.endBlock)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: symbol,
                    name: function.name,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: function.isSuspend,
                    isInline: function.isInline,
                    sourceRange: function.range
                )
            )
        )
        var declIDs: [KIRDeclID] = [kirID]
        if let defaults = ctx.functionDefaultArgumentsBySymbol[symbol],
           let sig = signature
        {
            let stubID = callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: symbol,
                originalName: function.name,
                signature: sig,
                defaultExpressions: defaults,
                shared: shared
            )
            declIDs.append(stubID)
        }
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        ctx.currentFunctionSymbol = nil
        return declIDs
    }

    private func lowerFunDeclBody(
        _ function: FunDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        switch function.body {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID),
                   case let .returnExpr(value, _, _) = expr
                {
                    if let value {
                        let lowered = lowerExpr(
                            value,
                            shared: shared, emit: &body
                        )
                        body.append(.returnValue(lowered))
                    } else {
                        body.append(.returnUnit)
                    }
                    terminatedByReturn = true
                    break
                }
                if let expr = ast.arena.expr(exprID),
                   case .throwExpr = expr
                {
                    _ = lowerExpr(
                        exprID,
                        shared: shared, emit: &body
                    )
                    terminatedByReturn = true
                    break
                }
                lastValue = lowerExpr(
                    exprID,
                    shared: shared, emit: &body
                )
                if let lastValue, controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                    terminatedByReturn = true
                    break
                }
            }
            if !terminatedByReturn {
                if let lastValue {
                    body.append(.returnValue(lastValue))
                } else {
                    body.append(.returnUnit)
                }
            }
        case let .expr(exprID, _):
            let value = lowerExpr(
                exprID,
                shared: shared, emit: &body
            )
            body.append(.returnValue(value))
        case .unit:
            body.append(.returnUnit)
        }
    }
}
