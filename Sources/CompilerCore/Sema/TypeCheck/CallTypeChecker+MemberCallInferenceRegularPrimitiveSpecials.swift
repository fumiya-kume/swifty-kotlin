// swiftlint:disable function_body_length cyclomatic_complexity

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
        if interner.resolve(calleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            if lookupReceiverType == intType || lookupReceiverType == longType || lookupReceiverType == uintType || lookupReceiverType == ulongType || lookupReceiverType == ubyteType || lookupReceiverType == ushortType || lookupReceiverType == byteType || lookupReceiverType == shortType {
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
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let charType = sema.types.charType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rawRhsType = argTypes[0]
            let isPrimitiveReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType
            let isShiftReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType
            // Helper: whether a type is a small unsigned type (UByte/UShort).
            // In Kotlin stdlib, small unsigned types promote to UInt for most
            // arithmetic (plus/minus/times/div/rem). `mod` returns the RHS type.
            let isSmallUnsigned = { (t: TypeID) -> Bool in t == ubyteType || t == ushortType }
            let isUnsignedInteger = { (t: TypeID) -> Bool in
                t == uintType || t == ulongType || isSmallUnsigned(t)
            }
            let isSignedInteger = { (t: TypeID) -> Bool in
                t == intType || t == longType || t == byteType || t == shortType
            }
            let isFloating = { (t: TypeID) -> Bool in
                t == floatType || t == doubleType
            }
            // Use non-nullable RHS for arithmetic promotion checks
            let rhsType = sema.types.makeNonNullable(rawRhsType)
            let isNumericReceiver = isPrimitiveReceiver
                || receiverForCheck == floatType
                || receiverForCheck == doubleType
                || receiverForCheck == charType
            switch interner.resolve(calleeName) {
            case "plus":
                // Collection plus(element) must reach overload resolution instead of
                // being mistaken for primitive arithmetic based only on the RHS type.
                let resultType: TypeID? = if !isNumericReceiver {
                    nil
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
                    // UByte/UShort arithmetic promotes to UInt in Kotlin stdlib
                    uintType
                } else if receiverForCheck == intType || rhsType == intType || receiverForCheck == charType
                           || receiverForCheck == byteType || rhsType == byteType
                           || receiverForCheck == shortType || rhsType == shortType
                {
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
                // Collection minus(element) must reach overload resolution just like plus(element).
                let resultType: TypeID? = if !isNumericReceiver {
                    nil
                } else if receiverForCheck == charType && rawRhsType == charType {
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
                } else if receiverForCheck == intType || receiverForCheck == byteType || receiverForCheck == shortType {
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

        // STDLIB-NUM-130 / KSP-638 / KSP-647: floating-point precision and bit helpers
        // (isNaN / isInfinite / isFinite / toBits / toRawBits) are declared by bundled
        // Kotlin source. Their internal __kk_* bridges are ordinary source declarations,
        // so they must flow through normal extension resolution instead of a primitive
        // name-based fast path. ulp / nextUp / nextDown remain runtime-backed synthetic
        // functions until their respective migrations.

        // Unsigned coercion (UByte/UShort/UInt/ULong) is handled by bundled Kotlin source
        // (RangeCoercion.kt); no primitive fast-path is needed.

        // KSP-642: Int/Long rotateLeft / rotateRight resolve through the bundled Kotlin
        // declarations in `Stdlib/kotlin/Numbers.kt`, so no special inference is needed.

        // Primitive member function: Int/Long/Byte/Short.toString() / toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let stringType = sema.types.stringType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == byteType || receiverForCheck == shortType {
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
        case .stringStruct:
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
            let stringType = sema.types.stringType
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
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == longType || receiverForCheck == ulongType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toFloat": (floatType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == doubleType || receiverForCheck == floatType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toDouble": (doubleType, receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toByte": (byteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toShort": (shortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUByte": (sema.types.ubyteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUShort": (sema.types.ushortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toChar": (sema.types.charType, receiverForCheck == byteType || receiverForCheck == shortType)
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
