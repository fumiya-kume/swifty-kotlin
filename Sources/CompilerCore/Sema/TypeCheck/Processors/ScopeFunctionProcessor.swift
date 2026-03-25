import Foundation

class ScopeFunctionProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        
        // with(receiver, block) のチェック
        if args.count == 2 && calleeName == knownNames.with {
            return !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx)
        }
        
        // top-level run(block) のチェック
        if isTopLevelRunCandidate(
            calleeName: calleeName,
            args: args,
            knownNames: knownNames,
            ast: ctx.ast,
            ctx: ctx
        ) {
            return true
        }
        
        // runCatching(block) のチェック
        if args.count == 1 && calleeName == knownNames.runCatching {
            return isLambdaOrCallableRefArg(args[0].expr, ast: ctx.ast) &&
                   !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx) &&
                   isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "runCatching"], ctx: ctx)
        }
        
        return false
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
        
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        let sema = ctx.sema
        
        // --- with(receiver, block) (STDLIB-004, STDLIB-061) ---
        if args.count == 2 && calleeName == knownNames.with {
            return processWithFunction(id: id, args: args, ctx: ctx, locals: &locals, expectedType: expectedType, sema: sema, knownNames: knownNames)
        }
        
        // --- top-level run(block) (STDLIB-401) ---
        if isTopLevelRunCandidate(
            calleeName: calleeName,
            args: args,
            knownNames: knownNames,
            ast: ctx.ast,
            ctx: ctx,
            locals: locals
        ) {
            return processTopLevelRunFunction(id: id, args: args, ctx: ctx, locals: &locals, expectedType: expectedType, sema: sema)
        }
        
        // --- runCatching(block) (STDLIB-590) ---
        if args.count == 1 && calleeName == knownNames.runCatching {
            return processRunCatchingFunction(id: id, args: args, ctx: ctx, locals: &locals, sema: sema, knownNames: knownNames)
        }
        
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    private func isTopLevelRunCandidate(
        calleeName: InternedString?,
        args: [CallArgument],
        knownNames: KnownCompilerNames,
        ast: ASTModule,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName,
              args.count == 1,
              calleeName == knownNames.run,
              isLambdaOrCallableRefArg(args[0].expr, ast: ast),
              !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx),
              isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "run"], ctx: ctx)
        else {
            return false
        }
        return true
    }
    
    private func processWithFunction(
        id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> TypeID {
        // 最初の引数はレシーバーオブジェクト
        let withReceiverType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        
        // 2番目の引数はレシーバー付きのラムダ
        var receiverCtx = ctx.with(implicitReceiverType: withReceiverType)
        let nonNullWithReceiverType = sema.types.makeNonNullable(withReceiverType)
        
        if case let .classType(classType) = sema.types.kind(of: nonNullWithReceiverType),
           let receiverSymbol = sema.symbols.symbol(classType.classSymbol),
           knownNames.isStringBuilderSymbol(receiverSymbol) {
            receiverCtx.isBuilderLambdaScope = true
            receiverCtx.builderKind = .buildString
        }
        
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            receiver: withReceiverType,
            params: [],
            returnType: expectedType ?? sema.types.anyType
        )))
        
        let lambdaType = driver.inferExpr(
            args[1].expr, ctx: receiverCtx, locals: &locals,
            expectedType: lambdaExpectedType
        )
        
        let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
            fnType.returnType
        } else {
            sema.bindings.exprTypes[args[1].expr].flatMap { typeID in
                if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                    return fnType.returnType
                }
                return nil
            } ?? sema.types.anyType
        }
        
        sema.bindings.markScopeFunctionExpr(id, kind: .scopeWith)
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }
    
    private func processTopLevelRunFunction(
        id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        let lambdaExpectedType: TypeID? = if let expectedType {
            sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: expectedType
            )))
        } else {
            nil
        }
        
        let lambdaType = driver.inferExpr(
            args[0].expr, ctx: ctx, locals: &locals,
            expectedType: lambdaExpectedType
        )
        
        let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
            fnType.returnType
        } else {
            sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                    return fnType.returnType
                }
                return nil
            } ?? sema.types.anyType
        }
        
        sema.bindings.markScopeFunctionExpr(id, kind: .scopeTopLevelRun)
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }
    
    private func processRunCatchingFunction(
        id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> TypeID {
        let lambdaType = driver.inferExpr(
            args[0].expr, ctx: ctx, locals: &locals, expectedType: nil
        )
        
        let innerType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
            fnType.returnType
        } else {
            sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                    return fnType.returnType
                }
                return nil
            } ?? sema.types.anyType
        }
        
        // Result<T> 型を構築
        let resultType: TypeID = if let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) {
            sema.types.make(.classType(ClassType(
                classSymbol: resultClassSymbol,
                args: [.out(innerType)],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }
        
        // KIRでのクロージャABI展開のためにラムダをマーク
        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        
        // 呼び出しを合成runCatching関数シンボルにバインド
        if let runCatchingSymbol = sema.symbols.lookup(fqName: knownNames.kotlinRunCatchingFQName) {
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: runCatchingSymbol,
                substitutedTypeArguments: [innerType],
                parameterMapping: [0: 0]
            ))
        }
        
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
