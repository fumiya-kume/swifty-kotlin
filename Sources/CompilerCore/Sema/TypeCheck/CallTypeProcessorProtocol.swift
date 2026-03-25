import Foundation

/// 共通の呼び出し処理プロトコル
protocol CallTypeProcessor {
    /// 指定された呼び出しを処理できるか判定
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool
    
    /// 呼び出しを処理して型を推論
    func processCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID?
}

/// 呼び出し処理の共通機能を提供するベースクラス
class CallTypeProcessorBase {
    unowned let driver: TypeCheckDriver
    
    init(driver: TypeCheckDriver) {
        self.driver = driver
    }
    
    /// シンボルがユーザー定義（非合成）によってシャドウされているか判定
    func isShadowedByNonSyntheticSymbol(
        _ calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> Bool {
        return ctx.cachedScopeLookup(calleeName).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
    }
    
    /// 合成標準ライブラリシンボルか判定
    func isSyntheticStdlibSymbol(
        _ calleeName: InternedString,
        fqComponents: [String],
        ctx: TypeInferenceContext
    ) -> Bool {
        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard !visibleCandidates.isEmpty else { return false }
        
        return visibleCandidates.allSatisfy { symbolID in
            guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
            return symbol.flags.contains(.synthetic) &&
                   symbol.fqName.count >= fqComponents.count &&
                   Array(symbol.fqName.prefix(fqComponents.count)) == fqComponents.map { ctx.interner.intern($0) }
        }
    }
    
    /// ラムダまたは呼び出し可能参照の引数か判定
    func isLambdaOrCallableRefArg(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }
    
    /// SAM変換可能な引数か判定
    func isSamConvertibleArgument(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }
    
    /// ビルダーラムダ引数が有効か判定
    func isValidBuilderLambdaArgument(_ argumentExprID: ExprID, ast: ASTModule) -> Bool {
        guard let argumentExpr = ast.arena.expr(argumentExprID),
              case let .lambdaLiteral(params, _, _, _) = argumentExpr
        else {
            return false
        }
        return params.isEmpty
    }
}
