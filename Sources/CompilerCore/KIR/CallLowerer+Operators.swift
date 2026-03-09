import Foundation

extension CallLowerer {
    // MARK: - Binary Operations

    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let lhsID = driver.lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = driver.lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        // Detect whether this is a compareTo-desugared comparison operator.
        // If so, the call binding targets compareTo (returns Int) and we must
        // wrap the result with a comparison against 0 to produce Bool.
        let isCompareToDesugaring: Bool = switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            sema.bindings.callBindings[exprID] != nil
        default:
            false
        }
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil
        {
            // For compareTo desugaring, the call result is Int, not Bool.
            // We allocate a separate temporary for the compareTo call result.
            let callResult: KIRExprID = if isCompareToDesugaring {
                arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            } else {
                result
            }
            if isCompareToDesugaring,
               shouldLowerComparableTypeParamViaRuntime(
                   chosenCallee: callBinding.chosenCallee,
                   receiverExpr: lhs,
                   sema: sema
               )
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_compare_any"),
                    arguments: [lhsID, rhsID],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan: cmpOp = .lessThan
                case .lessOrEqual: cmpOp = .lessOrEqual
                case .greaterThan: cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: erased Comparable runtime path only applies to comparison operators")
                }
                instructions.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
                return result
            }
            let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: [rhsID],
                callBinding: callBinding,
                chosenCallee: callBinding.chosenCallee,
                spreadFlags: [false],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhsID, at: 0)
            if !signature.reifiedTypeParameterIndices.isEmpty {
                for index in signature.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(encodedToken),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
                    finalArguments.append(tokenExpr)
                }
            }
            if normalizedResult.defaultMask != 0,
               sema.symbols.externalLinkName(for: callBinding.chosenCallee)?.isEmpty ?? true
            {
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
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                           !externalLinkName.isEmpty
                {
                    interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    symbol.name
                } else {
                    interner.intern(op.kotlinFunctionName)
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
                case .lessThan: cmpOp = .lessThan
                case .lessOrEqual: cmpOp = .lessOrEqual
                case .greaterThan: cmpOp = .greaterThan
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
                case .lessThan: cmpOp = .lessThan
                case .lessOrEqual: cmpOp = .lessOrEqual
                case .greaterThan: cmpOp = .greaterThan
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
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be lowered through member-call special handling")
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }

    private func shouldLowerComparableTypeParamViaRuntime(
        chosenCallee: SymbolID,
        receiverExpr: ExprID,
        sema: SemaModule
    ) -> Bool {
        guard let comparableSymbol = sema.types.comparableInterfaceSymbol,
              sema.symbols.parentSymbol(for: chosenCallee) == comparableSymbol,
              let receiverType = sema.bindings.exprTypes[receiverExpr]
        else {
            return false
        }
        if case .typeParam = sema.types.kind(of: receiverType) {
            return true
        }
        return false
    }

    // MARK: - Array Operations

    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: interner.intern("get"),
            argumentExprs: indices,
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        if let chosenGet = callBinding?.chosenCallee,
           chosenGet != .invalid,
           let signature = sema.symbols.functionSignature(for: chosenGet),
           signature.receiverType != nil
        {
            let loweredIndices = indices.map { indexExpr in
                driver.lowerExpr(
                    indexExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            emitMemberCallInstruction(
                normalized: driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredIndices,
                    callBinding: callBinding,
                    chosenCallee: chosenGet,
                    spreadFlags: Array(repeating: false, count: loweredIndices.count),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                callBinding: callBinding,
                chosenCallee: chosenGet,
                calleeName: interner.intern("get"),
                receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
                result: result,
                isSuperCall: sema.bindings.isSuperCallExpr(exprID),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: [receiverID] + loweredIndices
            )
            return result
        }
        // Built-in array get only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerIndexedAssignExpr(
        _: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array set only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, valueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIndexedCompoundAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Conceptual desugaring: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // appropriate kk_op_* for the compound operator
        //   3) kk_array_set(a, i, t')
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array compound assign only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Step 1: get current value
        let getResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: getResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 2: apply binary op
        let opResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        guard let expr = ast.arena.expr(exprID),
              case let .indexedCompoundAssign(op, _, _, _, _) = expr
        else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Determine the runtime op stub.
        // Use kk_string_concat for String += String (matching lowerBinaryExpr pattern),
        // otherwise use the appropriate numeric op stub.
        // Note: exprID's bound type is always unitType for compound assign, so we
        // derive the element type from the receiver's array type instead.
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        // Derive element type from the receiver's array type.
        // Mirrors TypeCheckHelpers.arrayElementType logic but also checks
        // the value expression type as a heuristic for non-IntArray receivers.
        let receiverBoundType = sema.bindings.exprTypes[receiverExpr]
        let isStringElement: Bool = {
            guard let recvType = receiverBoundType,
                  case let .classType(classType) = sema.types.kind(of: recvType)
            else {
                return false
            }
            // Prefer the explicit element type from type arguments, if present.
            if let firstArg = classType.args.first {
                let elementType: TypeID? = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: nil
                }
                if let elementType {
                    return elementType == stringType
                }
            }
            return false
        }()
        let opName = if op == .plusAssign, isStringElement {
            "kk_string_concat"
        } else {
            switch op {
            case .plusAssign: "kk_op_add"
            case .minusAssign: "kk_op_sub"
            case .timesAssign: "kk_op_mul"
            case .divAssign: "kk_op_div"
            case .modAssign: "kk_op_mod"
            }
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 3: set new value
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, opResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
