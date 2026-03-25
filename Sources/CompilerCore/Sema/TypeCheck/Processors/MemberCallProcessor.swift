import Foundation

class MemberCallProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        // MemberCallProcessorはメンバー呼び出しの一般的な処理を担当
        // 特定の名前チェックではなく、メンバー呼び出しのコンテキストで判断
        return true // すべての呼び出しを一度処理対象にする
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
        // MemberCallProcessorはフォールバックとして機能
        // 他のProcessorが処理しなかった一般的な呼び出しを処理
        return nil // 現時点では他のProcessorに委譲
    }
    
    // MARK: - Member Call Inference Utilities
    
    /// 既知の標準ライブラリシンボル（List、Map、Pairなど）の安全なルックアップ
    /// シンボルが見つからない場合はnilを返す。呼び出し元はエラーに強い設計原則に従い、
    /// nilの場合は`sema.types.anyType`にフォールバックする必要がある（シンボル不足でクラッシュしない）
    private func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        symbols.lookupByShortName(interner.intern(name)).first
    }
    
    /// 組み込みFlowメンバー呼び出しを試行
    private func tryBuiltinFlowMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let memberName = ctx.interner.resolve(calleeName)
        let flowMembers: Set<String> = ["map", "filter", "take", "collect"]
        guard flowMembers.contains(memberName) else {
            return nil
        }
        
        switch memberName {
        case "map":
            return processFlowMapCall(
                id: id,
                receiverElementType: receiverElementType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                sema: sema,
                ctx: ctx,
                locals: &locals
            )
            
        case "filter":
            return processFlowFilterCall(
                id: id,
                receiverElementType: receiverElementType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                sema: sema,
                ctx: ctx,
                locals: &locals
            )
            
        case "take":
            return processFlowTakeCall(
                id: id,
                receiverElementType: receiverElementType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                sema: sema,
                ctx: ctx,
                locals: &locals
            )
            
        case "collect":
            return processFlowCollectCall(
                id: id,
                receiverElementType: receiverElementType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                sema: sema,
                ctx: ctx,
                locals: &locals
            )
            
        default:
            return nil
        }
    }
    
    // MARK: - Flow Member Call Implementations
    
    private func processFlowMapCall(
        id: ExprID,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        // Flow<T>.map(transform) の実装
        guard args.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        // トランスフォーム関数の期待される型: (T) -> R
        let transformExpectedType = sema.types.make(.functionType(FunctionType(
            params: [receiverElementType],
            returnType: sema.types.anyType, // 推論のためにAnyを使用
            isSuspend: false,
            nullability: .nonNull
        )))
        
        let transformType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: transformExpectedType
        )
        
        let resultElementType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: transformType) {
            fnType.returnType
        } else {
            sema.types.anyType
        }
        
        // Flow<R> 型を構築
        let resultFlowType = driver.helpers.makeFlowType(
            elementType: resultElementType,
            sema: sema,
            interner: ctx.interner
        ) ?? sema.types.anyType
        
        sema.bindings.bindExprType(id, type: resultFlowType)
        return resultFlowType
    }
    
    private func processFlowFilterCall(
        id: ExprID,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        // Flow<T>.filter(predicate) の実装
        guard args.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        // 述語関数の期待される型: (T) -> Boolean
        let predicateExpectedType = sema.types.make(.functionType(FunctionType(
            params: [receiverElementType],
            returnType: sema.types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: predicateExpectedType
        )
        
        // フィルタ後も同じ要素型を持つFlow<T>
        let resultFlowType = driver.helpers.makeFlowType(
            elementType: receiverElementType,
            sema: sema,
            interner: ctx.interner
        ) ?? sema.types.anyType
        
        sema.bindings.bindExprType(id, type: resultFlowType)
        return resultFlowType
    }
    
    private func processFlowTakeCall(
        id: ExprID,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        // Flow<T>.take(count) の実装
        guard args.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: sema.types.intType
        )
        
        // take後も同じ要素型を持つFlow<T>
        let resultFlowType = driver.helpers.makeFlowType(
            elementType: receiverElementType,
            sema: sema,
            interner: ctx.interner
        ) ?? sema.types.anyType
        
        sema.bindings.bindExprType(id, type: resultFlowType)
        return resultFlowType
    }
    
    private func processFlowCollectCall(
        id: ExprID,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        // Flow<T>.collect(collector) の実装
        guard args.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        // コレクターの型を推論
        let collectorType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: nil
        )
        
        // コレクターの戻り型を使用
        let resultType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: collectorType) {
            fnType.returnType
        } else {
            sema.types.anyType
        }
        
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
