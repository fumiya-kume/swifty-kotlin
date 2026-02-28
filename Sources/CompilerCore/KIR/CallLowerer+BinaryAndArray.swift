import Foundation

extension CallLowerer {
    // MARK: - Binary Operations

    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let lhsID = driver.lowerExpr(
            lhs,
            shared: shared,
            emit: &instructions
        )
        let rhsID = driver.lowerExpr(
            rhs,
            shared: shared,
            emit: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        // Detect whether this is a compareTo-desugared comparison operator.
        // If so, the call binding targets compareTo (returns Int) and we must
        // wrap the result with a comparison against 0 to produce Bool.
        let isCompareToDesugaring: Bool
        switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            isCompareToDesugaring = sema.bindings.callBindings[exprID] != nil
        default:
            isCompareToDesugaring = false
        }
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil {
            // For compareTo desugaring, the call result is Int, not Bool.
            // We allocate a separate temporary for the compareTo call result.
            let callResult: KIRExprID
            if isCompareToDesugaring {
                callResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            } else {
                callResult = result
            }
            let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: [rhsID],
                callBinding: callBinding,
                chosenCallee: callBinding.chosenCallee,
                spreadFlags: [false],
                shared: shared,
                emit: &instructions
            )
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhsID, at: 0)
            if !signature.reifiedTypeParameterIndices.isEmpty {
                for index in signature.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            if normalizedResult.defaultMask != 0 {
                let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(
                    (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                )
                let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: callBinding.chosenCallee)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let loweredCalleeName: InternedString
                if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    loweredCalleeName = symbol.name
                } else {
                    loweredCalleeName = driver.callSupportLowerer.binaryOperatorFunctionName(for: op, interner: interner)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            // compareTo desugaring: emit `compareTo(a,b) <op> 0` to produce Bool
            if isCompareToDesugaring {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan:     cmpOp = .lessThan
                case .lessOrEqual:  cmpOp = .lessOrEqual
                case .greaterThan:  cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: isCompareToDesugaring should only be true for comparison operators")
                }
                instructions.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
            }
            return result
        }
        if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        // String comparison desugaring: route <, <=, >, >= on String operands
        // through kk_string_compareTo (content comparison) instead of the default
        // kk_op_lt/le/gt/ge path which compares raw pointer addresses.
        let lhsType = sema.bindings.exprTypes[lhs]
        let rhsType = sema.bindings.exprTypes[rhs]
        let nullableStringType = sema.types.make(.primitive(.string, .nullable))
        let isStringOperand = (lhsType == stringType || lhsType == nullableStringType)
                           && (rhsType == stringType || rhsType == nullableStringType)
        if isStringOperand {
            switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                let compareResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareTo"),
                    arguments: [lhsID, rhsID],
                    result: compareResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan:      cmpOp = .lessThan
                case .lessOrEqual:   cmpOp = .lessOrEqual
                case .greaterThan:   cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: unexpected comparison operator for string operands")
                }
                instructions.append(.binary(op: cmpOp, lhs: compareResult, rhs: zeroExpr, result: result))
                return result
            default:
                break
            }
        }
        if let runtimeCallee = driver.callSupportLowerer.builtinBinaryRuntimeCallee(for: op, interner: interner) {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .subtract:
            kirOp = .subtract
        case .multiply:
            kirOp = .multiply
        case .divide:
            kirOp = .divide
        case .modulo:
            kirOp = .modulo
        case .equal:
            kirOp = .equal
        case .notEqual:
            kirOp = .notEqual
        case .lessThan:
            kirOp = .lessThan
        case .lessOrEqual:
            kirOp = .lessOrEqual
        case .greaterThan:
            kirOp = .greaterThan
        case .greaterOrEqual:
            kirOp = .greaterOrEqual
        case .logicalAnd:
            kirOp = .logicalAnd
        case .logicalOr:
            kirOp = .logicalOr
        case .elvis:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_elvis"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeUntil:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeUntil"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .downTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_downTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .step:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_step"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .bitwiseAnd:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_bitwise_and"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .bitwiseOr:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_bitwise_or"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .bitwiseXor:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_bitwise_xor"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .shl:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_shl"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .shr:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_shr"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .ushr:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_ushr"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }

    // MARK: - Array Operations

}
