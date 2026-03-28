import Foundation

/// メンバーコールのローワーリングを担当する専門クラス
/// 通常のメンバーコール、コンストラクタコール、拡張関数などを処理する
final class MemberCallLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なメンバーコール処理
    
    /// メンバーコール式のローワーリング
    func lowerMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        // const val メンバープロパティのフォールディング (P5-109)
        if args.isEmpty,
           let callBinding = sema.bindings.callBindings[exprID],
           let constant = context.propertyConstantInitializers[callBinding.chosenCallee],
           let symInfo = sema.symbols.symbol(callBinding.chosenCallee),
           symInfo.flags.contains(.constValue) {
            
            let receiverType = sema.bindings.exprTypes[receiverExpr]
            if let receiverType, receiverType == sema.types.makeNonNullable(receiverType) {
                let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
                context.append(.constValue(result: id, value: constant))
                return id
            }
        }
        
        // レシーバーのローワーリング
        let loweredReceiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)
        
        // コルーチンハンドルの特殊処理
        if isCoroutineHandleCall(receiverExpr: receiverExpr, calleeName: calleeName, sema: sema, interner: interner) {
            return handleCoroutineHandleCall(
                exprID: exprID,
                receiverID: loweredReceiverID,
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }

        // チャネル操作の特殊処理
        if isChannelCall(receiverExpr: receiverExpr, calleeName: calleeName, sema: sema, interner: interner) {
            return handleChannelCall(
                exprID: exprID,
                receiverID: loweredReceiverID,
                calleeName: calleeName,
                args: args,
                context: &context
            )
        }
        
        // 一般的なメンバーコールの処理
        return handleGeneralMemberCall(
            exprID: exprID,
            receiverID: loweredReceiverID,
            calleeName: calleeName,
            args: args,
            context: &context
        )
    }
    
    // MARK: - 特殊なメンバーコール処理
    
    /// コルーチンハンドルのコールを処理
    private func handleCoroutineHandleCall(
        exprID: ExprID,
        receiverID: KIRExprID,
        calleeName: InternedString,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        let calleeStr = interner.resolve(calleeName)
        let runtimeName: String? = switch calleeStr {
        case "await": "kk_coro_await"
        case "join": "kk_coro_join"
        case "cancel": "kk_coro_cancel"
        default: nil
        }
        
        if let runtimeName {
            let loweredArgs = args.map { arg in
                context.lowerSubExpr(arg.expr, driver: coordinator.driver)
            }
            
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID] + loweredArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
            return result
        }
        
        // フォールバック: 一般的なメンバーコールとして処理
        return handleGeneralMemberCall(
            exprID: exprID,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            context: &context
        )
    }
    
    /// チャネル操作のコールを処理
    private func handleChannelCall(
        exprID: ExprID,
        receiverID: KIRExprID,
        calleeName: InternedString,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        let calleeStr = interner.resolve(calleeName)
        let runtimeName: String? = switch calleeStr {
        case "send": "kk_channel_send"
        case "receive": "kk_channel_receive"
        case "close": "kk_channel_close"
        default: nil
        }
        
        if let runtimeName {
            let loweredArgs = args.map { arg in
                context.lowerSubExpr(arg.expr, driver: coordinator.driver)
            }
            
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID] + loweredArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))
            return result
        }
        
        // フォールバック: 一般的なメンバーコールとして処理
        return handleGeneralMemberCall(
            exprID: exprID,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            context: &context
        )
    }
    
    /// 一般的なメンバーコールを処理
    private func handleGeneralMemberCall(
        exprID: ExprID,
        receiverID: KIRExprID,
        calleeName: InternedString,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        // 引数のローワーリング
        let loweredArgIDs = args.map { arg in
            context.lowerSubExpr(arg.expr, driver: coordinator.driver)
        }
        
        // コールバインディングの取得
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        
        // コンストラクタコールの特殊処理
        if let chosen,
           let symbol = sema.symbols.symbol(chosen),
           symbol.kind == .constructor {
            return handleConstructorCall(
                exprID: exprID,
                chosen: chosen,
                args: loweredArgIDs,
                context: &context
            )
        }
        
        // 通常のメンバーコール
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        if let callBinding, let chosen {
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
            
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(receiverID, at: 0)
            
            emitMemberCallInstruction(
                normalized: normalizedResult,
                callBinding: callBinding,
                chosenCallee: chosen,
                calleeName: calleeName,
                receiver: receiverID,
                result: result,
                context: &context,
                arguments: finalArguments
            )
        } else {
            // 動的コール（フォールバック）
            context.append(.call(
                symbol: nil,
                callee: calleeName,
                arguments: [receiverID] + loweredArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        return result
    }
    
    /// コンストラクタコールを処理
    private func handleConstructorCall(
        exprID: ExprID,
        chosen: SymbolID,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        // オブジェクトのアロケーション
        let allocType = boundType ?? sema.types.anyType
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        var slotCount: Int64 = 1
        var ownerNominalSymbol: SymbolID?
        
        if let parentClassID = sema.symbols.parentSymbol(for: chosen),
           let layout = sema.symbols.nominalLayout(for: parentClassID) {
            ownerNominalSymbol = parentClassID
            slotCount = Int64(max(layout.instanceSizeWords, 1))
        }
        
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        context.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        
        let classIDValue: Int64 = if let ownerNominalSymbol {
            RuntimeTypeCheckToken.stableNominalTypeID(symbol: ownerNominalSymbol, sema: sema, interner: interner)
        } else {
            0
        }
        
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        context.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        
        let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObj,
            canThrow: false,
            thrownResult: nil
        ))
        
        // タイプ登録とインターフェース実装
        if let ownerNominalSymbol {
            registerTypeMetadata(
                objectSymbol: ownerNominalSymbol,
                allocatedObj: allocatedObj,
                context: &context
            )
        }
        
        // コンストラクタの呼び出し
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        context.append(.call(
            symbol: chosen,
            callee: interner.intern("<init>"),
            arguments: [allocatedObj] + args,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return allocatedObj
    }
    
    // MARK: - ヘルパー関数
    
    /// コルーチンハンドルのコールか判定
    private func isCoroutineHandleCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        return isCoroutineHandleReceiverType(receiverType, sema: sema, interner: interner) &&
               Self.unresolvedCoroutineHandleMemberNames.contains(interner.resolve(calleeName))
    }

    /// チャネルのコールか判定
    private func isChannelCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        return isChannelReceiverType(receiverType, sema: sema, interner: interner) &&
               Self.unresolvedChannelMemberNames.contains(interner.resolve(calleeName))
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
    
    /// タイプメタデータを登録
    private func registerTypeMetadata(
        objectSymbol: SymbolID,
        allocatedObj: KIRExprID,
        context: inout CallLoweringContext
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )
        
        let childExpr = arena.appendExpr(.intLiteral(childTypeID), type: intType)
        context.append(.constValue(result: childExpr, value: .intLiteral(childTypeID)))
        
        // スーパータイプの登録
        for superSymbol in sema.symbols.directSupertypes(for: objectSymbol) {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: superSymbol,
                sema: sema,
                interner: interner
            )
            
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            context.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            
            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            let superKind = sema.symbols.symbol(superSymbol)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            
            context.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [childExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        // インターフェースメソッドの登録
        if let objectLayout = sema.symbols.nominalLayout(for: objectSymbol) {
            for interfaceSymbol in sema.symbols.directSupertypes(for: objectSymbol) {
                guard sema.symbols.symbol(interfaceSymbol)?.kind == .interface,
                      let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else {
                    continue
                }
                
                let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                for (methodSymbol, methodSlotInt) in interfaceLayout.vtableSlots {
                    let methodSlot = Int64(methodSlotInt)
                    let implementationSymbol = findImplementationSymbol(
                        methodSymbol: methodSymbol,
                        ownerSymbol: objectSymbol,
                        interfaceSymbol: interfaceSymbol,
                        sema: sema
                    )
                    
                    let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                    context.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                    
                    let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                    context.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                    
                    let methodFnExpr = arena.appendExpr(.symbolRef(implementationSymbol), type: intType)
                    context.append(.constValue(result: methodFnExpr, value: .symbolRef(implementationSymbol)))
                    
                    let registerMethodResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                    context.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_object_register_itable_method"),
                        arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                        result: registerMethodResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            }
        }
        
        // KClassメタデータの登録
        emitKClassMetadataRegistration(
            objectSymbol: objectSymbol,
            typeID: childTypeID,
            context: &context
        )
    }
    
    /// 実装シンボルを検索（シグネチャ対応）
    private func findImplementationSymbol(
        methodSymbol: SymbolID,
        ownerSymbol: SymbolID,
        interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID {
        guard let methodSym = sema.symbols.symbol(methodSymbol),
              let ownerSym = sema.symbols.symbol(ownerSymbol) else {
            return methodSymbol
        }

        let interfaceSignature = sema.symbols.functionSignature(for: methodSymbol)
        let interfaceParamCount = interfaceSignature?.parameterTypes.count ?? -1

        let overrideFQName = ownerSym.fqName + [methodSym.name]
        for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .function,
                  sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                continue
            }
            // シグネチャが利用可能な場合はパラメータ数でフィルタリング
            if let candidateSignature = sema.symbols.functionSignature(for: candidate) {
                guard candidateSignature.parameterTypes.count == interfaceParamCount else {
                    continue
                }
            }
            return candidate
        }

        return methodSymbol
    }
    
    /// KClassメタデータ登録を生成
    private func emitKClassMetadataRegistration(
        objectSymbol: SymbolID,
        typeID: Int64,
        context: inout CallLoweringContext
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        // REFL-005: KClassメタデータ登録
        let typeIDExpr = arena.appendExpr(.intLiteral(typeID), type: intType)
        context.append(.constValue(result: typeIDExpr, value: .intLiteral(typeID)))
        
        let metadataResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_register_kclass"),
            arguments: [typeIDExpr],
            result: metadataResult,
            canThrow: false,
            thrownResult: nil
        ))
    }
    
    /// メンバーコールインストラクションを生成
    private func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID,
        calleeName: InternedString,
        receiver: KIRExprID,
        result: KIRExprID,
        context: inout CallLoweringContext,
        arguments: [KIRExprID]
    ) {
        let sema = context.sema
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        var finalArguments = arguments
        
        // デフォルトマスクの処理
        if normalized.defaultMask != 0,
           sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true {

            appendReifiedTypeTokens(
                chosenCallee: chosenCallee,
                callBinding: callBinding,
                context: &context,
                arguments: &finalArguments
            )

            appendDefaultMaskArgument(
                defaultMask: normalized.defaultMask,
                context: &context,
                arguments: &finalArguments
            )

            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = coordinator.driver.callSupportLowerer.defaultStubSymbol(for: chosenCallee)
            
            context.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
                                                           !externalLinkName.isEmpty {
                interner.intern(externalLinkName)
            } else if let symbol = sema.symbols.symbol(chosenCallee) {
                symbol.name
            } else {
                calleeName
            }
            
            context.append(.call(
                symbol: chosenCallee,
                callee: loweredCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
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
        defaultMask: Int64,
        context: inout CallLoweringContext,
        arguments: inout [KIRExprID]
    ) {
        let sema = context.sema
        let arena = context.arena
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let maskExpr = arena.appendExpr(.intLiteral(defaultMask), type: intType)
        context.append(.constValue(result: maskExpr, value: .intLiteral(defaultMask)))
        arguments.append(maskExpr)
    }
    
    // MARK: - 定数
    
    static let unresolvedCoroutineHandleMemberNames: Set<String> = ["await", "join", "cancel"]
    static let unresolvedChannelMemberNames: Set<String> = ["send", "receive", "close"]
}

