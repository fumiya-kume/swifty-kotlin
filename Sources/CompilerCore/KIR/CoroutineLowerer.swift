import Foundation

/// コルーチン関連のローワーリングを担当する専門クラス
/// コルーチンハンドル、チャネル操作、コルーチンランチャーなどを処理する
final class CoroutineLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なコルーチン操作処理
    
    /// コルーチン操作のローワーリングを試行
    func lowerCoroutineOperation(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        
        // コルーチンハンドル操作
        if isCoroutineHandleCall(receiverExpr: receiverExpr, calleeName: calleeName, sema: sema, interner: interner) {
            return lowerCoroutineHandleCall(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }
        
        // チャネル操作
        if isChannelCall(receiverExpr: receiverExpr, calleeName: calleeName, sema: sema, interner: interner) {
            return lowerChannelCall(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }
        
        return nil
    }
    
    /// コルーチンランチャー操作を処理
    func lowerCoroutineLauncher(
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        let knownNames = KnownCompilerNames(interner: interner)
        
        // runBlocking, launch, async の処理
        if calleeStr == knownNames.runBlocking || 
           calleeStr == knownNames.launch || 
           calleeStr == knownNames.async {
            return lowerCoroutineLauncherCall(
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }
        
        // withContext の処理
        if calleeStr == knownNames.withContext && args.count >= 2 {
            return lowerWithContextCall(
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }
        
        return nil
    }
    
    // MARK: - コルーチンハンドル操作
    
    /// コルーチンハンドルのコールを処理
    private func lowerCoroutineHandleCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[/* exprID from context */] ?? sema.types.anyType
        
        let calleeStr = interner.resolve(calleeName)
        let runtimeName: String? = switch calleeStr {
        case "await": "kk_coro_await"
        case "join": "kk_coro_join"
        case "cancel": "kk_coro_cancel"
        default: nil
        }
        
        if let runtimeName {
            let receiverID = coordinator.driver.lowerExpr(
                receiverExpr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
            
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID] + args,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    // MARK: - チャネル操作
    
    /// チャネルのコールを処理
    private func lowerChannelCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[/* exprID from context */] ?? sema.types.anyType
        
        let calleeStr = interner.resolve(calleeName)
        let runtimeName: String? = switch calleeStr {
        case "send": "kk_channel_send"
        case "receive": "kk_channel_receive"
        case "close": "kk_channel_close"
        default: nil
        }
        
        if let runtimeName {
            let receiverID = coordinator.driver.lowerExpr(
                receiverExpr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
            
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID] + args,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    // MARK: - コルーチンランチャー
    
    /// コルーチンランチャーのコールを処理
    private func lowerCoroutineLauncherCall(
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let calleeStr = interner.resolve(calleeName)
        let boundType = sema.types.anyType // TODO: 実際の結果型を取得
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        
        // コルーチンランチャーのキャプチャ引数を展開
        var finalArgs = args
        if let firstArg = args.first,
           let callableInfo = coordinator.driver.ctx.callableValueInfo(for: firstArg),
           !callableInfo.captureArguments.isEmpty {
            finalArgs.insert(contentsOf: callableInfo.captureArguments, at: 1)
        }
        
        let runtimeName: String = switch calleeStr {
        case knownNames.runBlocking: "kk_run_blocking"
        case knownNames.launch: "kk_launch"
        case knownNames.async: "kk_async"
        default: calleeStr
        }
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeName),
            arguments: finalArgs,
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// withContextのコールを処理
    private func lowerWithContextCall(
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let boundType = sema.types.anyType // TODO: 実際の結果型を取得
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        
        // withContextのキャプチャ引数を展開
        var finalArgs = args
        if args.count >= 2,
           let callableInfo = coordinator.driver.ctx.callableValueInfo(for: args[1]),
           !callableInfo.captureArguments.isEmpty {
            finalArgs.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_with_context"),
            arguments: finalArgs,
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - コルーチンビルダー
    
    /// コルーチンビルダーを処理
    func lowerCoroutineBuilder(
        exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // coroutineビルダーの特殊処理
        if let coroutineResult = lowerCoroutineBuilderCall(
            exprID: exprID,
            receiverExpr: receiverExpr,
            args: args,
            context: &context
        ) {
            return coroutineResult
        }
        
        return nil
    }
    
    /// coroutineビルダーコールを処理
    private func lowerCoroutineBuilderCall(
        exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "coroutine" else {
            return nil
        }
        
        // coroutineビルダーの引数を処理
        guard args.count >= 2 else {
            return nil
        }
        
        let contextArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let blockArgID = coordinator.driver.lowerExpr(
            args[1].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        // coroutineビルダーの実装
        context.append(.call(
            symbol: chosen,
            callee: interner.intern("kk_coroutine_builder"),
            arguments: [contextArgID, blockArgID],
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - サスペンド関数
    
    /// サスペンド関数のコールを処理
    func lowerSuspendFunctionCall(
        exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.isSuspend else {
            return nil
        }
        
        // サスペンド関数の引数をローワーリング
        let loweredArgIDs = args.map { arg in
            coordinator.driver.lowerExpr(
                arg.expr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
        }
        
        let loweredCalleeID = coordinator.driver.lowerExpr(
            calleeExpr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        // サスペンド関数呼び出しの特殊処理
        var finalArguments = [loweredCalleeID] + loweredArgIDs
        
        // キャプチャ引数を展開
        if let callableInfo = coordinator.driver.ctx.callableValueInfo(for: loweredCalleeID),
           !callableInfo.captureArguments.isEmpty {
            finalArguments.insert(contentsOf: callableInfo.captureArguments, at: 1)
        }
        
        // デフォルトマスクの処理
        let normalizedResult = coordinator.driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            ast: context.ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: context.propertyConstantInitializers,
            instructions: &context.instructions
        )
        
        if normalizedResult.defaultMask != 0,
           sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true {
            
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                context: &context,
                arguments: &finalArguments
            )
            
            appendDefaultMaskArgument(
                defaultMask: normalizedResult.defaultMask,
                context: &context,
                arguments: &finalArguments
            )
            
            let stubName = interner.intern(interner.resolve(sema.symbols.symbol(chosen)?.name ?? "unknown") + "$default")
            let stubSym = coordinator.driver.callSupportLowerer.defaultStubSymbol(for: chosen)
            
            context.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
        } else {
            let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                           !externalLinkName.isEmpty {
                interner.intern(externalLinkName)
            } else if let symbol = sema.symbols.symbol(chosen) {
                symbol.name
            } else {
                interner.intern("suspend_call")
            }
            
            context.append(.call(
                symbol: chosen,
                callee: loweredCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
        }
        
        return result
    }
    
    // MARK: - ヘルパー関数
    
    /// コルーチンハンドルのコールか判定
    private func isCoroutineHandleCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let callBinding = sema.bindings.callBindings[/* exprID from context */],
              let receiverType = sema.bindings.exprTypes[callBinding.receiverExpr] else {
            return false
        }
        
        return isCoroutineHandleReceiverType(receiverType, sema: sema, interner: interner) &&
               MemberCallLowerer.unresolvedCoroutineHandleMemberNames.contains(interner.resolve(calleeName))
    }
    
    /// チャネルのコールか判定
    private func isChannelCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let callBinding = sema.bindings.callBindings[/* exprID from context */],
              let receiverType = sema.bindings.exprTypes[callBinding.receiverExpr] else {
            return false
        }
        
        return isChannelReceiverType(receiverType, sema: sema, interner: interner) &&
               MemberCallLowerer.unresolvedChannelMemberNames.contains(interner.resolve(calleeName))
    }
    
    /// コルーチンハンドルのレシーバー型か判定
    private func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }
    
    /// チャネルのレシーバー型か判定
    private func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }
    
    /// Reified型トークンを追加
    private func appendReifiedTypeTokens(
        chosenCallee: SymbolID,
        callBinding: CallBinding?,
        context: inout CallLoweringContext,
        arguments: inout [KIRExprID]
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        if let signature = sema.symbols.functionSignature(for: chosenCallee),
           !signature.reifiedTypeParameterIndices.isEmpty {
            
            for index in signature.reifiedTypeParameterIndices.sorted() {
                let concreteType = index < (callBinding?.substitutedTypeArguments.count ?? 0)
                    ? callBinding?.substitutedTypeArguments[index] ?? sema.types.anyType
                    : sema.types.anyType
                
                let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
                let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
                context.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
                arguments.append(tokenExpr)
            }
        }
    }
    
    /// デフォルトマスク引数を追加
    private func appendDefaultMaskArgument(
        defaultMask: Int,
        context: inout CallLoweringContext,
        arguments: inout [KIRExprID]
    ) {
        let sema = context.sema
        let arena = context.arena
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let maskExpr = arena.appendExpr(.intLiteral(Int64(defaultMask)), type: intType)
        context.append(.constValue(result: maskExpr, value: .intLiteral(Int64(defaultMask))))
        arguments.append(maskExpr)
    }
}
