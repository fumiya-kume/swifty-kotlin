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
        ctx.setCurrentFunctionSymbol(symbol)
        let signature = sema.symbols.functionSignature(for: symbol)
        let params = buildFunDeclParams(function, symbol: symbol, signature: signature, shared: shared)
        let returnType = signature?.returnType ?? sema.types.unitType
        var body: KIRLoweringEmitContext = [.beginBlock]
        bindFunctionParameterLocals(params: params, body: &body, arena: arena)
        lowerFunDeclBody(function, shared: shared, body: &body)
        body.append(.endBlock)
        let kirID = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: function.name, params: params,
            returnType: returnType, body: body,
            isSuspend: function.isSuspend, isInline: function.isInline,
            isTailrec: function.isTailrec,
            sourceRange: function.range
        )))
        var declIDs: [KIRDeclID] = [kirID]
        appendDefaultStub(symbol: symbol, function: function, signature: signature, shared: shared, declIDs: &declIDs)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        ctx.setCurrentFunctionSymbol(nil)
        return declIDs
    }

    // MARK: - Parameter building

    private func buildFunDeclParams(
        _ function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature?,
        shared: KIRLoweringSharedContext
    ) -> [KIRParameter] {
        let sema = shared.sema
        let arena = shared.arena
        var params: [KIRParameter] = []
        if let signature {
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
            }
            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })
        }
        if function.isInline, let signature, !signature.reifiedTypeParameterIndices.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
            }
        }
        return params
    }

    // MARK: - Default stub

    private func appendDefaultStub(
        symbol: SymbolID,
        function: FunDecl,
        signature: FunctionSignature?,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        if let defaults = ctx.defaultArguments(for: symbol), let sig = signature {
            let stubID = callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: symbol, originalName: function.name,
                signature: sig, defaultExpressions: defaults, shared: shared
            )
            declIDs.append(stubID)
        }
    }

    // MARK: - Body lowering

    private func lowerFunDeclBody(
        _ function: FunDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        switch function.body {
        case let .block(exprIDs, _):
            lowerFunDeclBlockBody(exprIDs: exprIDs, shared: shared, body: &body)
        case let .expr(exprID, _):
            let value = lowerExpr(exprID, shared: shared, emit: &body)
            body.append(.returnValue(value))
        case .unit:
            body.append(.returnUnit)
        }
    }

    private func lowerFunDeclBlockBody(
        exprIDs: [ExprID],
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        var lastValue: KIRExprID?
        var terminatedByReturn = false
        for exprID in exprIDs {
            if let expr = ast.arena.expr(exprID), case let .returnExpr(value, _, _) = expr {
                if let value {
                    let lowered = lowerExpr(value, shared: shared, emit: &body)
                    body.append(.returnValue(lowered))
                } else {
                    body.append(.returnUnit)
                }
                terminatedByReturn = true
                break
            }
            if let expr = ast.arena.expr(exprID), case .throwExpr = expr {
                _ = lowerExpr(exprID, shared: shared, emit: &body)
                terminatedByReturn = true
                break
            }
            lastValue = lowerExpr(exprID, shared: shared, emit: &body)
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
    }

    private func bindFunctionParameterLocals(
        params: [KIRParameter],
        body: inout KIRLoweringEmitContext,
        arena: KIRArena
    ) {
        if let receiverBinding = ctx.activeImplicitReceiver()
        {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            ctx.setLocalValue(receiverBinding.exprID, for: receiverBinding.symbol)
        }

        for param in params where param.symbol != ctx.activeImplicitReceiverSymbol() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
        }
    }
}
