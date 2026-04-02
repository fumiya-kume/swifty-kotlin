import Foundation

/// インデックスアクセスのローワーリングを担当する専門クラス
/// 配列、文字列のインデックスアクセス、代入、複合代入を処理する
final class IndexedAccessLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なインデックスアクセス処理
    
    /// インデックスアクセス式のローワーリング (array[index], string[index])
    func lowerIndexedAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]

        // 結果の仮割り当て（各ヘルパーが独自の最終結果を生成して返す）
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

        // レシーバーのローワーリング
        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        // コールバインディングの回復
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: interner.intern("get"),
            argumentExprs: indices,
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        
        // 配列型か判定
        let receiverLooksLikeArray = isArrayType(nonNullReceiverType, sema: sema, interner: interner)
        
        // 文字列の単一インデックスアクセス
        if indices.count == 1,
           sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || 
           !receiverLooksLikeArray && boundType == sema.types.charType {
            
            return handleStringIndexedAccess(
                receiverID: receiverID,
                indexExpr: indices[0],
                result: result,
                context: &context
            )
        }
        
        // メンバーコールとしてのget()処理
        if let chosenGet = callBinding?.chosenCallee,
           chosenGet != .invalid,
           let signature = sema.symbols.functionSignature(for: chosenGet),
           signature.receiverType != nil {
            
            return handleMemberGetCall(
                exprID: exprID,
                receiverID: receiverID,
                indices: indices,
                callBinding: callBinding,
                chosenGet: chosenGet,
                result: result,
                context: &context
            )
        }
        
        // ビルドイン配列アクセス
        return handleBuiltinArrayAccess(
            receiverID: receiverID,
            indices: indices,
            result: result,
            context: &context
        )
    }
    
    /// インデックス代入式のローワーリング (array[index] = value)
    func lowerIndexedAssign(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        // レシーバーと値のローワーリング
        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)
        
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        
        let indexID = context.lowerSubExpr(indices[0], driver: coordinator.driver)
        
        let valueID = context.lowerSubExpr(valueExpr, driver: coordinator.driver)
        
        // メンバーコールとしてのset()処理
        if let callBinding = sema.bindings.callBindings[exprID] {
            return handleMemberSetCall(
                exprID: exprID,
                receiverID: receiverID,
                indices: indices,
                indexID: indexID,
                valueID: valueID,
                callBinding: callBinding,
                context: &context
            )
        }
        
        // ビルドイン配列代入
        return handleBuiltinArrayAssign(
            receiverID: receiverID,
            indexID: indexID,
            valueID: valueID,
            context: &context
        )
    }
    
    /// インデックス複合代入式のローワーリング (array[index] += value)
    func lowerIndexedCompoundAssign(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        compoundOp: BinaryOp,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        // 概念的脱糖: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // 適切な kk_op_* を複合演算子に使用
        //   3) kk_array_set(a, i, t')
        
        // レシーバー、インデックス、値のローワーリング
        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)
        
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
        
        let indexID = context.lowerSubExpr(indices[0], driver: coordinator.driver)
        
        let valueID = context.lowerSubExpr(valueExpr, driver: coordinator.driver)
        
        // ステップ1: 現在の値を取得
        let getResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: getResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        // ステップ2: 複合演算を実行
        let compoundResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        
        // 適切な演算子を選択
        let runtimeCallee: InternedString = switch compoundOp {
        case .add: interner.intern("kk_op_add")
        case .subtract: interner.intern("kk_op_sub")
        case .multiply: interner.intern("kk_op_mul")
        case .divide: interner.intern("kk_op_div")
        case .modulo: interner.intern("kk_op_mod")
        default:
            // サポートされていない演算子の場合はフォールバック
            interner.intern("kk_op_add")
        }
        
        context.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [getResult, valueID],
            result: compoundResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        // ステップ3: 結果を配列に設定
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, compoundResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        
        // Unitを返す
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        context.append(.constValue(result: unit, value: .unit))
        return unit
    }
    
    // MARK: - 特殊なアクセス処理
    
    /// 文字列のインデックスアクセスを処理
    private func handleStringIndexedAccess(
        receiverID: KIRExprID,
        indexExpr: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        let indexID = context.lowerSubExpr(indexExpr, driver: coordinator.driver)
        
        let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        context.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
        
        let finalResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.charType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_get"),
            arguments: [receiverID, indexID, thrownExpr],
            result: finalResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        return finalResult
    }
    
    /// メンバーコールとしてのget()を処理
    private func handleMemberGetCall(
        exprID: ExprID,
        receiverID: KIRExprID,
        indices: [ExprID],
        callBinding: CallBinding?,
        chosenGet: SymbolID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        let loweredIndices = indices.map { indexExpr in
            context.lowerSubExpr(indexExpr, driver: coordinator.driver)
        }
        
        let finalResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        // メンバーコールインストラクションを生成
        emitMemberCallInstruction(
            normalized: coordinator.driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredIndices,
                originalArgs: indices.map { indexExpr in
                    CallArgument(label: nil, isSpread: false, expr: indexExpr)
                },
                callBinding: callBinding,
                chosenCallee: chosenGet,
                spreadFlags: Array(repeating: false, count: loweredIndices.count),
                ast: context.ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: context.propertyConstantInitializers,
                instructions: &context.instructions
            ),
            callBinding: callBinding,
            chosenCallee: chosenGet,
            calleeName: interner.intern("get"),
            receiver: receiverID,
            result: finalResult,
            isSuperCall: sema.bindings.isSuperCallExpr(exprID),
            qualifiedSuperType: nil,
            context: &context,
            arguments: [receiverID] + loweredIndices
        )
        
        return finalResult
    }
    
    /// ビルドイン配列アクセスを処理
    private func handleBuiltinArrayAccess(
        receiverID: KIRExprID,
        indices: [ExprID],
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.types.anyType
        
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        
        let indexID = context.lowerSubExpr(indices[0], driver: coordinator.driver)
        
        let finalResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: finalResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        return finalResult
    }
    
    /// メンバーコールとしてのset()を処理
    private func handleMemberSetCall(
        exprID: ExprID,
        receiverID: KIRExprID,
        indices: [ExprID],
        indexID: KIRExprID,
        valueID: KIRExprID,
        callBinding: CallBinding,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        let chosenSet = callBinding.chosenCallee
        var loweredIndices: [KIRExprID] = []
        
        for (i, indexExpr) in indices.enumerated() {
            if i == 0 {
                loweredIndices.append(indexID)
            } else {
                let loweredIndex = context.lowerSubExpr(indexExpr, driver: coordinator.driver)
                loweredIndices.append(loweredIndex)
            }
        }
        
        let loweredArgs = loweredIndices + [valueID]
        let callResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
        
        // メンバーコールインストラクションを生成
        emitMemberCallInstruction(
            normalized: coordinator.driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgs,
                originalArgs: [],
                callBinding: callBinding,
                chosenCallee: chosenSet,
                spreadFlags: Array(repeating: false, count: loweredArgs.count),
                ast: context.ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: context.propertyConstantInitializers,
                instructions: &context.instructions
            ),
            callBinding: callBinding,
            chosenCallee: chosenSet,
            calleeName: interner.intern("set"),
            receiver: receiverID,
            result: callResult,
            isSuperCall: sema.bindings.isSuperCallExpr(exprID),
            qualifiedSuperType: nil,
            context: &context,
            arguments: [receiverID] + loweredArgs
        )
        
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        context.append(.constValue(result: unit, value: .unit))
        return unit
    }
    
    /// ビルドイン配列代入を処理
    private func handleBuiltinArrayAssign(
        receiverID: KIRExprID,
        indexID: KIRExprID,
        valueID: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner

        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, valueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        context.append(.constValue(result: unit, value: .unit))
        return unit
    }
    
    // MARK: - ヘルパー関数
    
    /// メンバーコールバインディングを回復
    private func recoverMemberCallBinding(
        exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        argumentExprs: [ExprID],
        sema: SemaModule
    ) -> CallBinding? {
        // インデックスアクセスがメンバーコールに脱糖された場合のバインディングを回復
        // これはインデックスアクセスが get() メソッド呼び出しとして表現される場合に使用される
        
        // 実装は既存のCallLowererのロジックを参考に
        // TODO: 実際の実装は既存コードから移植
        return nil
    }
    
    /// 配列型か判定
    private func isArrayType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        
        let arrayNames = [
            "Array", "IntArray", "LongArray", "DoubleArray",
            "FloatArray", "BooleanArray", "CharArray", "UShortArray",
        ]
        
        return arrayNames.contains(interner.resolve(symbol.name))
    }
    
    /// メンバーコールインストラクションを生成
    private func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID,
        calleeName: InternedString,
        receiver: KIRExprID,
        result: KIRExprID,
        isSuperCall: Bool,
        qualifiedSuperType: TypeID?,
        context: inout CallLoweringContext,
        arguments: [KIRExprID]
    ) {
        let sema = context.sema
        let arena = context.arena
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
}
