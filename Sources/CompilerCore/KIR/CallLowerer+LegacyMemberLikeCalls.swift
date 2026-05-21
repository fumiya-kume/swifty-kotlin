// swiftlint:disable file_length
import Foundation

/// Legacy stdlib/member special-case lowering path.
///
/// This remains deliberately isolated while narrower families continue to move out.
extension CallLowerer {
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This shared lowering path still centralizes legacy stdlib/member special cases.
    func lowerMemberLikeCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        prependReceiverForUnresolvedCollectionCall: Bool,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // swiftlint:enable cyclomatic_complexity function_body_length
        if let foldedConst = tryFoldConstMemberProperty(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            requireNonNullableReceiver: requireNonNullableReceiverForConstFold,
            sema: sema,
            arena: arena,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return foldedConst
        }
        if let constValue = sema.bindings.constExprValue(for: exprID) {
            let constResult = arena.appendExpr(
                constValue,
                type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            )
            instructions.append(.constValue(result: constResult, value: constValue))
            return constResult
        }
        if let staticMemberValue = tryLowerClassNameMemberValueExpr(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            instructions: &instructions
        ) {
            return staticMemberValue
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let argInstructionStart = instructions.count
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let normalizedArgIDs: [KIRExprID] = {
            guard isCollectionHOFCallee(calleeName, interner: interner) else {
                return loweredArgIDs
            }
            let closureAdapted = addCollectionHOFClosureArguments(
                loweredArgIDs: loweredArgIDs,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return adaptComparatorFactoryArgumentsForCollectionHOF(
                calleeName: calleeName,
                loweredArgIDs: closureAdapted,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        if args.count == 1,
           interner.resolve(calleeName) == "withDefault"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if isMapLikeType(receiverType, sema: sema, interner: interner) {
                let runtimeArguments: [KIRExprID]
                if normalizedArgIDs.count >= 2 {
                    runtimeArguments = [loweredReceiverID, normalizedArgIDs[0], normalizedArgIDs[1]]
                } else if let defaultValueArg = normalizedArgIDs.first {
                    let split = splitCallableLambdaArgument(
                        defaultValueArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, split.fnPtrExpr, split.envPtrExpr]
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    runtimeArguments = [loweredReceiverID, zeroExpr, zeroExpr]
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_map_withDefault"),
                    arguments: runtimeArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        let chosenBase64Callee: SymbolID? = {
            guard let selected = sema.bindings.callBindings[exprID]?.chosenCallee, selected != .invalid else {
                return nil
            }
            return selected
        }()

        if tryLowerBase64MemberCall(
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            calleeName: calleeName,
            chosenCallee: chosenBase64Callee,
            argExprIDs: args.map(\.expr),
            loweredArgIDs: loweredArgIDs,
            argInstructionStart: argInstructionStart,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return result
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isComparatorLambdaArg = ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
            if isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner),
               !isComparatorLambdaArg
            {
                let sortedWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: interner.intern("kk_list_sortedWith"),
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_sortedWith"),
                    arguments: sortedWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedArrayWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee = interner.intern("kk_array_sortedArrayWith")
                let sortedArrayWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: runtimeCallee,
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: sortedArrayWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString? = switch interner.resolve(calleeName) {
            case "any":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_any")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_any")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_any")
                } else {
                    nil
                }
            case "none":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_none")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_none")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_none")
                } else {
                    nil
                }
            default:
                nil
            }
            if let runtimeCallee {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isRangeLikeReceiver = sema.bindings.isRangeExpr(receiverExpr) || {
                guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                let name = interner.resolve(symbol.name)
                return name == "IntProgression"
                    || name == "LongProgression"
                    || name == "LongRange"
                    || name == "CharProgression"
                    || name == "UIntRange"
                    || name == "UIntProgression"
                    || name == "ULongProgression"
            }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver {
                let runtimeGetter: InternedString? = switch interner.resolve(calleeName) {
                case "start":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "end":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "endExclusive":
                    interner.intern("kk_range_endExclusive")
                case "first":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "last":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "step":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_step"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_step"
                            : (isLongRange ? "kk_long_range_step" : "kk_range_step")))
                default:
                    nil
                }
                if let runtimeGetter {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeGetter,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if let storedObjectProperty = tryLowerObjectLiteralStoredPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedObjectProperty
        }

        if let enumEntryProperty = tryLowerEnumEntryPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return enumEntryProperty
        }

        if let externalMemberProperty = tryLowerExternalMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return externalMemberProperty
        }

        if let storedMemberProperty = tryLowerStoredMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedMemberProperty
        }

