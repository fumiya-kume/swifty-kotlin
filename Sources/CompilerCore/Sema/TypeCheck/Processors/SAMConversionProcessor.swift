import Foundation

class SAMConversionProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        // SAM変換は単一の引数を取る呼び出しのみを処理
        guard args.count == 1 else { return false }
        
        // 引数がSAM変換可能かチェック
        guard isSamConvertibleArgument(args[0].expr, ast: ctx.ast) else { return false }
        
        return true
    }
    
    func processCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let calleeName = calleeName,
              args.count == 1,
              isSamConvertibleArgument(args[0].expr, ast: ctx.ast) else {
            return nil
        }
        
        let sema = ctx.sema
        let ast = ctx.ast
        
        var visibleCandidates = ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible
        
        if visibleCandidates.isEmpty {
            visibleCandidates = sema.symbols.lookupAll(fqName: [calleeName]).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }
        
        guard !visibleCandidates.isEmpty else {
            return nil
        }
        
        // SAM変換の候補をフィルタリング
        let samCandidates = visibleCandidates.filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate) else { return false }
            return isSamConvertibleSymbol(symbol, sema: sema)
        }
        
        guard !samCandidates.isEmpty else {
            return nil
        }
        
        // 期待される型に基づいて最適な候補を選択
        let chosenCandidate = selectBestSamCandidate(
            from: samCandidates,
            expectedType: expectedType,
            sema: sema,
            ctx: ctx
        )
        
        guard let candidate = chosenCandidate else {
            return nil
        }
        
        return processSamConversion(
            id: id,
            candidate: candidate,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func isSamConvertibleSymbol(_ symbol: Symbol, sema: SemaModule) -> Bool {
        guard case let .functionType(fnType) = sema.types.kind(of: symbol.type) else {
            return false
        }
        
        // SAM（Single Abstract Method）インターフェースのチェック
        // 1. 関数型でなければならない
        // 2. 1つの抽象メソッドのみを持つ必要がある
        // 3. デフォルトメソッドは許可される
        
        return fnType.params.count == 1 // 簡略化されたチェック
    }
    
    private func selectBestSamCandidate(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        guard let expectedType = expectedType else {
            return candidates.first
        }
        
        // 期待される型に一致する候補を探す
        for candidate in candidates {
            guard let symbol = sema.symbols.symbol(candidate) else { continue }
            if symbol.type == expectedType {
                return candidate
            }
        }
        
        return candidates.first
    }
    
    private func processSamConversion(
        id: ExprID,
        candidate: SymbolID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        
        guard let symbol = sema.symbols.symbol(candidate) else {
            return nil
        }
        
        guard case let .functionType(fnType) = sema.types.kind(of: symbol.type) else {
            return nil
        }
        
        // ラムダ引数を関数型で推論
        let lambdaType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: fnType
        )
        
        // SAM変換のバインディングを設定
        var parameterMapping: [Int: Int] = [:]
        parameterMapping[0] = 0
        
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: candidate,
                substitutedTypeArguments: explicitTypeArgs,
                parameterMapping: parameterMapping
            )
        )
        
        sema.bindings.bindCallableTarget(id, target: .symbol(candidate))
        sema.bindings.bindExprType(id, type: symbol.type)
        
        return symbol.type
    }
}
