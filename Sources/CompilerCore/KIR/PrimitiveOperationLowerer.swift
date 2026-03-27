import Foundation

/// プリミティブ操作のローワーリングを担当する専門クラス
/// プリミティブ型の変換、ビット演算、数値強制などを処理する
final class PrimitiveOperationLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なプリミティブ操作処理
    
    /// プリミティブ操作のローワーリングを試行
    func lowerPrimitiveOperation(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        
        // ビット操作関数
        if let bitResult = lowerBitManipulationFunctions(
            calleeStr: calleeStr,
            receiverExpr: receiverExpr,
            args: args,
            context: &context
        ) {
            return bitResult
        }
        
        // 回転演算
        if args.count == 1, (calleeStr == "rotateLeft" || calleeStr == "rotateRight") {
            return lowerRotateOperations(
                calleeStr: calleeStr,
                receiverExpr: receiverExpr,
                argumentID: args[0],
                context: &context
            )
        }
        
        // 算術/ビット単項演算子
        if args.count == 1 {
            return lowerArithmeticOperations(
                calleeName: calleeName,
                receiverExpr: receiverExpr,
                argumentID: args[0],
                context: &context
            )
        }
        
        // 数値変換
        if args.isEmpty, isNumericConversionFunction(calleeStr) {
            return lowerNumericConversions(
                calleeStr: calleeStr,
                receiverExpr: receiverExpr,
                context: &context
            )
        }
        
        return nil
    }
    
    // MARK: - ビット操作関数
    
    /// ビット操作関数を処理
    private func lowerBitManipulationFunctions(
        calleeStr: String,
        receiverExpr: ExprID,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        guard args.isEmpty,
              isBitOperationFunction(calleeStr) else {
            return nil
        }
        
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let intType = sema.types.intType
        let longType = sema.types.longType
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.intType)
        
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
                let receiverID = coordinator.driver.lowerExpr(
                    receiverExpr,
                    shared: context.sharedContext,
                    emit: context.emitContext()
                )
                
                context.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeName),
                    arguments: [receiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        } else if nonNullReceiverType == longType {
            // Long型のビット操作
            return lowerLongBitOperations(
                calleeStr: calleeStr,
                receiverExpr: receiverExpr,
                result: result,
                context: &context
            )
        }
        
        return nil
    }
    
    /// Long型のビット操作を処理
    private func lowerLongBitOperations(
        calleeStr: String,
        receiverExpr: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let longType = sema.types.longType
        
        let runtimeName: String? = switch calleeStr {
        case "highestOneBit": "kk_long_highestOneBit"
        case "lowestOneBit": "kk_long_lowestOneBit"
        case "takeHighestOneBit": "kk_long_takeHighestOneBit"
        case "takeLowestOneBit": "kk_long_takeLowestOneBit"
        default: nil
        }
        
        if let name = runtimeName {
            let receiverID = coordinator.driver.lowerExpr(
                receiverExpr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
            
            context.append(.call(
                symbol: nil,
                callee: interner.intern(name),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    // MARK: - 回転演算
    
    /// 回転演算を処理
    private func lowerRotateOperations(
        calleeStr: String,
        receiverExpr: ExprID,
        argumentID: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let intType = sema.types.intType
        let longType = sema.types.longType
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nonNullReceiverType)
        let receiverID = coordinator.driver.lowerExpr(
            receiverExpr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        if nonNullReceiverType == intType {
            let runtimeName = calleeStr == "rotateLeft" ? "kk_int_rotateLeft" : "kk_int_rotateRight"
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID, argumentID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        } else if nonNullReceiverType == longType {
            let runtimeName = calleeStr == "rotateLeft" ? "kk_long_rotateLeft" : "kk_long_rotateRight"
            context.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeName),
                arguments: [receiverID, argumentID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    // MARK: - 算術操作
    
    /// 算術/ビット単項演算子を処理
    private func lowerArithmeticOperations(
        calleeName: InternedString,
        receiverExpr: ExprID,
        argumentID: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        
        // 引数の型を取得（実際の実装ではargs[0].exprから取得）
        let argType = sema.types.anyType // TODO: 実際の引数型を取得
        let nonNullArgType = sema.types.makeNonNullable(argType)
        
        if nonNullReceiverType == intType || nonNullReceiverType == longType || 
           nonNullReceiverType == uintType || nonNullReceiverType == ulongType {
            
            let isIntegerRhs = nonNullArgType == intType || nonNullArgType == longType || 
                              nonNullArgType == uintType || nonNullArgType == ulongType
            
            let primitiveCallee: InternedString? = switch calleeStr {
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
                let receiverID = coordinator.driver.lowerExpr(
                    receiverExpr,
                    shared: context.sharedContext,
                    emit: context.emitContext()
                )
                
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nonNullReceiverType)
                context.append(.call(
                    symbol: nil,
                    callee: primitiveCallee,
                    arguments: [receiverID, argumentID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        
        return nil
    }
    
    // MARK: - 数値変換
    
    /// 数値変換を処理
    private func lowerNumericConversions(
        calleeStr: String,
        receiverExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let ubyteType = sema.types.ubyteType
        let ushortType = sema.types.ushortType
        let charType = sema.types.charType
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        
        // 結果型は式の型から取得（実際の実装ではexprIDから取得）
        let resultType = sema.types.anyType // TODO: 実際の結果型を取得
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
            let receiverID = coordinator.driver.lowerExpr(
                receiverExpr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
            
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nonNullResultType)
            context.append(.call(
                symbol: nil,
                callee: callee,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    // MARK: - 数値強制
    
    /// 数値強制操作を処理
    func lowerNumericCoercion(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        
        // coerceIn の処理
        if calleeStr == "coerceIn" {
            if args.count == 2 {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    let receiverID = coordinator.driver.lowerExpr(
                        receiverExpr,
                        shared: context.sharedContext,
                        emit: context.emitContext()
                    )
                    
                    let result = context.arena.appendExpr(.temporary(Int32(context.arena.expressions.count)), type: receiverType)
                    context.append(.call(
                        symbol: nil,
                        callee: interner.intern(prefix + "_coerceIn"),
                        arguments: [receiverID] + args,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            } else if args.count == 1 {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema),
                   prefix == "kk_int" || prefix == "kk_long" {
                    
                    // rangeベースの強制
                    // TODO: range判定ロジックを実装
                    return nil
                }
            }
        }
        
        // coerceAtLeast/coerceAtMost の処理
        if args.count == 1 {
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = CallLoweringHelpers.numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast" : "_coerceAtMost"
                    let receiverID = coordinator.driver.lowerExpr(
                        receiverExpr,
                        shared: context.sharedContext,
                        emit: context.emitContext()
                    )
                    
                    let result = context.arena.appendExpr(.temporary(Int32(context.arena.expressions.count)), type: receiverType)
                    context.append(.call(
                        symbol: nil,
                        callee: interner.intern(prefix + suffix),
                        arguments: [receiverID] + args,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }
        
        return nil
    }
    
    // MARK: - ヘルパー関数
    
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
}
