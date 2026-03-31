import Foundation

/// Any型操作のローワーリングを担当する専門クラス
/// Any型のtoString、hashCode、equalsなどの操作を処理する
final class AnyTypeLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要なAny型操作処理
    
    /// Any型操作のローワーリングを試行
    func lowerAnyOperation(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [KIRExprID],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let _ = context.sema
        let interner = context.interner
        let calleeStr = interner.resolve(calleeName)
        
        // Any.toString()
        if args.isEmpty, calleeStr == "toString" {
            return lowerAnyToString(
                receiverExpr: receiverExpr,
                context: &context
            )
        }
        
        // Any.hashCode()
        if args.isEmpty, calleeStr == "hashCode" {
            return lowerAnyHashCode(
                receiverExpr: receiverExpr,
                context: &context
            )
        }
        
        // Any.equals()
        if args.count == 1, calleeStr == "equals" {
            return lowerAnyEquals(
                receiverExpr: receiverExpr,
                argID: args[0],
                context: &context
            )
        }
        
        return nil
    }
    
    // MARK: - Any.toString()
    
    /// Any.toString() のローワーリング
    private func lowerAnyToString(
        receiverExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        
        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [receiverID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// Any.hashCode() のローワーリング
    private func lowerAnyHashCode(
        receiverExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))

        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_hashCode"),
            arguments: [receiverID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// Any.equals() のローワーリング
    private func lowerAnyEquals(
        receiverExpr: ExprID,
        argID: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        // 引数の型を取得（実際の実装ではargs[0].exprから取得）
        let argType = sema.types.anyType // TODO: 実際の引数型を取得
        
        let receiverTag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let argTag = CallLoweringHelpers.anyFallbackTag(for: argType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let booleanType = sema.types.make(.primitive(.boolean, .nonNull))

        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: booleanType)
        let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
        context.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))

        let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
        context.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_equals"),
            arguments: [receiverID, receiverTagID, argID, argTagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - セーフコール用Any操作
    
    /// セーフコール用のAny.toString() のローワーリング
    func lowerSafeAnyToString(
        receiverExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let boundType = sema.types.nullableAnyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)

        // nullチェックと分岐
        let callLabel = coordinator.driver.ctx.makeLoopLabel()
        let endLabel = coordinator.driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: boundType)

        context.append(.jumpIfNotNull(value: receiverID, target: callLabel))
        context.append(.constValue(result: nullExpr, value: .null))
        context.append(.copy(from: nullExpr, to: result))
        context.append(.jump(endLabel))

        context.append(.label(callLabel))
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))

        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [receiverID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        context.append(.label(endLabel))

        return result
    }

    /// セーフコール用のAny.hashCode() のローワーリング
    func lowerSafeAnyHashCode(
        receiverExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let boundType = sema.types.nullableAnyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)

        // nullチェックと分岐
        let callLabel = coordinator.driver.ctx.makeLoopLabel()
        let endLabel = coordinator.driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: boundType)

        context.append(.jumpIfNotNull(value: receiverID, target: callLabel))
        context.append(.constValue(result: nullExpr, value: .null))
        context.append(.copy(from: nullExpr, to: result))
        context.append(.jump(endLabel))

        context.append(.label(callLabel))
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))

        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_hashCode"),
            arguments: [receiverID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        context.append(.label(endLabel))

        return result
    }

    /// セーフコール用のAny.equals() のローワーリング
    func lowerSafeAnyEquals(
        receiverExpr: ExprID,
        argID: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let boundType = sema.types.nullableAnyType
        
        // Anyフォールバックが許可される型か判定
        guard allowsAnyFallback(receiverType, sema: sema) else {
            return nil
        }
        
        // 引数の型を取得（実際の実装ではargs[0].exprから取得）
        let argType = sema.types.anyType // TODO: 実際の引数型を取得
        
        let receiverTag = CallLoweringHelpers.anyFallbackTag(for: receiverType, sema: sema)
        let argTag = CallLoweringHelpers.anyFallbackTag(for: argType, sema: sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let _ = sema.types.make(.primitive(.boolean, .nonNull))
        
        let receiverID = context.lowerSubExpr(receiverExpr, driver: coordinator.driver)

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)

        // nullチェックと分岐
        let callLabel = coordinator.driver.ctx.makeLoopLabel()
        let endLabel = coordinator.driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: boundType)

        context.append(.jumpIfNotNull(value: receiverID, target: callLabel))
        context.append(.constValue(result: nullExpr, value: .null))
        context.append(.copy(from: nullExpr, to: result))
        context.append(.jump(endLabel))

        context.append(.label(callLabel))
        let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
        context.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))

        let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
        context.append(.constValue(result: argTagID, value: .intLiteral(argTag)))

        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_equals"),
            arguments: [receiverID, receiverTagID, argID, argTagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        context.append(.label(endLabel))

        return result
    }

    // MARK: - ヘルパー関数
    
    /// Anyフォールバックが許可される型か判定
    private func allowsAnyFallback(_ type: TypeID, sema: SemaModule) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        return switch sema.types.kind(of: nonNullType) {
        case .primitive(.string, _):
            false
        case .primitive:
            true
        case .typeParam:
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        default:
            nonNullType == sema.types.anyType
        }
    }

    /// Any型のタグを取得
    func getAnyTypeTag(_ type: TypeID, sema: SemaModule) -> Int64 {
        return CallLoweringHelpers.anyFallbackTag(for: type, sema: sema)
    }
    
    /// Any型のtoString変換を生成
    func emitAnyToStringConversion(
        valueID: KIRExprID,
        type: TypeID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: type, sema: sema)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [valueID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }
    
    /// Any型のhashCode計算を生成
    func emitAnyHashCodeCalculation(
        valueID: KIRExprID,
        type: TypeID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let tag = CallLoweringHelpers.anyFallbackTag(for: type, sema: sema)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        context.append(.constValue(result: tagID, value: .intLiteral(tag)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_hashCode"),
            arguments: [valueID, tagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }
    
    /// Any型のequals比較を生成
    func emitAnyEqualsComparison(
        lhsID: KIRExprID,
        lhsType: TypeID,
        rhsID: KIRExprID,
        rhsType: TypeID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let lhsTag = CallLoweringHelpers.anyFallbackTag(for: lhsType, sema: sema)
        let rhsTag = CallLoweringHelpers.anyFallbackTag(for: rhsType, sema: sema)
        
        let lhsTagID = arena.appendExpr(.intLiteral(lhsTag), type: intType)
        context.append(.constValue(result: lhsTagID, value: .intLiteral(lhsTag)))
        
        let rhsTagID = arena.appendExpr(.intLiteral(rhsTag), type: intType)
        context.append(.constValue(result: rhsTagID, value: .intLiteral(rhsTag)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_equals"),
            arguments: [lhsID, lhsTagID, rhsID, rhsTagID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }
}
