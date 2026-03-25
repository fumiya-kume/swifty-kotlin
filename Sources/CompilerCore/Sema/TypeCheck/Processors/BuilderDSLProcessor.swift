import Foundation

class BuilderDSLProcessor: CallTypeProcessorBase, CallTypeProcessor {
    private enum BuilderDSLArgumentShape {
        case unary([TypeID])
        case keyed([(key: TypeID, value: TypeID)])
    }
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        if locals[calleeName] != nil {
            return false
        }
        
        // ユーザー定義（非合成）シンボルがない場合のみBuilder DSL処理を使用
        if ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }) {
            return false
        }
        
        return builderDSLKind(for: calleeName, interner: ctx.interner) != nil
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
              let builderKind = builderDSLKind(for: calleeName, interner: ctx.interner) else {
            return nil
        }
        
        let ast = ctx.ast
        let sema = ctx.sema
        
        let lambdaArgumentIndex: Int? = switch builderKind {
        case .buildString, .buildSet, .buildMap:
            args.count == 1 ? 0 : nil
        case .buildList:
            switch args.count {
            case 1: 0
            case 2: 1
            default: nil
            }
        }
        
        guard let lambdaArgumentIndex else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        if builderKind == .buildList, args.count == 2 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        }
        
        let argumentExprID = args[lambdaArgumentIndex].expr
        guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        let receiverType = builderDSLReceiverType(
            kind: builderKind,
            lambdaExprID: argumentExprID,
            expectedType: expectedType,
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: ctx.interner
        )
        
        let returnType: TypeID = switch builderKind {
        case .buildString:
            sema.types.stringType
        case .buildList:
            builderDSLBuildListReturnType(receiverType: receiverType, sema: sema, interner: ctx.interner)
        case .buildSet:
            builderDSLBuildSetReturnType(receiverType: receiverType, sema: sema, interner: ctx.interner)
        case .buildMap:
            builderDSLBuildMapReturnType(receiverType: receiverType, sema: sema, interner: ctx.interner)
        }
        
        // ビルダーレシーバーを暗黙の`this`としてラムダ引数を推論
        var builderCtx = ctx.with(implicitReceiverType: receiverType)
        builderCtx.isBuilderLambdaScope = true
        builderCtx.builderKind = builderKind
        _ = driver.inferExpr(argumentExprID, ctx: builderCtx, locals: &locals)
        
        sema.bindings.markBuilderDSLExpr(id, kind: builderKind)
        sema.bindings.markCollectionExpr(id)
        sema.bindings.bindExprType(id, type: returnType)
        
        return returnType
    }
    
    // MARK: - Private Helper Methods
    
    private func builderDSLKind(for name: InternedString, interner: StringInterner) -> BuilderDSLKind? {
        let knownNames = KnownCompilerNames(interner: interner)
        switch name {
        case knownNames.buildString:
            return .buildString
        case knownNames.buildList:
            return .buildList
        case knownNames.buildSet:
            return .buildSet
        case knownNames.buildMap:
            return .buildMap
        default:
            return nil
        }
    }
    
    private func builderDSLReceiverType(
        kind: BuilderDSLKind,
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        // 実装は元のCallTypeChecker+BuilderDSL.swiftから移動
        switch kind {
        case .buildString:
            let knownNames = KnownCompilerNames(interner: interner)
            if let stringBuilderSymbol = sema.symbols.lookup(fqName: knownNames.kotlinStringBuilderFQName) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: stringBuilderSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case .buildList:
            return expectedType ?? sema.types.anyType
        case .buildSet:
            return expectedType ?? sema.types.anyType
        case .buildMap:
            return expectedType ?? sema.types.anyType
        }
    }
    
    private func builderDSLBuildListReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        if let listSymbol = sema.symbols.lookup(fqName: knownNames.kotlinListFQName) {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverType)],
                nullability: .nonNull
            )))
        }
        return sema.types.anyType
    }
    
    private func builderDSLBuildSetReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        if let setSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSetFQName) {
            return sema.types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.invariant(receiverType)],
                nullability: .nonNull
            )))
        }
        return sema.types.anyType
    }
    
    private func builderDSLBuildMapReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        if let mapSymbol = sema.symbols.lookup(fqName: knownNames.kotlinMapFQName) {
            return sema.types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(receiverType)],
                nullability: .nonNull
            )))
        }
        return sema.types.anyType
    }
}
