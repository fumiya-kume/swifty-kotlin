// swiftlint:disable function_body_length cyclomatic_complexity
import Foundation

extension CallTypeChecker {
    func tryInferRegularMemberCallPrimitiveSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        argTypes: [TypeID],
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let safeCall = request.safeCall
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if interner.resolve(calleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            if lookupReceiverType == intType || lookupReceiverType == longType || lookupReceiverType == uintType || lookupReceiverType == ulongType || lookupReceiverType == ubyteType || lookupReceiverType == ushortType {
                let resultType = lookupReceiverType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers
        // (e.g. Int.times(Int), Long.plus(Long), UInt.shl(Int)).
        if args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let charType = sema.types.charType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rawRhsType = argTypes[0]
            let isPrimitiveReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType
            let isShiftReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType
            // Helper: whether a type is a small unsigned type (UByte/UShort).
            // In Kotlin stdlib, small unsigned types promote to UInt for most
            // arithmetic (plus/minus/times/div/rem). `mod` returns the RHS type.
            let isSmallUnsigned = { (t: TypeID) -> Bool in t == ubyteType || t == ushortType }
            let isUnsignedInteger = { (t: TypeID) -> Bool in
                t == uintType || t == ulongType || isSmallUnsigned(t)
            }
            let isSignedInteger = { (t: TypeID) -> Bool in
                t == intType || t == longType
            }
            let isFloating = { (t: TypeID) -> Bool in
                t == floatType || t == doubleType
            }
            // Use non-nullable RHS for arithmetic promotion checks
            let rhsType = sema.types.makeNonNullable(rawRhsType)
            switch interner.resolve(calleeName) {
            case "plus":
                let resultType: TypeID? = if receiverForCheck == charType && rawRhsType == intType {
                    charType
                } else if receiverForCheck == doubleType || rhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    // UByte/UShort arithmetic promotes to UInt in Kotlin stdlib
                    uintType
                } else if receiverForCheck == intType || rhsType == intType || receiverForCheck == charType {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "minus":
                let resultType: TypeID? = if receiverForCheck == charType && rawRhsType == charType {
                    intType
                } else if receiverForCheck == charType && rawRhsType == intType {
                    charType
                } else if receiverForCheck == doubleType || rhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    uintType
                } else if receiverForCheck == intType {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "times", "div", "rem":
                // times/div/rem: small unsigned types promote to UInt (Kotlin stdlib)
                let resultType: TypeID? = if receiverForCheck == doubleType || rhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    uintType
                } else if receiverForCheck == intType {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "floorDiv":
                let resultType: TypeID? = if isSignedInteger(receiverForCheck), isSignedInteger(rhsType) {
                    receiverForCheck == longType || rhsType == longType ? longType : intType
                } else if isUnsignedInteger(receiverForCheck), isUnsignedInteger(rhsType) {
                    receiverForCheck == ulongType || rhsType == ulongType ? ulongType : uintType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "mod":
                // mod overloads return the divisor type for integer overloads and
                // use normal Float/Double widening for floating operands.
                let resultType: TypeID? = if isFloating(receiverForCheck), isFloating(rhsType) {
                    receiverForCheck == doubleType || rhsType == doubleType ? doubleType : floatType
                } else if isSignedInteger(receiverForCheck), isSignedInteger(rhsType) {
                    rhsType == longType ? longType : intType
                } else if isUnsignedInteger(receiverForCheck), isUnsignedInteger(rhsType) {
                    rhsType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "and", "or", "xor":
                if isPrimitiveReceiver,
                   rawRhsType == receiverForCheck
                {
                    let resultType = receiverForCheck
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "shl", "shr", "ushr":
                if isShiftReceiver,
                   rawRhsType == intType
                {
                    // shift amount must be Int; receiver can be Int/Long/UInt/ULong
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            default:
                break
            }
        }

        // Stdlib infix function: Any.to(Any) → Pair<LHS, RHS> (FUNC-002)
        if calleeName == knownNames.to,
           args.count == 1
        {
            let rhsType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let resultType = makeSyntheticPairType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                firstType: receiverType,
                secondType: rhsType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // STDLIB-NUM-130 (previous fast-path) removed:
        // isNaN / isInfinite / isFinite / toBits / toRawBits / ulp / nextUp / nextDown
        // are registered as real extension functions with external link names
        // (kk_{double,float}_*) in HeaderHelpers+SyntheticCoercionStubs.swift. Letting
        // them flow through the normal extension-function resolution path carries the
        // link name into codegen; the old early-return bound only the result type, so
        // the linker saw raw "_isNaN"/"_nextUp" symbols.

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceIn(min, max) (STDLIB-150, STDLIB-500)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let ubyteType = sema.types.ubyteType
            let ushortType = sema.types.ushortType
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType
                || receiverForCheck == doubleType || receiverForCheck == floatType
                || receiverForCheck == ubyteType || receiverForCheck == ushortType
                || receiverForCheck == uintType || receiverForCheck == ulongType
            {
                _ = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck) }
                let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Int/Long/UInt/ULong.coerceIn(range) (STDLIB-525)
        if interner.resolve(calleeName) == "coerceIn", args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let supportsRangeCoercion = receiverForCheck == intType || receiverForCheck == longType
                || receiverForCheck == uintType || receiverForCheck == ulongType
            if supportsRangeCoercion {
                let inferredArgType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nominalRangeElementType = nominalRangeElementType(
                    for: inferredArgType,
                    sema: sema,
                    interner: interner
                )
                let isRangeArg = sema.bindings.isRangeExpr(args[0].expr)
                if isRangeArg || nominalRangeElementType == receiverForCheck {
                    if isRangeArg {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck)
                    }
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceAtLeast(min) / coerceAtMost(max) (STDLIB-150, STDLIB-500)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let longType = sema.types.make(.primitive(.long, .nonNull))
                let doubleType = sema.types.make(.primitive(.double, .nonNull))
                let floatType = sema.types.make(.primitive(.float, .nonNull))
                let ubyteType = sema.types.ubyteType
                let ushortType = sema.types.ushortType
                let uintType = sema.types.uintType
                let ulongType = sema.types.ulongType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let isRangeArg = sema.bindings.isRangeExpr(args[0].expr)
                let supportsRangeCoercion = receiverForCheck == intType || receiverForCheck == longType
                    || receiverForCheck == doubleType || receiverForCheck == floatType
                let supportsValueCoercion = supportsRangeCoercion
                    || receiverForCheck == ubyteType || receiverForCheck == ushortType
                    || receiverForCheck == uintType || receiverForCheck == ulongType
                if (!isRangeArg && supportsValueCoercion) || (isRangeArg && supportsRangeCoercion) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck)
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() → Int (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "countOneBits" || calleeStr == "countLeadingZeroBits" || calleeStr == "countTrailingZeroBits" ||
                calleeStr == "highestOneBit" || calleeStr == "lowestOneBit" || calleeStr == "takeHighestOneBit" || calleeStr == "takeLowestOneBit"
            {
                let intType = sema.types.intType
                let longType = sema.types.longType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverForCheck == intType || receiverForCheck == longType {
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int.rotateLeft() / rotateRight() → Int (STDLIB-BIT-007)
        // Long.rotateLeft() / rotateRight() → Long (STDLIB-BIT-007)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                let intType = sema.types.intType
                let longType = sema.types.longType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverForCheck == intType || receiverForCheck == longType {
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Primitive member function: Int/Long.toString() / toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType {
                if args.isEmpty || argTypes[0] == intType {
                    let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // STDLIB-NUM-130: Double/Float extension functions - Direct resolution (moved earlier, removed duplicate)

        let anyFallbackReceiverType = safeCall
            ? sema.types.makeNonNullable(lookupReceiverType)
            : lookupReceiverType
        let allowsAnyFallback: Bool = switch sema.types.kind(of: anyFallbackReceiverType) {
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
            anyFallbackReceiverType == sema.types.anyType || anyFallbackReceiverType == sema.types.nullableAnyType
        }

        // Any.hashCode(): Int (STDLIB-306)
        if interner.resolve(calleeName) == "hashCode", args.isEmpty, allowsAnyFallback {
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Any.toString(): String (STDLIB-306)
        if interner.resolve(calleeName) == "toString", args.isEmpty, allowsAnyFallback {
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Any.equals(other: Any?): Boolean (STDLIB-306)
        if interner.resolve(calleeName) == "equals", args.count == 1, allowsAnyFallback {
            let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toDouble(), toByte(), toShort() (TYPE-005, STDLIB-151)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.ubyteType
            let ushortType = sema.types.ushortType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == sema.types.charType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == sema.types.charType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == longType || receiverForCheck == ulongType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == sema.types.charType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == sema.types.charType)
            case "toFloat": (floatType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == doubleType || receiverForCheck == floatType)
            case "toDouble": (doubleType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType)
            case "toByte", "toShort": (intType, receiverForCheck == intType || receiverForCheck == longType)
            case "toUByte": (sema.types.ubyteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toUShort": (sema.types.ushortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toChar": (sema.types.charType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType)
            default: (sema.types.errorType, false)
            }
            if matches {
                let finalType = safeCall ? sema.types.makeNullable(targetType) : targetType
                driver.helpers.checkBuiltinDeprecation(
                    calleeName: calleeName,
                    receiverType: receiverForCheck,
                    sema: sema,
                    interner: interner,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        return nil
    }
}
