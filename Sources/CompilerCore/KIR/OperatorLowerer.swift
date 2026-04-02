import Foundation

/// 演算子のローワーリングを担当する専門クラス
/// 二項演算子、単項演算子、文字列連結、シーケンス操作などを処理する
final class OperatorLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要な演算子処理
    
    /// 二項演算子式のローワーリング
    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        // オペランドのローワーリング
        let lhsID = context.lowerSubExpr(lhs, driver: coordinator.driver)
        let rhsID = context.lowerSubExpr(rhs, driver: coordinator.driver)
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        
        // compareTo脱糖の検出
        let isCompareToDesugaring: Bool = switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            sema.bindings.callBindings[exprID] != nil
        default:
            false
        }

        // STDLIB-OP-031: equals脱糖の検出 (!=はequals()を呼んで結果をnotする)
        let isEqualsDesugaring: Bool = op == .notEqual
            && sema.bindings.callBindings[exprID] != nil
        
        // compareTo/equals脱糖の処理
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
            let isNominalMemberOperator = if let owner = sema.symbols.parentSymbol(for: callBinding.chosenCallee),
                                            let ownerSymbol = sema.symbols.symbol(owner) {
                switch ownerSymbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass:
                    true
                default:
                    false
                }
            } else {
                false
            }
            if signature.receiverType != nil || isNominalMemberOperator {
                return handleCompareToDesugaring(
                    op: op,
                    lhsID: lhsID,
                    lhsExpr: lhs,
                    rhsID: rhsID,
                    callBinding: callBinding,
                    isCompareToDesugaring: isCompareToDesugaring,
                    isEqualsDesugaring: isEqualsDesugaring,
                    result: result,
                    context: &context
                )
            }
        }
        
        // シーケンスのplus/minus演算子 (STDLIB-561/562)
        if let sequenceResult = handleSequenceOperations(
            op: op,
            lhsID: lhsID,
            rhsID: rhsID,
            lhsExpr: lhs,
            rhsExpr: rhs,
            result: result,
            context: &context
        ) {
            return sequenceResult
        }
        
        // Listのplus/minus演算子 (STDLIB-345)
        if let listResult = handleListOperations(
            op: op,
            lhsID: lhsID,
            rhsID: rhsID,
            lhsExpr: lhs,
            rhsExpr: rhs,
            exprID: exprID,
            result: result,
            context: &context
        ) {
            return listResult
        }
        
        // 文字列連結の特殊処理
        if op == .add, sema.bindings.exprTypes[exprID] == sema.types.stringType {
            return handleStringConcatenation(
                lhsID: lhsID,
                rhsID: rhsID,
                lhsExpr: lhs,
                rhsExpr: rhs,
                result: result,
                context: &context
            )
        }
        
        // 文字列比較の特殊処理
        if let stringComparisonResult = handleStringComparison(
            op: op,
            lhsID: lhsID,
            rhsID: rhsID,
            lhsExpr: lhs,
            rhsExpr: rhs,
            result: result,
            context: &context
        ) {
            return stringComparisonResult
        }
        
        // ビルドイン二項演算子の処理
        if let runtimeCallee = coordinator.driver.callSupportLowerer.builtinBinaryRuntimeCallee(for: op, interner: interner) {
            context.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        
        // KIR二項演算子の処理
        return handleKIRBinaryOp(
            op: op,
            lhsID: lhsID,
            rhsID: rhsID,
            result: result,
            context: &context
        )
    }
    
    // MARK: - 特殊な演算子処理
    
    /// compareTo/equals脱糖を処理
    private func handleCompareToDesugaring(
        op: BinaryOp,
        lhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsID: KIRExprID,
        callBinding: CallBinding,
        isCompareToDesugaring: Bool,
        isEqualsDesugaring: Bool = false,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.booleanType

        // STDLIB-OP-031: For !=, equals() returns Bool; we store in a temporary
        // and negate afterward.
        let callResult: KIRExprID = if isCompareToDesugaring {
            arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        } else if isEqualsDesugaring {
            arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        } else {
            result
        }
        
        // Comparable型パラメータのランタイム処理
        if isCompareToDesugaring,
           shouldLowerComparableTypeParamViaRuntime(
               chosenCallee: callBinding.chosenCallee,
               receiverExpr: lhsExpr,
               sema: sema
           ) {
            context.append(.call(
                symbol: nil,
                callee: interner.intern("kk_compare_any"),
                arguments: [lhsID, rhsID],
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
            
            return emitCompareToComparison(
                op: op,
                callResult: callResult,
                result: result,
                context: &context
            )
        }
        
        // 通常のcompareTo呼び出し
        let normalizedResult = coordinator.driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: [rhsID],
            originalArgs: [CallArgument(label: nil, isSpread: false, expr: lhsExpr)],
            callBinding: callBinding,
            chosenCallee: callBinding.chosenCallee,
            spreadFlags: [false],
            ast: context.ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: context.propertyConstantInitializers,
            instructions: &context.instructions
        )
        
        var finalArguments = normalizedResult.arguments
        finalArguments.insert(lhsID, at: 0)
        
        // Reified型パラメータの処理
        let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee)
        if !(signature?.reifiedTypeParameterIndices.isEmpty ?? true) {
            for index in (signature?.reifiedTypeParameterIndices.sorted() ?? []) {
                let concreteType = index < callBinding.substitutedTypeArguments.count
                    ? callBinding.substitutedTypeArguments[index]
                    : sema.types.anyType
                let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
                let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
                context.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
                finalArguments.append(tokenExpr)
            }
        }
        
        // デフォルトマスクの処理
        if normalizedResult.defaultMask != 0,
           sema.symbols.externalLinkName(for: callBinding.chosenCallee)?.isEmpty ?? true {
            
            let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
            context.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
            finalArguments.append(maskExpr)
            
            let stubName = interner.intern(
                (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
            )
            let stubSym = coordinator.driver.callSupportLowerer.defaultStubSymbol(for: callBinding.chosenCallee)
            
            context.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                           !externalLinkName.isEmpty {
                interner.intern(externalLinkName)
            } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                symbol.name
            } else {
                interner.intern(op.kotlinFunctionName)
            }
            
            context.append(.call(
                symbol: callBinding.chosenCallee,
                callee: loweredCalleeName,
                arguments: finalArguments,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        // compareTo脱糖の場合は比較結果を生成
        if isCompareToDesugaring {
            return emitCompareToComparison(
                op: op,
                callResult: callResult,
                result: result,
                context: &context
            )
        }

        // STDLIB-OP-031: != は equals() の結果を反転
        if isEqualsDesugaring {
            context.append(.unary(op: .not, operand: callResult, result: result))
            return result
        }

        return callResult
    }
    
    /// シーケンス操作を処理
    private func handleSequenceOperations(
        op: BinaryOp,
        lhsID: KIRExprID,
        rhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        if isSequenceLikeType(sema.bindings.exprTypes[lhsExpr] ?? sema.types.anyType, sema: sema, interner: interner) {
            if op == .add {
                let effectiveRHS: KIRExprID
                if sema.bindings.isCollectionExpr(rhsExpr) {
                    // RHSは既にコレクションハンドル
                    effectiveRHS = rhsID
                } else {
                    // 単一要素を単一要素シーケンスでラップ
                    let wrappedExpr = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)), type: nil
                    )
                    context.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_of_single"),
                        arguments: [rhsID],
                        result: wrappedExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    effectiveRHS = wrappedExpr
                }
                
                context.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_plus"),
                    arguments: [lhsID, effectiveRHS],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            
            if op == .subtract {
                if !sema.bindings.isCollectionExpr(rhsExpr) {
                    // 単一要素削除
                    context.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_minus"),
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // コレクション削除は未サポート
                context.append(.copy(from: lhsID, to: result))
                return result
            }
        }
        
        return nil
    }
    
    /// List操作を処理
    private func handleListOperations(
        op: BinaryOp,
        lhsID: KIRExprID,
        rhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        exprID: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        if (op == .add || op == .subtract), 
           sema.bindings.isCollectionExpr(exprID),
           isConcreteListLikeType(sema.bindings.exprTypes[lhsExpr] ?? sema.types.anyType, sema: sema, interner: interner) {
            
            let calleeName: String
            if op == .subtract {
                let rhsIsCollection = sema.bindings.isCollectionExpr(rhsExpr)
                calleeName = rhsIsCollection ? "kk_list_minus_collection" : "kk_list_minus_element"
            } else {
                let rhsIsCollection = sema.bindings.isCollectionExpr(rhsExpr)
                calleeName = rhsIsCollection ? "kk_list_plus_collection" : "kk_list_plus_element"
            }
            
            context.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        
        return nil
    }
    
    /// 文字列連結を処理
    private func handleStringConcatenation(
        lhsID: KIRExprID,
        rhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let nullableStringType = sema.types.make(.primitive(.string, .nullable))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        // RHSの文字列変換
        let rhsExprType = sema.bindings.exprTypes[rhsExpr]
        let effectiveRHS: KIRExprID
        if rhsExprType == stringType || rhsExprType == nullableStringType {
            effectiveRHS = rhsID
        } else {
            let tag = CallLoweringHelpers.anyFallbackTag(for: rhsExprType ?? sema.types.anyType, sema: sema)
            let tagExpr = arena.appendExpr(.intLiteral(tag), type: intType)
            context.append(.constValue(result: tagExpr, value: .intLiteral(tag)))
            
            let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
            context.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [rhsID, tagExpr],
                result: converted,
                canThrow: false,
                thrownResult: nil
            ))
            effectiveRHS = converted
        }
        
        // LHSの文字列変換
        let lhsExprType = sema.bindings.exprTypes[lhsExpr]
        let effectiveLHS: KIRExprID
        if lhsExprType == stringType || lhsExprType == nullableStringType {
            effectiveLHS = lhsID
        } else {
            let tag = CallLoweringHelpers.anyFallbackTag(for: lhsExprType ?? sema.types.anyType, sema: sema)
            let tagExpr = arena.appendExpr(.intLiteral(tag), type: intType)
            context.append(.constValue(result: tagExpr, value: .intLiteral(tag)))
            
            let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
            context.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [lhsID, tagExpr],
                result: converted,
                canThrow: false,
                thrownResult: nil
            ))
            effectiveLHS = converted
        }
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_concat"),
            arguments: [effectiveLHS, effectiveRHS],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// 文字列比較を処理
    private func handleStringComparison(
        op: BinaryOp,
        lhsID: KIRExprID,
        rhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let nullableStringType = sema.types.make(.primitive(.string, .nullable))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let lhsType = sema.bindings.exprTypes[lhsExpr]
        let rhsType = sema.bindings.exprTypes[rhsExpr]
        let isStringOperand = (lhsType == stringType || lhsType == nullableStringType) &&
                           (rhsType == stringType || rhsType == nullableStringType)
        
        if isStringOperand {
            switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                let compareResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                context.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareTo"),
                    arguments: [lhsID, rhsID],
                    result: compareResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                context.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                
                let cmpOp: KIRBinaryOp = switch op {
                case .lessThan: .lessThan
                case .lessOrEqual: .lessOrEqual
                case .greaterThan: .greaterThan
                case .greaterOrEqual: .greaterOrEqual
                default: fatalError("Unexpected comparison operator for string operands")
                }
                
                context.append(.binary(op: cmpOp, lhs: compareResult, rhs: zeroExpr, result: result))
                return result
            default:
                break
            }
        }
        
        return nil
    }
    
    /// KIR二項演算子を処理
    private func handleKIRBinaryOp(
        op: BinaryOp,
        lhsID: KIRExprID,
        rhsID: KIRExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        // 特殊な演算子の処理（ランタイム関数呼び出しが必要なもの）
        switch op {
        case .elvis:
            context.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_elvis"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeTo:
            let rangeToCallee = arena.exprType(result) == sema.types.uintType
                ? interner.intern("kk_uint_rangeTo")
                : interner.intern("kk_op_rangeTo")
            context.append(.call(
                symbol: nil,
                callee: rangeToCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeUntil:
            context.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeUntil"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .downTo:
            let downToCallee = arena.exprType(result) == sema.types.uintType
                ? interner.intern("kk_uint_downTo")
                : interner.intern("kk_op_downTo")
            context.append(.call(
                symbol: nil,
                callee: downToCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .step:
            let stepCallee = arena.exprType(result) == sema.types.uintType
                ? interner.intern("kk_uint_step")
                : interner.intern("kk_op_step")
            context.append(.call(
                symbol: nil,
                callee: stepCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be lowered through member-call special handling")
        default:
            break
        }

        let kirOp: KIRBinaryOp = switch op {
        case .add: .add
        case .subtract: .subtract
        case .multiply: .multiply
        case .divide: .divide
        case .modulo: .modulo
        case .equal: .equal
        case .notEqual: .notEqual
        case .lessThan: .lessThan
        case .lessOrEqual: .lessOrEqual
        case .greaterThan: .greaterThan
        case .greaterOrEqual: .greaterOrEqual
        case .logicalAnd: .logicalAnd
        case .logicalOr: .logicalOr
        default:
            preconditionFailure("Unexpected operator in KIRBinaryOp switch: \(op)")
        }

        context.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }
    
    // MARK: - ヘルパー関数
    
    /// compareTo比較を生成
    private func emitCompareToComparison(
        op: BinaryOp,
        callResult: KIRExprID,
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let intType = sema.types.make(.primitive(.int, .nonNull))
        
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
        context.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        
        let cmpOp: KIRBinaryOp = switch op {
        case .lessThan: .lessThan
        case .lessOrEqual: .lessOrEqual
        case .greaterThan: .greaterThan
        case .greaterOrEqual: .greaterOrEqual
        default: fatalError("Unexpected comparison operator for compareTo desugaring")
        }
        
        context.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
        return result
    }
    
    /// Comparable型パラメータをランタイム経由でローワーリングするか判定
    private func shouldLowerComparableTypeParamViaRuntime(
        chosenCallee: SymbolID,
        receiverExpr: ExprID,
        sema: SemaModule
    ) -> Bool {
        guard let comparableSymbol = sema.types.comparableInterfaceSymbol,
              sema.symbols.parentSymbol(for: chosenCallee) == comparableSymbol,
              let receiverType = sema.bindings.exprTypes[receiverExpr] else {
            return false
        }
        
        if case .typeParam = sema.types.kind(of: receiverType) {
            return true
        }
        return false
    }
    
    /// シーケンスライク型か判定
    private func isSequenceLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        
        return knownNames.isSequenceSymbol(symbol) || knownNames.isCollectionLikeSymbol(symbol)
    }
    
    /// 具体的なListライク型か判定
    private func isConcreteListLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        
        return knownNames.isConcreteListLikeSymbol(symbol) || knownNames.isMutableListSymbol(symbol)
    }
}
