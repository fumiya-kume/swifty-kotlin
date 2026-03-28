import Foundation

/// セーフメンバーコールのローワーリングを担当する専門クラス
/// receiver?.method() 形式のセーフコールを処理し、null安全性を保証する
final class SafeMemberCallLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なセーフメンバーコール処理
    
    /// セーフメンバーコール式のローワーリング
    func lowerSafeMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let boundType = sema.bindings.exprTypes[exprID]
        
        // const val メンバープロパティのフォールディング (P5-109)
        // nullableレシーバーの場合はフォールディングしない（nullチェックが必要なため）
        if args.isEmpty,
           let callBinding = sema.bindings.callBindings[exprID],
           let constant = propertyConstantInitializers[callBinding.chosenCallee],
           let symInfo = sema.symbols.symbol(callBinding.chosenCallee),
           symInfo.flags.contains(.constValue) {
            
            let receiverType = sema.bindings.exprTypes[receiverExpr]
            if let receiverType, receiverType == sema.types.makeNonNullable(receiverType) {
                let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
                instructions.append(.constValue(result: id, value: constant))
                return id
            }
        }
        
        // レシーバーのローワーリング
        let loweredReceiverID = coordinator.driver.lowerExpr(
            receiverExpr,
            shared: shared,
            emit: &instructions
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let safeReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullSafeReceiverType = sema.types.makeNonNullable(safeReceiverType)
        let isCoroutineReceiver = !isPrimitiveType(nonNullSafeReceiverType, sema: sema)
        
        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        
        // Boolean型の特殊処理
        if sema.types.isSubtype(nonNullSafeReceiverType, sema.types.booleanType) {
            if let boolResult = handleBooleanSafeCall(
                effectiveCalleeName: effectiveCalleeName,
                args: args,
                loweredReceiverID: loweredReceiverID,
                result: result,
                shared: shared,
                emit: &instructions
            ) {
                return boolResult
            }
        }
        
        // 引数のローワーリング
        let loweredArgIDs = args.map { argument in
            coordinator.driver.lowerExpr(
                argument.expr,
                shared: shared,
                emit: &instructions
            )
        }
        
        // プリミティブ操作の特殊処理
        if let primitiveResult = handlePrimitiveOperations(
            effectiveCalleeName: effectiveCalleeName,
            args: loweredArgIDs,
            loweredReceiverID: loweredReceiverID,
            result: result,
            shared: shared,
            emit: &instructions
        ) {
            return primitiveResult
        }
        
        // 数値変換の特殊処理
        if let conversionResult = handleNumericConversions(
            effectiveCalleeName: effectiveCalleeName,
            args: loweredArgIDs,
            loweredReceiverID: loweredReceiverID,
            result: result,
            boundType: boundType,
            shared: shared,
            emit: &instructions
        ) {
            return conversionResult
        }
        
        // Any型操作の特殊処理
        if let anyResult = handleAnyOperations(
            effectiveCalleeName: effectiveCalleeName,
            args: loweredArgIDs,
            loweredReceiverID: loweredReceiverID,
            result: result,
            boundType: boundType,
            shared: shared,
            emit: &instructions
        ) {
            return anyResult
        }
        
        // 数値強制の特殊処理
        if let coercionResult = handleNumericCoercion(
            effectiveCalleeName: effectiveCalleeName,
            args: loweredArgIDs,
            loweredReceiverID: loweredReceiverID,
            result: result,
            shared: shared,
            emit: &instructions
        ) {
            return coercionResult
        }
        
        // 一般的なセーフメンバーコール
        return handleGeneralSafeMemberCall(
            exprID: exprID,
            loweredReceiverID: loweredReceiverID,
            effectiveCalleeName: effectiveCalleeName,
            loweredArgIDs: loweredArgIDs,
            result: result,
            shared: shared,
            emit: &instructions
        )
    }
    
    // MARK: - 特殊なセーフコール処理
    
    /// Boolean型のセーフコールを処理
    private func handleBooleanSafeCall(
        effectiveCalleeName: InternedString,
        args: [CallArgument],
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        
        let calleeStr = interner.resolve(effectiveCalleeName)
        let boolCallee: InternedString? = switch calleeStr {
        case "not" where args.isEmpty:
            interner.intern("kk_op_not")
        case "and" where args.count == 1:
            interner.intern("kk_bitwise_and")
        case "or" where args.count == 1:
            interner.intern("kk_bitwise_or")
        case "xor" where args.count == 1:
            interner.intern("kk_bitwise_xor")
        default:
            nil
        }
        
        if let boolCallee {
            let nonNullLabel = coordinator.driver.ctx.makeLoopLabel()
            let endLabel = coordinator.driver.ctx.makeLoopLabel()
            
            instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
            
            let nullableBooleanType = sema.types.makeNullable(sema.types.booleanType)
            let nullValue = arena.appendExpr(.unit, type: nullableBooleanType)
            instructions.append(.constValue(result: nullValue, value: .null))
            
            let nullableResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nullableBooleanType)
            instructions.append(.copy(from: nullValue, to: nullableResult))
            instructions.append(.jump(endLabel))
            
            instructions.append(.label(nonNullLabel))
            let nonNullResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.booleanType)
            
            let argumentIDs: [KIRExprID] = if args.isEmpty {
                []
            } else {
                [
                    coordinator.driver.lowerExpr(
                        args[0].expr,
                        shared: shared,
                        emit: &instructions
                    )
                ]
            }
            
            instructions.append(.call(
                symbol: nil,
                callee: boolCallee,
                arguments: [loweredReceiverID] + argumentIDs,
                result: nonNullResult,
                canThrow: false,
                thrownResult: nil
            ))
            
            instructions.append(.copy(from: nonNullResult, to: nullableResult))
            instructions.append(.label(endLabel))
            
            return nullableResult
        }
        
        return nil
    }
    
    /// プリミティブ操作のセーフコールを処理
    private func handlePrimitiveOperations(
        effectiveCalleeName: InternedString,
        args: [KIRExprID],
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        
        // Int.inv() などの単項演算子
        if interner.resolve(effectiveCalleeName) == "inv", args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            
            let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            
            if nonNullReceiverType == intType || nonNullReceiverType == longType || 
               nonNullReceiverType == uintType || nonNullReceiverType == ulongType {
                
                return emitSafeCallWithNullCheck(
                    loweredReceiverID: loweredReceiverID,
                    runtimeCallee: interner.intern("kk_op_inv"),
                    arguments: [],
                    result: result,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        // ビット操作関数
        if args.isEmpty {
            let calleeStr = interner.resolve(effectiveCalleeName)
            if isBitOperationFunction(calleeStr) {
                return handleBitOperationSafeCall(
                    calleeStr: calleeStr,
                    loweredReceiverID: loweredReceiverID,
                    result: result,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        // 回転演算
        if args.count == 1 {
            let calleeStr = interner.resolve(effectiveCalleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                return handleRotateOperationSafeCall(
                    calleeStr: calleeStr,
                    loweredReceiverID: loweredReceiverID,
                    argumentID: args[0],
                    result: result,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        // 算術/ビット単項演算子
        if args.count == 1 {
            return handleArithmeticOperationSafeCall(
                effectiveCalleeName: effectiveCalleeName,
                loweredReceiverID: loweredReceiverID,
                argumentID: args[0],
                result: result,
                shared: shared,
                emit: &instructions
            )
        }
        
        return nil
    }
    
    /// 数値変換のセーフコールを処理
    private func handleNumericConversions(
        effectiveCalleeName: InternedString,
        args: [KIRExprID],
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        boundType: TypeID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        
        // toString() の特殊処理
        if interner.resolve(effectiveCalleeName) == "toString", args.count <= 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            
            let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                if args.isEmpty {
                    let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                    instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                    
                    return emitSafeCallWithNullCheck(
                        loweredReceiverID: loweredReceiverID,
                        runtimeCallee: interner.intern("kk_any_to_string"),
                        arguments: [tagID],
                        result: result,
                        shared: shared,
                        emit: &instructions
                    )
                } else {
                    return emitSafeCallWithNullCheck(
                        loweredReceiverID: loweredReceiverID,
                        runtimeCallee: interner.intern("kk_int_toString_radix"),
                        arguments: args,
                        result: result,
                        shared: shared,
                        emit: &instructions
                    )
                }
            }
        }
        
        // 一般的な数値変換
        if args.isEmpty {
            let calleeStr = interner.resolve(effectiveCalleeName)
            if isNumericConversionFunction(calleeStr) {
                return handleGeneralNumericConversionSafeCall(
                    calleeStr: calleeStr,
                    loweredReceiverID: loweredReceiverID,
                    result: result,
                    boundType: boundType,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        return nil
    }
    
    /// Any型操作のセーフコールを処理
    private func handleAnyOperations(
        effectiveCalleeName: InternedString,
        args: [KIRExprID],
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        boundType: TypeID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        
        let calleeStr = interner.resolve(effectiveCalleeName)
        
        // Any.toString()
        if args.isEmpty, calleeStr == "toString" {
            let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
            if allowsAnyFallback(receiverType, sema: sema) {
                let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
                let intType = sema.types.make(.primitive(.int, .nonNull))
                
                let callLabel = coordinator.driver.ctx.makeLoopLabel()
                let endLabel = coordinator.driver.ctx.makeLoopLabel()
                let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                
                instructions.append(.label(callLabel))
                let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
                instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
                
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_any_to_string"),
                    arguments: [loweredReceiverID, tagID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.label(endLabel))
                
                return result
            }
        }
        
        // Any.hashCode()
        if args.isEmpty, calleeStr == "hashCode" {
            let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
            if allowsAnyFallback(receiverType, sema: sema) {
                let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
                let intType = sema.types.make(.primitive(.int, .nonNull))
                
                let callLabel = coordinator.driver.ctx.makeLoopLabel()
                let endLabel = coordinator.driver.ctx.makeLoopLabel()
                let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                
                instructions.append(.label(callLabel))
                let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
                instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
                
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_any_hashCode"),
                    arguments: [loweredReceiverID, tagID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.label(endLabel))
                
                return result
            }
        }
        
        // Any.equals()
        if args.count == 1, calleeStr == "equals" {
            let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
            if allowsAnyFallback(receiverType, sema: sema) {
                let receiverTag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
                let argType = arena.exprType(args[0]) ?? sema.types.anyType
                let argTag = CallLoweringHelpers.anyFallbackTag(for: argType, sema: sema)
                let intType = sema.types.make(.primitive(.int, .nonNull))

                let callLabel = coordinator.driver.ctx.makeLoopLabel()
                let endLabel = coordinator.driver.ctx.makeLoopLabel()
                let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                
                instructions.append(.label(callLabel))
                let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
                instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
                
                let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
                instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
                
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_any_equals"),
                    arguments: [loweredReceiverID, receiverTagID, args[0], argTagID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.label(endLabel))
                
                return result
            }
        }
        
        return nil
    }
    
    /// 数値強制のセーフコールを処理
    private func handleNumericCoercion(
        effectiveCalleeName: InternedString,
        args: [KIRExprID],
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let calleeStr = interner.resolve(effectiveCalleeName)
        
        // coerceIn の処理
        if calleeStr == "coerceIn" {
            if args.count == 2 {
                let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    return emitSafeCallWithNullCheck(
                        loweredReceiverID: loweredReceiverID,
                        runtimeCallee: interner.intern(prefix + "_coerceIn"),
                        arguments: args,
                        result: result,
                        shared: shared,
                        emit: &instructions
                    )
                }
            } else if args.count == 1 {
                let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema),
                   prefix == "kk_int" || prefix == "kk_long" {

                    // rangeベースの強制（単一引数の coerceIn はRange引数を期待する）
                    let callLabel = coordinator.driver.ctx.makeLoopLabel()
                    let endLabel = coordinator.driver.ctx.makeLoopLabel()
                    let nullExpr = shared.arena.appendExpr(.null, type: sema.types.nullableAnyType)

                    instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
                    instructions.append(.constValue(result: nullExpr, value: .null))
                    instructions.append(.copy(from: nullExpr, to: result))
                    instructions.append(.jump(endLabel))

                    instructions.append(.label(callLabel))
                    CallLoweringHelpers.emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiverID,
                        loweredRangeArgID: args[0],
                        result: result,
                        sema: sema,
                        arena: shared.arena,
                        interner: interner,
                        instructions: &instructions.instructions
                    )
                    instructions.append(.label(endLabel))

                    return result
                }
            }
        }
        
        // coerceAtLeast/coerceAtMost の処理
        if args.count == 1 {
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast" : "_coerceAtMost"
                    return emitSafeCallWithNullCheck(
                        loweredReceiverID: loweredReceiverID,
                        runtimeCallee: interner.intern(prefix + suffix),
                        arguments: args,
                        result: result,
                        shared: shared,
                        emit: &instructions
                    )
                }
            }
        }
        
        return nil
    }
    
    /// 一般的なセーフメンバーコールを処理
    private func handleGeneralSafeMemberCall(
        exprID: ExprID,
        loweredReceiverID: KIRExprID,
        effectiveCalleeName: InternedString,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        let callLabel = coordinator.driver.ctx.makeLoopLabel()
        let endLabel = coordinator.driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
        
        // nullチェックと分岐
        instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
        instructions.append(.constValue(result: nullExpr, value: .null))
        instructions.append(.copy(from: nullExpr, to: result))
        instructions.append(.jump(endLabel))
        
        instructions.append(.label(callLabel))
        
        // 通常のメンバーコールを発行
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        
        if let callBinding, let chosen {
            let normalizedResult = coordinator.driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: Array(repeating: false, count: loweredArgIDs.count),
                ast: shared.ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: shared.propertyConstantInitializers,
                instructions: &instructions.instructions
            )
            
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(loweredReceiverID, at: 0)
            
            // デフォルトマスクの処理
            if normalizedResult.defaultMask != 0,
               sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true {
                
                appendReifiedTypeTokens(
                    chosenCallee: chosen,
                    callBinding: callBinding,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions,
                    arguments: &finalArguments
                )
                
                appendDefaultMaskArgument(
                    defaultMask: normalizedResult.defaultMask,
                    sema: sema,
                    arena: arena,
                    instructions: &instructions,
                    arguments: &finalArguments
                )
                
                let stubName = interner.intern(interner.resolve(effectiveCalleeName) + "$default")
                let stubSym = coordinator.driver.callSupportLowerer.defaultStubSymbol(for: chosen)
                
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                               !externalLinkName.isEmpty {
                    interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(chosen) {
                    symbol.name
                } else {
                    effectiveCalleeName
                }
                
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        } else {
            // 動的コール（フォールバック）
            instructions.append(.call(
                symbol: nil,
                callee: effectiveCalleeName,
                arguments: [loweredReceiverID] + loweredArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        instructions.append(.label(endLabel))
        return result
    }
    
    // MARK: - ヘルパー関数
    
    /// nullチェック付きでセーフコールを生成
    private func emitSafeCallWithNullCheck(
        loweredReceiverID: KIRExprID,
        runtimeCallee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        
        let callLabel = coordinator.driver.ctx.makeLoopLabel()
        let endLabel = coordinator.driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        
        instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
        instructions.append(.constValue(result: nullExpr, value: .null))
        instructions.append(.copy(from: nullExpr, to: result))
        instructions.append(.jump(endLabel))
        
        instructions.append(.label(callLabel))
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [loweredReceiverID] + arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.label(endLabel))
        
        return result
    }
    
    /// プリミティブ型か判定
    private func isPrimitiveType(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .primitive = sema.types.kind(of: type) {
            return true
        }
        return false
    }
    
    /// ビット操作関数か判定
    private func isBitOperationFunction(_ calleeStr: String) -> Bool {
        return ["countOneBits", "countLeadingZeroBits", "countTrailingZeroBits",
                "highestOneBit", "lowestOneBit", "takeHighestOneBit", "takeLowestOneBit"].contains(calleeStr)
    }
    
    /// 数値変換関数か判定
    private func isNumericConversionFunction(_ calleeStr: String) -> Bool {
        return ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble",
                "toByte", "toShort", "toUByte", "toUShort", "toChar"].contains(calleeStr)
    }
    
    /// Anyフォールバックが許可される型か判定
    private func allowsAnyFallback(_ type: TypeID, sema: SemaModule) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        return switch sema.types.kind(of: nonNullType) {
        case .primitive(.string, _):
            false
        case .primitive:
            true
        default:
            nonNullType == sema.types.anyType
        }
    }
    
    /// Reified型トークンを追加
    private func appendReifiedTypeTokens(
        chosenCallee: SymbolID,
        callBinding: CallBinding?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout KIRLoweringEmitContext,
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        if let signature = sema.symbols.functionSignature(for: chosenCallee),
           !signature.reifiedTypeParameterIndices.isEmpty {
            
            for index in signature.reifiedTypeParameterIndices.sorted() {
                let concreteType = index < (callBinding?.substitutedTypeArguments.count ?? 0)
                    ? callBinding?.substitutedTypeArguments[index] ?? sema.types.anyType
                    : sema.types.anyType
                
                let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
                let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
                arguments.append(tokenExpr)
            }
        }
    }
    
    /// デフォルトマスク引数を追加
    private func appendDefaultMaskArgument(
        defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout KIRLoweringEmitContext,
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let maskExpr = arena.appendExpr(.intLiteral(defaultMask), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(defaultMask)))
        arguments.append(maskExpr)
    }
    
    // MARK: - 特殊処理ヘルパー
    
    /// ビット操作のセーフコールを処理
    private func handleBitOperationSafeCall(
        calleeStr: String,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let intType = sema.types.intType
        
        let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        
        if nonNullReceiverType == intType {
            let runtimeName: String = switch calleeStr {
            case "countOneBits": "kk_int_countOneBits"
            case "countLeadingZeroBits": "kk_int_countLeadingZeroBits"
            case "countTrailingZeroBits": "kk_int_countTrailingZeroBits"
            case "highestOneBit": "kk_int_highestOneBit"
            case "lowestOneBit": "kk_int_lowestOneBit"
            case "takeHighestOneBit": "kk_int_takeHighestOneBit"
            case "takeLowestOneBit": "kk_int_takeLowestOneBit"
            default: ""
            }
            
            if !runtimeName.isEmpty {
                return emitSafeCallWithNullCheck(
                    loweredReceiverID: loweredReceiverID,
                    runtimeCallee: interner.intern(runtimeName),
                    arguments: [],
                    result: result,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        return nil
    }
    
    /// 回転操作のセーフコールを処理
    private func handleRotateOperationSafeCall(
        calleeStr: String,
        loweredReceiverID: KIRExprID,
        argumentID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let intType = sema.types.intType
        let longType = sema.types.longType
        
        let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        
        if nonNullReceiverType == intType {
            let runtimeName = calleeStr == "rotateLeft" ? "kk_int_rotateLeft" : "kk_int_rotateRight"
            return emitSafeCallWithNullCheck(
                loweredReceiverID: loweredReceiverID,
                runtimeCallee: interner.intern(runtimeName),
                arguments: [argumentID],
                result: result,
                shared: shared,
                emit: &instructions
            )
        } else if nonNullReceiverType == longType {
            let runtimeName = calleeStr == "rotateLeft" ? "kk_long_rotateLeft" : "kk_long_rotateRight"
            return emitSafeCallWithNullCheck(
                loweredReceiverID: loweredReceiverID,
                runtimeCallee: interner.intern(runtimeName),
                arguments: [argumentID],
                result: result,
                shared: shared,
                emit: &instructions
            )
        }
        
        return nil
    }
    
    /// 算術操作のセーフコールを処理
    private func handleArithmeticOperationSafeCall(
        effectiveCalleeName: InternedString,
        loweredReceiverID: KIRExprID,
        argumentID: KIRExprID,
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))

        let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let argType = arena.exprType(argumentID) ?? sema.types.anyType
        let nonNullArgType = sema.types.makeNonNullable(argType)
        
        if nonNullReceiverType == intType || nonNullReceiverType == longType || 
           nonNullReceiverType == uintType || nonNullReceiverType == ulongType {
            
            let isIntegerRhs = nonNullArgType == intType || nonNullArgType == longType || 
                              nonNullArgType == uintType || nonNullArgType == ulongType
            
            let primitiveCallee: InternedString? = switch interner.resolve(effectiveCalleeName) {
            case "plus":
                interner.intern("kk_op_add")
            case "minus":
                interner.intern("kk_op_sub")
            case "times":
                interner.intern("kk_op_mul")
            case "div":
                interner.intern("kk_op_div")
            case "rem", "mod":
                interner.intern("kk_op_mod")
            case "and":
                isIntegerRhs ? interner.intern("kk_bitwise_and") : nil
            case "or":
                isIntegerRhs ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                isIntegerRhs ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                nonNullArgType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                nonNullArgType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                nonNullArgType == intType ? interner.intern("kk_op_ushr") : nil
            default:
                nil
            }
            
            if let primitiveCallee {
                return emitSafeCallWithNullCheck(
                    loweredReceiverID: loweredReceiverID,
                    runtimeCallee: primitiveCallee,
                    arguments: [argumentID],
                    result: result,
                    shared: shared,
                    emit: &instructions
                )
            }
        }
        
        return nil
    }
    
    /// 一般的な数値変換のセーフコールを処理
    private func handleGeneralNumericConversionSafeCall(
        calleeStr: String,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        boundType: TypeID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let ubyteType = sema.types.ubyteType
        let ushortType = sema.types.ushortType
        let charType = sema.types.charType
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        
        let receiverType = arena.exprType(loweredReceiverID) ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let resultType = boundType ?? sema.types.anyType
        let nonNullResultType = sema.types.makeNonNullable(resultType)
        
        let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
        case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
        case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
        case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
        case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
        case ("toInt", doubleType, intType): interner.intern("kk_double_to_int")
        case ("toInt", floatType, intType): interner.intern("kk_float_to_int")
        case ("toInt", longType, intType): interner.intern("kk_long_to_int")
        case ("toInt", charType, intType): interner.intern("kk_char_to_int")
        case ("toInt", intType, intType): nil // identity
        case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
        case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
        case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
        case ("toUInt", charType, uintType): interner.intern("kk_char_to_uint")
        case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil // identity
        case ("toLong", intType, longType): interner.intern("kk_int_to_long")
        case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
        case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
        case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
        case ("toLong", doubleType, longType): interner.intern("kk_double_to_long")
        case ("toLong", floatType, longType): interner.intern("kk_float_to_long")
        case ("toLong", charType, longType): interner.intern("kk_char_to_long")
        case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
        case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
        case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
        case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
        case ("toULong", charType, ulongType): interner.intern("kk_char_to_ulong")
        case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
        case ("toULong", ulongType, ulongType): nil // identity
        case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
        case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
        case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
        case ("toFloat", floatType, floatType): nil // identity
        case ("toDouble", intType, doubleType): interner.intern("kk_int_to_double_bits")
        case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
        case ("toDouble", floatType, doubleType): interner.intern("kk_float_to_double_bits")
        case ("toDouble", doubleType, doubleType): nil // identity
        case ("toByte", intType, intType): interner.intern("kk_int_to_byte")
        case ("toByte", longType, intType): interner.intern("kk_long_to_byte")
        case ("toShort", intType, intType): interner.intern("kk_int_to_short")
        case ("toShort", longType, intType): interner.intern("kk_long_to_short")
        case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
        case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
        case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
        case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
        case ("toUByte", ubyteType, ubyteType): nil // identity
        case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
        case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
        case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
        case ("toUShort", ushortType, ushortType): nil // identity
        case ("toChar", intType, charType): interner.intern("kk_int_to_char")
        case ("toChar", longType, charType): interner.intern("kk_long_to_char")
        case ("toChar", uintType, charType): interner.intern("kk_uint_to_char")
        case ("toChar", ulongType, charType): interner.intern("kk_ulong_to_char")
        case ("toChar", ubyteType, charType): interner.intern("kk_ubyte_to_char")
        case ("toChar", ushortType, charType): interner.intern("kk_ushort_to_char")
        case ("toChar", charType, charType): nil // identity
        default: nil
        }
        
        if let callee = conversionCallee {
            return emitSafeCallWithNullCheck(
                loweredReceiverID: loweredReceiverID,
                runtimeCallee: callee,
                arguments: [],
                result: result,
                shared: shared,
                emit: &instructions
            )
        }
        
        return nil
    }
}
