import Foundation

class ComparisonProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        // 比較関数は2-3個の引数を取る
        guard args.count == 2 || args.count == 3 else { return false }
        
        let calleeNameStr = ctx.interner.resolve(calleeName)
        
        // compareBy, compareByDescending
        if (calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending") && args.count == 1 {
            return !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx)
        }
        
        return comparisonSpecialCallKind(
            for: calleeName,
            argCount: args.count,
            resolvedParamType: nil, // canHandleでは型推論前なのでnil
            ctx: ctx
        ) != nil
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
        guard let calleeName = calleeName else { return nil }
        
        let calleeNameStr = ctx.interner.resolve(calleeName)
        let sema = ctx.sema
        
        // Comparator factory functions: compareBy, compareByDescending (STDLIB-649)
        if args.count == 1 && (calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending") {
            return processCompareByFunction(
                id: id,
                calleeName: calleeName,
                args: args,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
        }
        
        // その他の比較関数
        if args.count == 2 || args.count == 3 {
            return processComparisonFunction(
                id: id,
                calleeName: calleeName,
                args: args,
                range: range,
                ctx: ctx,
                locals: &locals,
                sema: sema
            )
        }
        
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    private func comparisonSpecialCallKind(
        for calleeName: InternedString,
        argCount: Int,
        resolvedParamType: TypeID?,
        ctx: TypeInferenceContext
    ) -> StdlibSpecialCallKind? {
        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard !visibleCandidates.isEmpty else {
            return nil
        }
        
        let expectedPrefix = [ctx.interner.intern("kotlin"), ctx.interner.intern("comparisons")]
        let onlySyntheticComparisonCandidates = visibleCandidates.allSatisfy { symbolID in
            guard let symbol = ctx.cachedSymbol(symbolID) else {
                return false
            }
            return symbol.flags.contains(.synthetic)
                && symbol.fqName.count >= expectedPrefix.count
                && Array(symbol.fqName.prefix(expectedPrefix.count)) == expectedPrefix
        }
        
        guard onlySyntheticComparisonCandidates else {
            return nil
        }
        
        let resolvedName = ctx.interner.resolve(calleeName)
        
        switch (resolvedName, argCount) {
        case ("maxOf", 2):
            return .maxOf2
        case ("maxOf", 3):
            return .maxOf3
        case ("minOf", 2):
            return .minOf2
        case ("minOf", 3):
            return .minOf3
        default:
            return nil
        }
    }
    
    private func processCompareByFunction(
        id: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> TypeID {
        let calleeNameStr = ctx.interner.resolve(calleeName)
        
        // Comparator<T> の戻り型を解決
        // ラムダセレクターは (T) -> Comparable<*> のシグネチャを持つ
        // Tは明示的な型引数、呼び出しコンテキストから推論、またはデフォルトでAny
        let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
            explicitT
        } else if let expectedType,
                  case let .classType(classType) = sema.types.kind(of: expectedType),
                  let firstArg = classType.args.first {
            switch firstArg {
            case let .invariant(t), let .out(t), let .in(t): t
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        
        let selectorExpectedType = sema.types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: selectorExpectedType
        )
        
        // Comparator<T> 型を構築
        let comparatorFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern("Comparator")]
        let comparatorType: TypeID
        
        if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
            comparatorType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            )))
        } else {
            comparatorType = sema.types.anyType
        }
        
        let specialKind: StdlibSpecialCallKind = if calleeNameStr == "compareBy" {
            .compareBy
        } else {
            .compareByDescending
        }
        
        sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
        sema.bindings.bindExprType(id, type: comparatorType)
        return comparatorType
    }
    
    private func processComparisonFunction(
        id: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        sema: SemaModule
    ) -> TypeID {
        // 最初の引数を期待される型なしで推論してオーバーロードを決定
        let firstArgType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: nil
        )
        
        // このオーバーロードが対象とする数値型を解決
        let supportedNumericTypes = [sema.types.longType, sema.types.doubleType, sema.types.floatType, sema.types.intType]
        let resolvedParamType = supportedNumericTypes.first(where: { firstArgType == $0 }) ?? sema.types.intType
        
        guard let specialKind = comparisonSpecialCallKind(
            for: calleeName,
            argCount: args.count,
            resolvedParamType: resolvedParamType,
            ctx: ctx
        ) else {
            return nil
        }
        
        let expectedType = resolvedParamType
        
        // 最初の引数のサブタイプ制約を発行
        driver.emitSubtypeConstraint(
            left: firstArgType,
            right: expectedType,
            range: ctx.ast.arena.exprRange(args[0].expr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        
        // 残りの引数を解決された型で推論
        for i in 1..<args.count {
            let argType = driver.inferExpr(
                args[i].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedType
            )
            driver.emitSubtypeConstraint(
                left: argType,
                right: expectedType,
                range: ctx.ast.arena.exprRange(args[i].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        
        let paramTypes = Array(repeating: expectedType, count: args.count)
        let chosen = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == paramTypes
        })
        
        if let chosen, let signature = sema.symbols.functionSignature(for: chosen) {
            var paramMapping: [Int: Int] = [:]
            for i in 0..<args.count {
                paramMapping[i] = i
            }
            
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [],
                    parameterMapping: paramMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
            sema.bindings.bindExprType(id, type: signature.returnType)
            return signature.returnType
        }
        
        sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
        sema.bindings.bindExprType(id, type: expectedType)
        return expectedType
    }
}