        if args.isEmpty,
           calleeName == interner.intern("step")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString = if sema.bindings.isULongRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.ulongType
            {
                interner.intern("kk_ulong_range_step")
            } else if sema.bindings.isUIntRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.uintType
            {
                interner.intern("kk_uint_range_step")
            } else {
                interner.intern("kk_range_step")
            }
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive member function: Int/Long.inv() → kk_op_inv (P5-103)
        if calleeName == interner.intern("inv"),
           args.isEmpty,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_inv"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        // NOTE: This bit-count lowering logic is intentionally duplicated in
        // CallLowerer+SafeMemberCalls.swift for the safe-call (?.) path.
        // If you change the callee-name -> runtime-name mapping here, update
        // the other file as well. Consider extracting a shared helper if the
        // number of bit-operation intrinsics grows further.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "countOneBits" || calleeStr == "countLeadingZeroBits" || calleeStr == "countTrailingZeroBits" ||
               calleeStr == "highestOneBit" || calleeStr == "lowestOneBit" || calleeStr == "takeHighestOneBit" || calleeStr == "takeLowestOneBit" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "countOneBits": runtimeName = "kk_int_countOneBits"
                    case "countLeadingZeroBits": runtimeName = "kk_int_countLeadingZeroBits"
                    case "countTrailingZeroBits": runtimeName = "kk_int_countTrailingZeroBits"
                    case "highestOneBit": runtimeName = "kk_int_highestOneBit"
                    case "lowestOneBit": runtimeName = "kk_int_lowestOneBit"
                    case "takeHighestOneBit": runtimeName = "kk_int_takeHighestOneBit"
                    case "takeLowestOneBit": runtimeName = "kk_int_takeLowestOneBit"
                    default: fatalError("unreachable: calleeStr already guarded to bit operation functions")
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Int.rotateLeft() / rotateRight() (STDLIB-BIT-007)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "rotateLeft": runtimeName = "kk_int_rotateLeft"
                    case "rotateRight": runtimeName = "kk_int_rotateRight"
                    default: fatalError("unreachable: calleeStr already guarded to rotate functions")
                    }
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Long bit manipulation functions (STDLIB-BIT-007)
        let longType = sema.types.longType
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)

        if nonNullReceiverType == longType {
            let calleeStr = interner.resolve(calleeName)

            // Zero-argument functions
            if args.isEmpty {
                let runtimeName: String?
                switch calleeStr {
                case "highestOneBit": runtimeName = "kk_long_highestOneBit"
                case "lowestOneBit": runtimeName = "kk_long_lowestOneBit"
                case "takeHighestOneBit": runtimeName = "kk_long_takeHighestOneBit"
                case "takeLowestOneBit": runtimeName = "kk_long_takeLowestOneBit"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }

            // Single-argument functions (rotate)
            if args.count == 1 {
                let runtimeName: String?
                switch calleeStr {
                case "rotateLeft": runtimeName = "kk_long_rotateLeft"
                case "rotateRight": runtimeName = "kk_long_rotateRight"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Boolean.not() → kk_op_not (STDLIB-308)
        if calleeName == interner.intern("not"),
           args.isEmpty
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_not"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                let boolCallee: InternedString? = switch interner.resolve(calleeName) {
                case "and":
                    interner.intern("kk_bitwise_and")
                case "or":
                    interner.intern("kk_bitwise_or")
                case "xor":
                    interner.intern("kk_bitwise_xor")
                default:
                    nil
                }
                if let boolCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: boolCallee,
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Float.mod(other) / Double.mod(other): Kotlin mod uses floor-style
        // modulo, while rem/% use truncating remainder.
        if args.count == 1,
           interner.resolve(calleeName) == "mod"
        {
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            let isFloatingReceiver = nonNullReceiverType == floatType || nonNullReceiverType == doubleType
            let isFloatingRhs = nonNullRhsType == floatType || nonNullRhsType == doubleType
            if isFloatingReceiver, isFloatingRhs {
                let resultType = nonNullReceiverType == doubleType || nonNullRhsType == doubleType ? doubleType : floatType
                var lhs = loweredReceiverID
                var rhs = loweredArgIDs[0]
                if resultType == doubleType {
                    if nonNullReceiverType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [lhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [rhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        rhs = converted
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(resultType == doubleType ? "kk_op_dfloor_mod" : "kk_op_ffloor_mod"),
                    arguments: [lhs, rhs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers.
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rawRhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rawRhsType)
            let isShiftReceiver = nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
            let isUnsignedReceiver = nonNullReceiverType == uintType || nonNullReceiverType == ulongType || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
            case "plus":
                interner.intern("kk_op_add")
            case "minus":
                interner.intern("kk_op_sub")
            case "times":
                interner.intern("kk_op_mul")
            case "div":
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_div")
            case "floorDiv":
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_floor_div")
            case "rem":
                isUnsignedReceiver ? interner.intern("kk_op_urem") : interner.intern("kk_op_mod")
            case "mod":
                isUnsignedReceiver
                    ? interner.intern("kk_op_urem")
                    : interner.intern(nonNullReceiverType == longType || nonNullRhsType == longType ? "kk_op_lfloor_mod" : "kk_op_floor_mod")
            case "and":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_and") : nil
            case "or":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_ushr") : nil
            default:
                nil
            }
            if let primitiveCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: primitiveCallee,
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceIn(min, max) (STDLIB-150, STDLIB-500)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(prefix + "_coerceIn"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/UInt/ULong.coerceIn(range) — single ClosedRange argument (STDLIB-525, STDLIB-CONV-006)
        // Decompose the range into first/last and delegate to kk_{int,long,uint,ulong}_coerceIn.
        // The shared emitCoerceInRange helper types the extracted bounds as the non-nullable
        // receiver type and kk_range_first/kk_range_last return the range's element type.
        if interner.resolve(calleeName) == "coerceIn", args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let intType = sema.types.intType
            let longType = sema.types.longType
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let supportsRangeCoercion = receiverType == intType || receiverType == longType
                || receiverType == uintType || receiverType == ulongType
            if supportsRangeCoercion,
               let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let argExprID = args[0].expr
                let argType = sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
                if sema.bindings.isRangeExpr(argExprID)
                    || nominalRangeElementType(for: argType, sema: sema, interner: interner) != nil
                {
                    emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiverID,
                        loweredRangeArgID: loweredArgIDs[0],
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return result
                }
            }
        }

        // Int/Long/Double/Float/Byte/Short/UByte/UShort/UInt/ULong.coerceAtLeast(min)
        // / coerceAtMost(max) (STDLIB-150, STDLIB-500)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    // Check if this is range-based coercion (single range argument)
                    if args.count == 1 {
                        let argExprID = args[0].expr
                        if sema.bindings.isRangeExpr(argExprID) {
                            // Use range-based coercion functions
                            let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast_range" : "_coerceAtMost_range"
                            instructions.append(.call(
                                symbol: nil,
                                callee: interner.intern(prefix + suffix),
                                arguments: [loweredReceiverID, loweredArgIDs[0]],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            return result
                        }
                    }
                    // Fallback to single-value coercion
                    let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast" : "_coerceAtMost"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(prefix + suffix),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Primitive member function: Int/Long.toString() → kk_any_to_string
        // and Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if calleeName == interner.intern("toString"),
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                if args.isEmpty {
                    let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                    instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [loweredReceiverID, tagID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_int_toString_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let allowsAnyFallback: Bool = switch sema.types.kind(of: nonNullAnyFallbackReceiverType) {
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
            nonNullAnyFallbackReceiverType == sema.types.anyType
        }
        // Any.toString(): String — no-arg fallback via kk_any_to_string (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "toString", allowsAnyFallback {
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
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
            return result
        }

        // Any.hashCode(): Int — via kk_any_hashCode (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_hashCode"),
                arguments: [loweredReceiverID, receiverTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.equals(other: Any?): Boolean — via kk_any_equals (STDLIB-306)
        if args.count == 1, interner.resolve(calleeName) == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredArgIDs[0], argTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let calleeStr = interner.resolve(calleeName)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", charType, intType): nil // identity (Char is stored as Int)
            case ("toInt", intType, intType): nil // identity
            case ("toChar", intType, charType): nil // identity (Char is stored as Int)
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
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", charType, ulongType): interner.intern("kk_char_to_ulong")
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
            case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
            case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
            case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
            case ("toChar", longType, charType): interner.intern("kk_long_to_char")
            case ("toChar", uintType, charType): interner.intern("kk_uint_to_char")
            case ("toChar", ulongType, charType): interner.intern("kk_ulong_to_char")
            case ("toChar", ubyteType, charType): interner.intern("kk_ubyte_to_char")
            case ("toChar", ushortType, charType): interner.intern("kk_ushort_to_char")
            case ("toChar", charType, charType): nil // identity
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toUInt" && nonNullReceiverType == ulongType && nonNullResultType == uintType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && nonNullReceiverType == charType && nonNullResultType == intType)
                    || (calleeStr == "toChar" && nonNullReceiverType == intType && nonNullResultType == charType)
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toUByte", "toUShort", "toChar"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
               || nonNullReceiverType == charType
            {
                instructions.append(.copy(from: loweredReceiverID, to: result))
                return result
            }
        }

        if args.isEmpty, interner.resolve(calleeName) == "length" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_length"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Char.digitToInt() / Char.digitToIntOrNull() (STDLIB-083)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "digitToInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "digitToIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Char.code → identity (Char is stored as its Int code point) (STDLIB-305)
                if calleeStr == "code" {
                    instructions.append(.copy(from: loweredReceiverID, to: result))
                    return result
                }
            }
        }

        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int) — 1-arg overload
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType, interner.resolve(calleeName) == "digitToInt" {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_char_digitToInt_radix"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // filterIsInstance<R>() — encode type token from result type (STDLIB-114 / STDLIB-SEQ-FN-026)
        if args.isEmpty, interner.resolve(calleeName) == "filterIsInstance" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from List<R> or Sequence<R>.
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let runtimeCallee = isSequenceLikeType(sema.types.makeNonNullable(receiverType), sema: sema, interner: interner)
                ? "kk_sequence_filterIsInstance"
                : "kk_list_filterIsInstance"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeCallee),
                arguments: [loweredReceiverID, tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // filterIsInstanceTo<R>(destination) — encode type token from result type (STDLIB-021)
        if args.count == 1, interner.resolve(calleeName) == "filterIsInstanceTo" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from MutableCollection<R>
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            let nonNullReceiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType)
            let runtimeCallee = if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                interner.intern("kk_sequence_filterIsInstanceTo")
            } else {
                interner.intern("kk_list_filterIsInstanceTo")
            }
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [loweredReceiverID, loweredArgIDs[0], tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // String stdlib: nullable-receiver 0-arg methods (NULL-002)
        // isNullOrEmpty/isNullOrBlank pass the raw (potentially null) receiver pointer to C runtime.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if sema.bindings.callBindings[exprID] == nil,
               calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if calleeStr == "isNullOrEmpty",
                   let runtimeCallee = collectionIsNullOrEmptyRuntimeCallee(
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                   )
                {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    let runtimeCallee = calleeStr == "isNullOrEmpty"
                        ? "kk_string_isNullOrEmpty"
                        : "kk_string_isNullOrBlank"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // STDLIB-532/533/534, STDLIB-SEQ-011: orEmpty() on nullable receivers
            if sema.bindings.callBindings[exprID] == nil, calleeStr == "orEmpty" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isMapLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_map_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }
        // String stdlib: 0-arg methods (STDLIB-006)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "trim" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_trim"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "lowercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_lowercase"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "uppercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_uppercase"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDouble" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDouble"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDoubleOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDoubleOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "reversed" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_reversed"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toList" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toList"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toCharArray" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toCharArray"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toRegex" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toRegex"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "lines" || calleeStr == "lineSequence" {
                    let rtName = calleeStr == "lineSequence"
                        ? "kk_string_lineSequence" : "kk_string_lines"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(rtName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "kk_string_first"
                        : calleeStr == "last" ? "kk_string_last"
                        : "kk_string_single"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull"
                        : calleeStr == "lastOrNull" ? "kk_string_lastOrNull"
                        : "kk_string_singleOrNull"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeName == interner.intern("zipWithNext") {
                    // String.zipWithNext overload dispatch: no-arg → kk_string_zipWithNext,
                    // transform → kk_string_zipWithNextTransform.
                    let runtimeCallee = args.isEmpty ? "kk_string_zipWithNext" : "kk_string_zipWithNextTransform"
                    let callArguments = args.isEmpty ? [loweredReceiverID] : [loweredReceiverID] + normalizedArgIDs
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: !args.isEmpty,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asSequence" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asSequence"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let isCharSequenceTextHelper = calleeStr == "ifBlank"
                || calleeStr == "ifEmpty"
                || calleeStr == "chunkedSequence"
                || calleeStr == "firstNotNullOf"
                || calleeStr == "firstNotNullOfOrNull"
                || calleeStr == "reduceRightIndexed"
                || calleeStr == "reduceRightIndexedOrNull"
                || calleeStr == "reduceRightOrNull"
                || calleeStr == "sumBy"
                || calleeStr == "sumByDouble"
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
                || (isCharSequenceTextHelper && isCharSequenceReceiver)
            {
                if calleeStr == "firstNotNullOf"
                    || calleeStr == "firstNotNullOfOrNull"
                    || calleeStr == "reduceRightIndexed"
                    || calleeStr == "reduceRightIndexedOrNull"
                    || calleeStr == "reduceRightOrNull"
                    || calleeStr == "sumBy"
                    || calleeStr == "sumByDouble"
                {
                    let originalCallBinding = sema.bindings.callBindings[exprID]
                    let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                        chosen
                    } else {
                        nil
                    }
                    let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                        providedArguments: loweredArgIDs,
                        callBinding: originalCallBinding,
                        chosenCallee: originalChosen,
                        spreadFlags: args.map(\.isSpread),
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    ).arguments
                    let transformArg = normalizedOriginalArgs.first ?? loweredArgIDs[0]
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        transformArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let runtimeCallee = switch calleeStr {
                    case "firstNotNullOf": "kk_string_firstNotNullOf"
                    case "firstNotNullOfOrNull": "kk_string_firstNotNullOfOrNull"
                    case "reduceRightIndexed": "kk_string_reduceRightIndexed"
                    case "reduceRightIndexedOrNull": "kk_string_reduceRightIndexedOrNull"
                    case "sumBy": "kk_string_sumBy"
                    case "sumByDouble": "kk_string_sumByDouble"
                    default: "kk_string_reduceRightOrNull"
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID, fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "substring" {
                    let hasEndExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(0)))
                    let endExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: endExpr, value: .intLiteral(0)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_substring"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], endExpr, hasEndExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "windowed" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_windowed_default"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let stringGetThrownExpr: KIRExprID?
                if calleeStr == "get" {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    stringGetThrownExpr = zeroExpr
                } else {
                    stringGetThrownExpr = nil
                }
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeStr {
                case "split":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_split_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_split", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "startsWith":
                    ("kk_string_startsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "endsWith":
                    ("kk_string_endsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "contains":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_contains_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_contains_str", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "indexOf":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_indexOf_from", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_indexOf", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "lastIndexOf":
                    ("kk_string_lastIndexOf", [loweredReceiverID, loweredArgIDs[0]])
                case "get":
                    ("kk_string_get", [loweredReceiverID, loweredArgIDs[0], stringGetThrownExpr!])
                case "compareTo":
                    ("kk_string_compareTo_member", [loweredReceiverID, loweredArgIDs[0]])
                case "matches":
                    ("kk_string_matches_regex", [loweredReceiverID, loweredArgIDs[0]])
                case "repeat":
                    ("kk_string_repeat", [loweredReceiverID, loweredArgIDs[0]])
                case "replaceFirstChar":
                    ("kk_string_replaceFirstChar", [loweredReceiverID] + normalizedArgIDs)
                case "mapIndexed":
                    ("kk_string_mapIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "mapNotNull":
                    ("kk_string_mapNotNull", [loweredReceiverID] + normalizedArgIDs)
                case "filterIndexed":
                    ("kk_string_filterIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "filterNot":
                    ("kk_string_filterNot", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfFirst":
                    ("kk_string_indexOfFirst", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfLast":
                    ("kk_string_indexOfLast", [loweredReceiverID] + normalizedArgIDs)
                case "takeWhile":
                    ("kk_string_takeWhile", [loweredReceiverID] + normalizedArgIDs)
                case "dropWhile":
                    ("kk_string_dropWhile", [loweredReceiverID] + normalizedArgIDs)
                case "trim":
                    ("kk_string_trim_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimStart":
                    ("kk_string_trimStart_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimEnd":
                    ("kk_string_trimEnd_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "splitToSequence":
                    ("kk_string_splitToSequence", [loweredReceiverID] + normalizedArgIDs)
                case "find":
                    ("kk_string_find", [loweredReceiverID] + normalizedArgIDs)
                case "findLast":
                    ("kk_string_findLast", [loweredReceiverID] + normalizedArgIDs)
                case "partition":
                    ("kk_string_partition", [loweredReceiverID] + normalizedArgIDs)
                case "ifBlank":
                    ("kk_string_ifBlank", [loweredReceiverID] + normalizedArgIDs)
                case "ifEmpty":
                    ("kk_string_ifEmpty", [loweredReceiverID] + normalizedArgIDs)
                case "take":
                    ("kk_string_take", [loweredReceiverID, loweredArgIDs[0]])
                case "drop":
                    ("kk_string_drop", [loweredReceiverID, loweredArgIDs[0]])
                case "takeLast":
                    ("kk_string_takeLast", [loweredReceiverID, loweredArgIDs[0]])
                case "dropLast":
                    ("kk_string_dropLast", [loweredReceiverID, loweredArgIDs[0]])
                case "chunked":
                    ("kk_string_chunked", [loweredReceiverID, loweredArgIDs[0]])
                case "chunkedSequence":
                    ("kk_string_chunked_sequence", [loweredReceiverID, loweredArgIDs[0]])
                case "encodeToByteArray", "toByteArray":
                    if loweredArgIDs.count == 1 {
                        ("kk_string_encodeToByteArray_charset", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_encodeToByteArray_range", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    }
                case "commonPrefixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonPrefixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonPrefixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "commonSuffixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonSuffixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonSuffixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "padStart":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_padStart", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_padStart_default", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "padEnd":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_padEnd", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_padEnd_default", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "removePrefix":
                    ("kk_string_removePrefix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSuffix":
                    ("kk_string_removeSuffix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSurrounding":
                    ("kk_string_removeSurrounding", [loweredReceiverID, loweredArgIDs[0]])
                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeStr == "repeat"
                        || calleeStr == "replaceFirstChar"
                        || calleeStr == "indexOfFirst"
                        || calleeStr == "indexOfLast"
                        || calleeStr == "partition"
                        || calleeStr == "ifBlank"
                        || calleeStr == "ifEmpty"
                        || calleeStr == "trim"
                        || calleeStr == "trimStart"
                        || calleeStr == "trimEnd"
                        || calleeStr == "take"
                        || calleeStr == "drop"
                        || calleeStr == "takeLast"
                        || calleeStr == "dropLast"
                    // Only `partition` captures the thrown result into a register so the
                    // caller can inspect it.  All other HOFs propagate exceptions through
                    // the standard thrown-channel codegen path (thrownResult == nil),
                    // which emits an early return when the channel is non-zero.  Setting
                    // thrownResult to non-nil for those HOFs would silently swallow the
                    // exception instead of propagating it.
                    let stringHOFThrownResult: KIRExprID? = calleeStr == "partition"
                        ? arena.appendExpr(
                            .temporary(Int32(arena.expressions.count)),
                            type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: stringHOFCanThrow,
                        thrownResult: stringHOFThrownResult
                    ))
                    return result
                }
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, limit) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.intType)
            {
                let falseExpr = arena.appendExpr(.intLiteral(0), type: sema.types.booleanType)
                instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], falseExpr, loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType)
            {
                // limit = 0 means "no limit" for Kotlin's split overload.
                let zeroLimitExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroLimitExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], zeroLimitExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase, limit) — 3-arg overload
        if args.count == 3, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            let thirdArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[2].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType),
               sema.types.isSubtype(thirdArgType, sema.types.intType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg overloads (STDLIB-009, STDLIB-549)
        // KNOWN LIMITATION: The dispatch below matches purely on function name + receiver
        // type (String). User-defined extension functions with the same name (e.g.
        // `fun String.windowed(...)`) will be incorrectly intercepted. A future fix
        // should check the resolved symbol's origin (synthetic vs user-defined) before
        // rewriting to the runtime call.
        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "chunkedSequence",
               normalizedArgIDs.count >= 3
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "indexOf",
               sema.types.isSubtype(firstArgType, sema.types.stringType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_indexOf_from"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "windowed"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowed"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "chunkedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let sizeArgIndex = args.indices.first { index in
                    if let lambdaArgIndex {
                        return index != lambdaArgIndex
                    }
                    return false
                }
                let callArguments: [KIRExprID]
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                if normalizedOriginalArgs.count == 2 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, normalizedOriginalArgs[0], fnPtrExpr, envPtrExpr]
                } else if let lambdaArgIndex,
                          let sizeArgIndex,
                          lambdaArgIndex < loweredArgIDs.count,
                          sizeArgIndex < loweredArgIDs.count
                {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        loweredArgIDs[lambdaArgIndex],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, loweredArgIDs[sizeArgIndex], fnPtrExpr, envPtrExpr]
                } else {
                    callArguments = [loweredReceiverID] + normalizedArgIDs
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: callArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "compareTo"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareToIgnoreCase"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith"
            {
                let runtimeName = calleeStr == "commonPrefixWith"
                    ? "kk_string_commonPrefixWith_ignoreCase"
                    : "kk_string_commonSuffixWith_ignoreCase"
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeName),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "substring" || calleeStr == "padStart" || calleeStr == "padEnd"
            {
                if calleeStr == "padStart" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_padStart"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "padEnd" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_padEnd"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let hasEndExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(1)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_substring"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], hasEndExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg removeSurrounding(prefix, suffix) (STDLIB-TEXT-EDGE-010 / STDLIB-185)
        if args.count == 2, interner.resolve(calleeName) == "removeSurrounding" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeSurrounding_pair"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: windowed(size, step, partialWindows) — STDLIB-549
        // NOTE: Same name-based matching limitation as the 2-arg case above.
        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "windowed"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowed_partial"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "windowedSequence"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowedSequence_partial"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "windowedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                let callArguments: [KIRExprID]?
                if normalizedOriginalArgs.count == 4 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[3],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [
                        loweredReceiverID,
                        normalizedOriginalArgs[0],
                        normalizedOriginalArgs[1],
                        normalizedOriginalArgs[2],
                        fnPtrExpr,
                        envPtrExpr,
                    ]
                } else if let lambdaArgIndex,
                          lambdaArgIndex < loweredArgIDs.count
                {
                    let scalarArgIDs = args.indices
                        .filter { $0 != lambdaArgIndex }
                        .compactMap { index -> KIRExprID? in
                            guard index < loweredArgIDs.count else { return nil }
                            return loweredArgIDs[index]
                        }
                    if scalarArgIDs.count == 3 {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            loweredArgIDs[lambdaArgIndex],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        callArguments = [loweredReceiverID] + scalarArgIDs + [fnPtrExpr, envPtrExpr]
                    } else {
                        callArguments = nil
                    }
                } else {
                    callArguments = nil
                }
                if let callArguments {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_windowedSequence_transform"),
                        arguments: callArguments,
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

 
        // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
        // Skip when first arg is a Regex — handled by the STDLIB-REGEX-094 block below.
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgIsRegex = isRegexLikeType(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType), !firstArgIsRegex {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(startIndex, endIndex) (STDLIB-TEXT-EDGE-008)
        if args.count == 2, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(range) (STDLIB-TEXT-EDGE-008)
        if args.count == 1, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange_range"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceRange(range, replacement) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replace(old, new) (STDLIB-006)
        if args.count == 2, interner.resolve(calleeName) == "replace" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let runtimeCallee = if isRegexLikeType(
                    sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                    sema: sema,
                    interner: interner
                ) {
                    "kk_string_replace_regex"
                } else {
                    "kk_string_replace"
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceFirst(regex, replacement) (STDLIB-REGEX-094)
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               isRegexLikeType(
                   sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                   sema: sema,
                   interner: interner
               ) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst_regex"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Sequence joinTo (STDLIB-SEQ-FN-052): buffer plus separator/prefix/postfix defaults.
        if (1 ... 4).contains(args.count), interner.resolve(calleeName) == "joinTo" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let stringType = sema.types.stringType
                let paramNames = ["buffer", "separator", "prefix", "postfix"]
                let defaults = [nil, ", ", "", ""]
                var resolved: [KIRExprID?] = [nil, nil, nil, nil]
                for (argIdx, arg) in args.enumerated() {
                    if let label = arg.label,
                       let paramIdx = paramNames.firstIndex(of: interner.resolve(label))
                    {
                        resolved[paramIdx] = loweredArgIDs[argIdx]
                    } else if let slot = resolved.firstIndex(where: { $0 == nil }), slot <= argIdx {
                        resolved[slot] = loweredArgIDs[argIdx]
                    } else {
                        resolved[argIdx] = loweredArgIDs[argIdx]
                    }
                }
                if let destinationArg = resolved[0] {
                    var joinArgs: [KIRExprID] = [destinationArg]
                    for paramIndex in 1 ..< 4 {
                        if let existing = resolved[paramIndex] {
                            joinArgs.append(existing)
                        } else if let defaultValue = defaults[paramIndex] {
                            let interned = interner.intern(defaultValue)
                            let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                            instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
                            joinArgs.append(exprID)
                        }
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_joinTo"),
                        arguments: [loweredReceiverID] + joinArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Sequence joinToString (STDLIB-275): 0-3 args, non-HOF, non-throwing
        if args.count <= 3, interner.resolve(calleeName) == "joinToString" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let stringType = sema.types.stringType
                let paramNames = ["separator", "prefix", "postfix"]
                let defaults = [", ", "", ""]
                // Build a 3-element array mapping each parameter to its lowered arg or a default
                var resolved: [KIRExprID?] = [nil, nil, nil]
                for (argIdx, arg) in args.enumerated() {
                    if let label = arg.label,
                       let paramIdx = paramNames.firstIndex(of: interner.resolve(label))
                    {
                        resolved[paramIdx] = loweredArgIDs[argIdx]
                    } else {
                        // Positional argument: fill first unresolved slot
                        if let slot = resolved.firstIndex(where: { $0 == nil }), slot <= argIdx {
                            resolved[slot] = loweredArgIDs[argIdx]
                        } else {
                            resolved[argIdx] = loweredArgIDs[argIdx]
                        }
                    }
                }
                var joinArgs: [KIRExprID] = []
                for paramIndex in 0 ..< 3 {
                    if let existing = resolved[paramIndex] {
                        joinArgs.append(existing)
                    } else {
                        let interned = interner.intern(defaults[paramIndex])
                        let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                        instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
                        joinArgs.append(exprID)
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_joinToString"),
                    arguments: [loweredReceiverID] + joinArgs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1,
           calleeName == interner.intern("plusElement") || calleeName == interner.intern("minusElement")
        {
            let chosenLinkName = chosenBase64Callee.flatMap { sema.symbols.externalLinkName(for: $0) }
            let returnsList = boundType.map { resultType in
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(resultType)),
                      let resultSymbol = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return interner.resolve(resultSymbol.name) == "List"
            } ?? false
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let receiverIsIterable = {
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ]
            }()
            let runtimeCallee = calleeName == interner.intern("plusElement")
                ? "kk_list_plus_element"
                : "kk_list_minus_element"
            if chosenLinkName == runtimeCallee || returnsList || receiverIsIterable {
                instructions.append(.call(
                    symbol: chosenBase64Callee,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "get" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "contains" {
                    let listExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nil)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_toList"),
                        arguments: [loweredReceiverID],
                        result: listExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_contains"),
                        arguments: [listExpr] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let runtimeCallee: String? = switch calleeStr {
                case "map":
                    "kk_array_map"
                case "filter":
                    "kk_array_filter"
                case "forEach":
                    "kk_array_forEach"
                case "any":
                    "kk_array_any"
                case "all":
                    "kk_array_all"
                case "none":
                    "kk_array_none"
                case "count":
                    "kk_array_count"
                case "fill":
                    "kk_array_fill"
                default:
                    nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_list_partition"
                        || runtimeCallee == "kk_list_zipWithNextTransform"
                    let thrownResult = canThrow
                        ? arena.appendExpr(
                            .temporary(Int32(arena.expressions.count)),
                            type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
                let runtimeCallee: String?
                let mapName = interner.intern("map")
                let filterName = interner.intern("filter")
                let takeName = interner.intern("take")
                let forEachName = interner.intern("forEach")
                let flatMapName = interner.intern("flatMap")
                let flatMapToName = interner.intern("flatMapTo")
                let flatMapIndexedName = interner.intern("flatMapIndexed")
                let dropName = interner.intern("drop")
                let zipName = interner.intern("zip")
                let takeWhileName = interner.intern("takeWhile")
                let takeLastWhileName = interner.intern("takeLastWhile")
                let dropWhileName = interner.intern("dropWhile")
                let sortedByName = interner.intern("sortedBy")
                let sumOfName = interner.intern("sumOf")
                let sumByName = interner.intern("sumBy")
                let sumByDoubleName = interner.intern("sumByDouble")
                let firstNotNullOfName = interner.intern("firstNotNullOf")
                let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
                let associateName = interner.intern("associate")
                let associateByName = interner.intern("associateBy")
                let associateWithName = interner.intern("associateWith")
                let associateToName = interner.intern("associateTo")
                let associateByToName = interner.intern("associateByTo")
                let associateWithToName = interner.intern("associateWithTo")
                let groupByToName = interner.intern("groupByTo")
                let flatMapIndexedToName = interner.intern("flatMapIndexedTo")
                let containsName = interner.intern("contains")
                let indexOfName = interner.intern("indexOf")
                let elementAtName = interner.intern("elementAt")
                let elementAtOrNullName = interner.intern("elementAtOrNull")
                let filterIndexedName = interner.intern("filterIndexed")
                let findLastName = interner.intern("findLast")
                let lastName = interner.intern("last")
                let partitionName = interner.intern("partition")
                let minByOrNullName = interner.intern("minByOrNull")
                let maxByOrNullName = interner.intern("maxByOrNull")
                let minOfName = interner.intern("minOf")
                let minOfOrNullName = interner.intern("minOfOrNull")
                let maxOfName = interner.intern("maxOf")
                let distinctByName = interner.intern("distinctBy")
                if calleeName == mapName {
                    runtimeCallee = "kk_sequence_map"
                } else if calleeName == filterName {
                    runtimeCallee = "kk_sequence_filter"
                } else if calleeName == takeName {
                    runtimeCallee = "kk_sequence_take"
                } else if calleeName == interner.intern("takeLast") {
                    runtimeCallee = "kk_sequence_takeLast"
                } else if calleeName == forEachName {
                    runtimeCallee = "kk_sequence_forEach"
                } else if calleeName == flatMapName {
                    runtimeCallee = "kk_sequence_flatMap"
                } else if calleeName == flatMapToName {
                    runtimeCallee = "kk_sequence_flatMapTo"
                } else if calleeName == flatMapIndexedName {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == dropName {
                    runtimeCallee = "kk_sequence_drop"
                } else if calleeName == zipName {
                    runtimeCallee = "kk_sequence_zip"
                } else if calleeName == takeWhileName {
                    runtimeCallee = "kk_sequence_takeWhile"
                } else if calleeName == takeLastWhileName {
                    runtimeCallee = "kk_sequence_takeLastWhile"
                } else if calleeName == dropWhileName {
                    runtimeCallee = "kk_sequence_dropWhile"
                } else if calleeName == sortedByName {
                    runtimeCallee = "kk_sequence_sortedBy"
                } else if calleeName == distinctByName {
                    runtimeCallee = "kk_sequence_distinctBy"
                } else if calleeName == sumOfName {
                    runtimeCallee = "kk_sequence_sumOf"
                } else if calleeName == sumByName {
                    runtimeCallee = "kk_sequence_sumBy"
                } else if calleeName == sumByDoubleName {
                    runtimeCallee = "kk_sequence_sumByDouble"
                } else if calleeName == firstNotNullOfName {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == firstNotNullOfOrNullName {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == associateName {
                    runtimeCallee = "kk_sequence_associate"
                } else if calleeName == associateByName {
                    runtimeCallee = "kk_sequence_associateBy"
                } else if calleeName == associateWithName {
                    runtimeCallee = "kk_sequence_associateWith"
                } else if calleeName == associateToName {
                    runtimeCallee = "kk_sequence_associateTo"
                } else if calleeName == associateByToName {
                    runtimeCallee = "kk_sequence_associateByTo"
                } else if calleeName == associateWithToName {
                    runtimeCallee = "kk_sequence_associateWithTo"
                } else if calleeName == groupByToName {
                    runtimeCallee = "kk_sequence_groupByTo"
                } else if calleeName == flatMapIndexedToName {
                    runtimeCallee = "kk_sequence_flatMapIndexedTo"
                } else if calleeName == containsName {
                    runtimeCallee = "kk_sequence_contains"
                } else if calleeName == indexOfName {
                    runtimeCallee = "kk_sequence_indexOf"
                } else if calleeName == elementAtName {
                    runtimeCallee = "kk_sequence_elementAt"
                } else if calleeName == elementAtOrNullName {
                    runtimeCallee = "kk_sequence_elementAtOrNull"
                } else if calleeName == filterIndexedName {
                    runtimeCallee = "kk_sequence_filterIndexed"
                } else if calleeName == lastName {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_last" : "kk_sequence_last"
                } else if calleeName == findLastName {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == partitionName {
                    runtimeCallee = "kk_sequence_partition"
                } else if calleeName == interner.intern("maxBy") {
                    runtimeCallee = "kk_sequence_maxBy"
                } else if calleeName == minByOrNullName {
                    runtimeCallee = "kk_sequence_minByOrNull"
                } else if calleeName == maxByOrNullName {
                    runtimeCallee = "kk_sequence_maxByOrNull"
                } else if calleeName == interner.intern("maxWithOrNull") {
                    runtimeCallee = "kk_sequence_maxWithOrNull"
                } else if calleeName == minOfName {
                    runtimeCallee = "kk_sequence_minOf"
                } else if calleeName == minOfOrNullName {
                    runtimeCallee = "kk_sequence_minOfOrNull"
                } else if calleeName == interner.intern("maxOfOrNull") {
                    runtimeCallee = "kk_sequence_maxOfOrNull"
                } else if calleeName == maxOfName {
                    runtimeCallee = "kk_sequence_maxOf"
                } else if calleeName == interner.intern("max") {
                    runtimeCallee = "kk_sequence_max"
                } else if calleeName == interner.intern("find") {
                    runtimeCallee = "kk_sequence_find"
                } else if calleeName == interner.intern("findLast") {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == interner.intern("intersect") {
                    runtimeCallee = "kk_sequence_intersect"
                } else if calleeName == interner.intern("any") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_any" : "kk_sequence_any"
                } else if calleeName == interner.intern("all") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_all" : "kk_sequence_all"
                } else if calleeName == interner.intern("none") {
                    runtimeCallee = "kk_sequence_none"
                } else if calleeName == interner.intern("mapNotNull") {
                    runtimeCallee = "kk_sequence_mapNotNull"
                } else if calleeName == interner.intern("firstNotNullOf") {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == interner.intern("firstNotNullOfOrNull") {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == interner.intern("randomOrNull") {
                    runtimeCallee = "kk_sequence_randomOrNull"
                } else if calleeName == interner.intern("requireNoNulls") {
                    runtimeCallee = "kk_sequence_requireNoNulls"
                } else if calleeName == interner.intern("reversed") {
                    runtimeCallee = "kk_sequence_reversed"
                } else if calleeName == interner.intern("mapIndexed") {
                    runtimeCallee = "kk_sequence_mapIndexed"
                } else if calleeName == interner.intern("flatMapIndexed") {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == interner.intern("windowed"), args.count == 4 {
                    runtimeCallee = "kk_sequence_windowed_transform"
                } else if calleeName == interner.intern("chunked") {
                    runtimeCallee = args.count == 2
                        ? "kk_sequence_chunked_transform"
                        : "kk_sequence_chunked"
                } else if calleeName == interner.intern("onEach") {
                    runtimeCallee = "kk_sequence_onEach"
                } else if calleeName == interner.intern("onEachIndexed") {
                    runtimeCallee = "kk_sequence_onEachIndexed"
                } else if calleeName == interner.intern("plus") {
                    if let firstArg = args.first {
                        let argType = sema.types.makeNonNullable(
                            sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
                        )
                        runtimeCallee = (sema.bindings.isCollectionExpr(firstArg.expr)
                            || isSequenceLikeType(argType, sema: sema, interner: interner)
                            || isIterableOrCollectionInterfaceType(argType, sema: sema, interner: interner)
                            || isConcreteCollectionLikeType(argType, sema: sema, interner: interner))
                            ? "kk_sequence_plus"
                            : "kk_sequence_plus_element"
                    } else {
                        runtimeCallee = "kk_sequence_plus_element"
                    }
                } else if calleeName == interner.intern("plusElement") {
                    runtimeCallee = "kk_sequence_plus_element"
                } else if calleeName == interner.intern("minus") || calleeName == interner.intern("minusElement") {
                    runtimeCallee = "kk_sequence_minus"
                } else if calleeName == interner.intern("union") {
                    runtimeCallee = "kk_sequence_union"
                } else if calleeName == interner.intern("reduceRight") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback
                        ? "kk_list_reduceRight"
                        : "kk_sequence_reduceRight"
                } else if calleeName == interner.intern("runningReduceIndexed") {
                    runtimeCallee = "kk_sequence_runningReduceIndexed"
                } else if calleeName == interner.intern("shuffled") {
                    switch normalizedArgIDs.count {
                    case 0: runtimeCallee = "kk_sequence_shuffled"
                    case 1: runtimeCallee = "kk_sequence_shuffled_random"
                    default: runtimeCallee = nil
                    }
                } else if calleeName == interner.intern("ifEmpty") {
                    runtimeCallee = "kk_sequence_ifEmpty"
                } else if calleeName == interner.intern("forEachIndexed") {
                    runtimeCallee = "kk_sequence_forEachIndexed"
                } else if calleeName == interner.intern("zipWithNext") {
                    // Overload dispatch: no-arg → kk_sequence_zipWithNext, with transform → kk_sequence_zipWithNextTransform
                    runtimeCallee = normalizedArgIDs.isEmpty ? "kk_sequence_zipWithNext" : "kk_sequence_zipWithNextTransform"
                } else {
                    runtimeCallee = nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_sequence_sortedBy"
                        || runtimeCallee == "kk_sequence_distinctBy"
                        || runtimeCallee == "kk_sequence_sumOf"
                        || runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble"
                        || runtimeCallee == "kk_sequence_takeLastWhile"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_associate"
                        || runtimeCallee == "kk_sequence_associateBy"
                        || runtimeCallee == "kk_sequence_associateTo"
                        || runtimeCallee == "kk_sequence_associateByTo"
                        || runtimeCallee == "kk_sequence_associateWithTo"
                        || runtimeCallee == "kk_sequence_associateWith"
                        || runtimeCallee == "kk_sequence_groupByTo"
                        || runtimeCallee == "kk_sequence_flatMapIndexedTo"
                        || runtimeCallee == "kk_sequence_flatMapTo"
                        || runtimeCallee == "kk_sequence_find"
                        || runtimeCallee == "kk_sequence_findLast"
                        || runtimeCallee == "kk_sequence_takeLast"
                        || runtimeCallee == "kk_sequence_elementAt"
                        || runtimeCallee == "kk_sequence_last"
                        || runtimeCallee == "kk_iterable_last"
                        || runtimeCallee == "kk_sequence_maxBy"
                        || runtimeCallee == "kk_sequence_minByOrNull"
                        || runtimeCallee == "kk_sequence_maxByOrNull"
                        || runtimeCallee == "kk_sequence_maxWithOrNull"
                        || runtimeCallee == "kk_sequence_minOf"
                        || runtimeCallee == "kk_sequence_minOfOrNull"
                        || runtimeCallee == "kk_sequence_maxOfOrNull"
                        || runtimeCallee == "kk_sequence_maxOf"
                        || runtimeCallee == "kk_sequence_max"
                        || runtimeCallee == "kk_sequence_partition"
                        || runtimeCallee == "kk_sequence_any"
                        || runtimeCallee == "kk_iterable_any"
                        || runtimeCallee == "kk_sequence_all"
                        || runtimeCallee == "kk_iterable_all"
                        || runtimeCallee == "kk_sequence_none"
                        || runtimeCallee == "kk_sequence_mapNotNull"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_randomOrNull"
                        || runtimeCallee == "kk_sequence_mapIndexed"
                        || runtimeCallee == "kk_sequence_filterIndexed"
                        || runtimeCallee == "kk_sequence_chunked_transform"
                        || runtimeCallee == "kk_sequence_windowed_transform"
                        || runtimeCallee == "kk_sequence_onEach"
                        || runtimeCallee == "kk_sequence_onEachIndexed"
                        || runtimeCallee == "kk_sequence_reduceRight"
                        || runtimeCallee == "kk_sequence_runningReduceIndexed"
                        || runtimeCallee == "kk_sequence_ifEmpty"
                        || runtimeCallee == "kk_sequence_zipWithNextTransform"
                    var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    if (runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_maxWithOrNull",
                       normalizedArgIDs.count == 2
                    {
                        runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    }
                    if (runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_takeLastWhile"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if (runtimeCallee == "kk_sequence_associate"
                        || runtimeCallee == "kk_sequence_associateBy"
                        || runtimeCallee == "kk_sequence_associateWith"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if (runtimeCallee == "kk_sequence_reduceRight" || runtimeCallee == "kk_list_reduceRight"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if (runtimeCallee == "kk_sequence_associateTo"
                        || runtimeCallee == "kk_sequence_associateByTo"
                        || runtimeCallee == "kk_sequence_associateWithTo"
                        || runtimeCallee == "kk_sequence_groupByTo"
                        || runtimeCallee == "kk_sequence_flatMapIndexedTo"),
                       normalizedArgIDs.count == 2
                    {
                        let firstArg = normalizedArgIDs[0]
                        let secondArg = normalizedArgIDs[1]
                        let lambdaArg: KIRExprID
                        let destinationArg: KIRExprID
                        if args.count >= 2,
                           sema.bindings.isCollectionHOFLambdaExpr(args[0].expr)
                        {
                            lambdaArg = firstArg
                            destinationArg = secondArg
                        } else if args.count >= 2,
                                  sema.bindings.isCollectionHOFLambdaExpr(args[1].expr)
                        {
                            destinationArg = firstArg
                            lambdaArg = secondArg
                        } else if driver.ctx.callableValueInfo(for: firstArg) != nil {
                            lambdaArg = firstArg
                            destinationArg = secondArg
                        } else {
                            destinationArg = firstArg
                            lambdaArg = secondArg
                        }
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            lambdaArg,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, destinationArg, fnPtrExpr, envPtrExpr]
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: args.first?.expr, sema: sema)
                let runtimeCallee: String? = switch calleeStr {
                case "sortedBy":
                    primitiveSelectorKind != nil ? "kk_list_sortedBy_primitive" : "kk_list_sortedBy"
                case "sortedByDescending":
                    primitiveSelectorKind != nil ? "kk_list_sortedByDescending_primitive" : "kk_list_sortedByDescending"
                case "distinctBy":
                    "kk_list_distinctBy"
                case "dropLastWhile":
                    "kk_list_dropLastWhile"
                case "sortedWith":
                    "kk_list_sortedWith"
                case "maxOf":
                    "kk_list_maxOf"
                case "minOf":
                    "kk_list_minOf"
                case "max":
                    "kk_list_max"
                case "min":
                    "kk_list_min"
                case "maxWith":
                    "kk_list_maxWith"
                case "maxWithOrNull":
                    "kk_list_maxWithOrNull"
                case "minWith":
                    "kk_list_minWith"
                case "minWithOrNull":
                    "kk_list_minWithOrNull"
                case "maxOfWith":
                    "kk_list_maxOfWith"
                case "maxOfWithOrNull":
                    "kk_list_maxOfWithOrNull"
                case "minOfWith":
                    "kk_list_minOfWith"
                case "minOfWithOrNull":
                    "kk_list_minOfWithOrNull"
                case "minBy":
                    "kk_list_minBy"
                case "indexOf":
                    "kk_list_indexOf"
                case "lastIndexOf":
                    "kk_list_lastIndexOf"
                case "partition":
                    "kk_list_partition"
                case "zipWithNext":
                    "kk_list_zipWithNextTransform"
                case "getOrNull":
                    "kk_list_getOrNull"
                case "elementAtOrNull":
                    "kk_list_elementAtOrNull"
                case "elementAt":
                    "kk_list_elementAt"
                case "containsAll":
                    "kk_list_containsAll"
                case "intersect":
                    "kk_list_intersect"
                default:
                    nil
                }
                if let runtimeCallee {
                    var callArguments = [loweredReceiverID] + normalizedArgIDs
                    if let primitiveSelectorKind,
                       runtimeCallee == "kk_list_sortedBy_primitive" || runtimeCallee == "kk_list_sortedByDescending_primitive"
                    {
                        let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                        instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                        callArguments.append(kindExpr)
                    }
                    let canThrow = runtimeCallee == "kk_list_elementAt"
                        || runtimeCallee == "kk_list_distinctBy"
                        || runtimeCallee == "kk_list_dropLastWhile"
                        || runtimeCallee == "kk_list_minBy"
                        || runtimeCallee == "kk_list_min"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "find":
                    "kk_regex_find"
                case "findAll":
                    "kk_regex_findAll"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // StringBuilder member calls with 1 arg (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.append {
                    "kk_string_builder_append_obj"
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_obj"
                } else if calleeName == sbNames.deleteCharAt {
                    "kk_string_builder_deleteCharAt"
                } else if calleeName == sbNames.deleteAt {
                    "kk_string_builder_deleteAt"
                } else if calleeName == sbNames.get {
                    "kk_string_builder_get"
                } else if calleeName == sbNames.ensureCapacity {
                    "kk_string_builder_ensureCapacity"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "copyOf"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_copyOf_newSize"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                if interner.resolve(calleeName) == "copyOf" {
                    let fnPtrExpr: KIRExprID
                    let envPtrExpr: KIRExprID
                    if normalizedArgIDs.count >= 3 {
                        fnPtrExpr = normalizedArgIDs[1]
                        envPtrExpr = normalizedArgIDs[2]
                    } else {
                        let split = splitCallableLambdaArgument(
                            normalizedArgIDs[1],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        fnPtrExpr = split.fnPtrExpr
                        envPtrExpr = split.envPtrExpr
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOf_newSize_init"),
                        arguments: [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if interner.resolve(calleeName) == "copyOfRange" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOfRange"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // List.elementAtOrElse(index, defaultValue) — 2 args (STDLIB-214)
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "elementAtOrElse"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_elementAtOrElse"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // StringBuilder 2-arg member calls (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insert {
                    "kk_string_builder_insert_obj"
                } else if calleeName == sbNames.delete {
                    "kk_string_builder_delete_obj"
                } else if calleeName == sbNames.deleteRange {
                    "kk_string_builder_deleteRange"
                } else if calleeName == sbNames.setCharAt {
                    "kk_string_builder_setCharAt"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 3-arg member calls (STDLIB-580 / STDLIB-STR-123)
        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.appendRange {
                    "kk_string_builder_appendRange_obj"
                } else if calleeName == sbNames.replace {
                    "kk_string_builder_replace_obj"
                } else if calleeName == sbNames.setRange {
                    "kk_string_builder_setRange"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 4-arg member calls (STDLIB-TEXT-BUILDER-003)
        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insertRange {
                    "kk_string_builder_insertRange_obj"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        let hasHOFLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false

        // Sequence windowed: 1-3 args (size, step=1, partialWindows=false) — STDLIB-276
        // Lambda-bearing `windowed` calls use the synthetic iterable HOF overload
        // and must not be rewritten to the sequence ABI here.
        if !hasHOFLambdaArg,
           (1...3).contains(args.count),
           calleeName == interner.intern("windowed")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let sizeArg = normalizedArgIDs[0]
                let stepArg: KIRExprID
                if args.count >= 2 {
                    stepArg = normalizedArgIDs[1]
                } else {
                    stepArg = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                    instructions.append(.constValue(result: stepArg, value: .intLiteral(1)))
                }
                let partialArg: KIRExprID
                if args.count >= 3 {
                    partialArg = normalizedArgIDs[2]
                } else {
                    partialArg = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: partialArg, value: .intLiteral(0)))
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_windowed"),
                    arguments: [loweredReceiverID, sizeArg, stepArg, partialArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_array_toList"
                case "toMutableList":
                    "kk_array_toMutableList"
                case "toTypedArray":
                    "kk_array_copyOf"
                case "copyOf":
                    "kk_array_copyOf"
                case "concatToString":
                    "kk_chararray_concatToString"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // String Iterable<Char> — route toList/iterator to specialised runtime (STDLIB-317)
            if isStringIterableType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_string_iterable_toList"
                case "iterator":
                    "kk_string_iterable_iterator"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForTerminalFallback = isSequenceLikeType(
                nonNullReceiverType,
                sema: sema,
                interner: interner
            )
            let useIterableRuntimeForTerminalFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForTerminalFallback || useIterableRuntimeForTerminalFallback {
                let toListID = interner.intern("toList")
                let constrainOnceID = interner.intern("constrainOnce")
                let distinctID = interner.intern("distinct")
                let sortedID = interner.intern("sorted")
                let sortedDescendingID = interner.intern("sortedDescending")
                let filterNotNullID = interner.intern("filterNotNull")
                let requireNoNullsID = interner.intern("requireNoNulls")
                let asIterableID = interner.intern("asIterable")
                let withIndexID = interner.intern("withIndex")
                let firstID = interner.intern("first")
                let firstOrNullID = interner.intern("firstOrNull")
                let lastID = interner.intern("last")
                let lastOrNullID = interner.intern("lastOrNull")
                let countID = interner.intern("count")
                let sumID = interner.intern("sum")
                let averageID = interner.intern("average")
                let toMutableListID = interner.intern("toMutableList")
                let toMutableSetID = interner.intern("toMutableSet")
                let toSortedSetID = interner.intern("toSortedSet")
                let toHashSetID = interner.intern("toHashSet")
                let unzipID = interner.intern("unzip")
                let anyID = interner.intern("any")
                let noneID = interner.intern("none")

                let seqFirstCallee = interner.intern("kk_sequence_first")
                let seqFirstOrNullCallee = interner.intern("kk_sequence_firstOrNull")
                let seqLastCallee = interner.intern("kk_sequence_last")
                let iterableLastCallee = interner.intern("kk_iterable_last")
                let seqLastOrNullCallee = interner.intern("kk_sequence_lastOrNull")
                let seqSingleCallee = interner.intern("kk_sequence_single")
                let seqSingleOrNullCallee = interner.intern("kk_sequence_singleOrNull")
                let seqCountCallee = interner.intern("kk_sequence_count")
                let seqAnyCallee = interner.intern("kk_sequence_any")
                let iterableAnyCallee = interner.intern("kk_iterable_any")
                let seqNoneCallee = interner.intern("kk_sequence_none")
                let seqToListCallee = interner.intern("kk_sequence_to_list")

                let runtimeCallee: InternedString? = switch calleeName {
                case toListID:
                    seqToListCallee
                case constrainOnceID:
                    interner.intern("kk_sequence_constrainOnce")
                case distinctID:
                    interner.intern("kk_sequence_distinct")
                case sortedID:
                    interner.intern("kk_sequence_sorted")
                case sortedDescendingID:
                    interner.intern("kk_sequence_sortedDescending")
                case interner.intern("shuffled") where args.isEmpty:
                    interner.intern("kk_sequence_shuffled")
                case filterNotNullID:
                    interner.intern("kk_sequence_filterNotNull")
                case requireNoNullsID:
                    interner.intern("kk_sequence_requireNoNulls")
                case asIterableID:
                    interner.intern("kk_sequence_asIterable")
                case withIndexID:
                    interner.intern("kk_sequence_withIndex")
                case firstID:
                    seqFirstCallee
                case firstOrNullID:
                    seqFirstOrNullCallee
                case lastID:
                    useIterableRuntimeForTerminalFallback ? iterableLastCallee : seqLastCallee
                case lastOrNullID:
                    seqLastOrNullCallee
                case interner.intern("single"):
                    seqSingleCallee
                case interner.intern("singleOrNull"):
                    seqSingleOrNullCallee
                case countID:
                    seqCountCallee
                case sumID:
                    interner.intern("kk_sequence_sum")
                case averageID:
                    interner.intern("kk_sequence_average")
                case toMutableListID:
                    toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                        chosenCallee: sema.bindings.callBindings[exprID]?.chosenCallee,
                        useIterableFallback: useIterableRuntimeForTerminalFallback,
                        sema: sema,
                        interner: interner
                    )
                case toMutableSetID:
                    interner.intern(useIterableRuntimeForTerminalFallback
                        ? "kk_iterable_toMutableSet"
                        : "kk_sequence_toMutableSet")
                case toSortedSetID:
                    interner.intern("kk_sequence_toSortedSet")
                case toHashSetID:
                    interner.intern("kk_sequence_toHashSet")
                case unzipID:
                    interner.intern("kk_sequence_unzip")
                case anyID:
                    useIterableRuntimeForTerminalFallback ? iterableAnyCallee : seqAnyCallee
                case noneID:
                    seqNoneCallee
                default:
                    nil
                }
                if let runtimeCallee {
                    // any()/none() with no predicate: pass fnPtr=0, closure=0 sentinel
                    if runtimeCallee == seqAnyCallee || runtimeCallee == iterableAnyCallee || runtimeCallee == seqNoneCallee {
                        let zeroExpr = arena.appendExpr(.intLiteral(0), type: nil)
                        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        instructions.append(.call(
                            symbol: nil,
                            callee: runtimeCallee,
                            arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    let canThrow = runtimeCallee == seqFirstCallee
                        || runtimeCallee == seqFirstOrNullCallee
                        || runtimeCallee == seqLastCallee
                        || runtimeCallee == iterableLastCallee
                        || runtimeCallee == seqLastOrNullCallee
                        || runtimeCallee == seqCountCallee
                        || runtimeCallee == seqToListCallee
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "pattern"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_regex_pattern"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // StringBuilder 0-arg member calls and properties (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.toString {
                    "kk_string_builder_toString"
                } else if calleeName == sbNames.clear {
                    "kk_string_builder_clear"
                } else if calleeName == sbNames.reverse {
                    "kk_string_builder_reverse"
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_noarg_obj"
                } else if calleeName == sbNames.length {
                    "kk_string_builder_length_prop"
                } else if calleeName == sbNames.capacity {
                    "kk_string_builder_capacity"
                } else if calleeName == sbNames.trimToSize {
                    "kk_string_builder_trimToSize"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: format(vararg args) (STDLIB-006)
        if interner.resolve(calleeName) == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_format"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                func boxedFormatArgument(_ argExpr: ExprID, loweredArgID: KIRExprID) -> KIRExprID {
                    let argType = sema.bindings.exprTypes[argExpr] ?? sema.types.anyType
                    let nonNullArgType = sema.types.makeNonNullable(argType)
                    let boxCallee: String? = switch sema.types.kind(of: nonNullArgType) {
                    case .primitive(.int, _), .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
                        "kk_box_int"
                    case .primitive(.boolean, _):
                        "kk_box_bool"
                    case .primitive(.long, _), .primitive(.ulong, _):
                        "kk_box_long"
                    case .primitive(.float, _):
                        "kk_box_float"
                    case .primitive(.double, _):
                        "kk_box_double"
                    case .primitive(.char, _):
                        "kk_box_char"
                    default:
                        nil
                    }

                    let boxedArg = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                    if let boxCallee {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern(boxCallee),
                            arguments: [loweredArgID],
                            result: boxedArg,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    } else {
                        instructions.append(.copy(from: loweredArgID, to: boxedArg))
                    }
                    return boxedArg
                }

                let boxedArgIDs = zip(args, loweredArgIDs).map { arg, loweredArgID in
                    boxedFormatArgument(arg.expr, loweredArgID: loweredArgID)
                }

                let packedArgs: KIRExprID
                if boxedArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = boxedArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(boxedArgIDs.indices),
                        providedArguments: boxedArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_format"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // StringBuilder: append(vararg value: String? / Any?) (STDLIB-TEXT-EDGE-012)
        if interner.resolve(calleeName) == "append",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_builder_append_vararg_obj"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let packedArgs: KIRExprID
                if loweredArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = loweredArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(loweredArgIDs.indices),
                        providedArguments: loweredArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_builder_append_vararg_obj"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)

        // Extract qualified super type information for super<Interface> calls
        var qualifiedSuperType: SymbolID? = nil
        if isSuperCall, case let .superRef(interfaceQualifier, _) = ast.arena.expr(receiverExpr) {
            if let qualifier = interfaceQualifier {
                // Find the interface symbol that matches the qualifier
                if let currentReceiverType = sema.bindings.exprTypes[receiverExpr],
                   case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(currentReceiverType)) {
                    let classSymbol = classType.classSymbol
                    let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let qualifierStr = interner.resolve(qualifier)
                    for superID in directSupertypes {
                        guard let superSym = sema.symbols.symbol(superID) else { continue }
                        if superSym.kind == SymbolKind.interface && interner.resolve(superSym.name) == qualifierStr {
                            qualifiedSuperType = superID
                            break
                        }
                    }
                }
            }
        }

        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        if qualifiedSuperType == nil,
           isSuperCall,
           case let .superRef(interfaceQualifier?, _) = ast.arena.expr(receiverExpr),
           let chosenCallee = callBinding?.chosenCallee,
           chosenCallee != .invalid,
           let ownerSymbol = sema.symbols.parentSymbol(for: chosenCallee),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .interface,
           interner.resolve(ownerInfo.name) == interner.resolve(interfaceQualifier)
        {
            qualifiedSuperType = ownerSymbol
        }
        let chosen: SymbolID? = if let chosenCallee = callBinding?.chosenCallee, chosenCallee != .invalid {
            chosenCallee
        } else {
            SymbolID?.none
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: normalizedArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        var finalArguments = normalized.arguments
        appendReceiverToMemberArguments(
            loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            chosenCallee: chosen,
            prependReceiverForUnresolvedCollectionCall: prependReceiverForUnresolvedCollectionCall,
            sema: sema,
            interner: interner,
            arguments: &finalArguments
        )
        emitMemberCallInstruction(
            normalized: normalized,
            callBinding: callBinding,
            chosenCallee: chosen,
            calleeName: calleeName,
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: loweredReceiverID),
            result: result,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: finalArguments,
            sourceArgExprs: args.map(\.expr),
            sourceArgLabels: args.map(\.label)
        )
        return result
    }
}
