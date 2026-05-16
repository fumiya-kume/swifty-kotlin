// swiftlint:disable file_length function_body_length cyclomatic_complexity
import Foundation

extension CallTypeChecker {
    func inferRegularMemberCallWithoutCandidates(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isNullLiteralReceiver: Bool,
        isFlowReceiver: Bool,
        flowElementType: TypeID,
        hasLeadingLocaleArgument: Bool,
        invisibleCandidates: [SemanticSymbol],
        locals: inout LocalBindings
    ) -> TypeID {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if isClassNameReceiver,
           args.isEmpty,
           let classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: classNameReceiverNominalSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }
        if args.isEmpty,
           interner.resolve(calleeName) == "length"
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                let resultType = sema.types.intType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        if args.isEmpty,
           interner.resolve(calleeName) == "code"
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == sema.types.charType {
                let resultType = sema.types.intType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        if args.isEmpty {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == sema.types.charType {
                let calleeStr = interner.resolve(calleeName)
                if let member = syntheticCharMemberSpec(named: calleeStr) {
                    let resultType = member.returnKind.typeID(
                        in: sema.types,
                        symbols: sema.symbols,
                        interner: interner
                    )
                    let kotlinTextFQName = [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]
                    if let chosen = sema.symbols.lookupAll(fqName: kotlinTextFQName).first(where: { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    }) {
                        _ = bindCallAndResolveReturnType(
                            id,
                            chosen: chosen,
                            resolved: ResolvedCall(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [:],
                                parameterMapping: [:],
                                diagnostic: nil
                            ),
                            sema: sema
                        )
                    }
                    switch calleeStr {
                    case "toList", "toCharArray", "lines", "lineSequence", "toByteArray", "encodeToByteArray":
                        sema.bindings.markCollectionExpr(id)
                    default:
                        break
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int) — 1-arg overload
        if args.count == 1, interner.resolve(calleeName) == "digitToInt" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == sema.types.charType {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                let intType = sema.types.intType
                let finalType = safeCall ? sema.types.makeNullable(intType) : intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // Boolean.not() / Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
        do {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.booleanType) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "not", args.isEmpty {
                    let resultType = sema.types.booleanType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if calleeStr == "and" || calleeStr == "or" || calleeStr == "xor", args.count == 1 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                    let resultType = sema.types.booleanType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // STDLIB-574 / STDLIB-TEXT-EDGE-006: ByteArray.decodeToString overloads.
        do {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
            if let baSymbol = sema.symbols.lookup(fqName: byteArrayFQName),
               case let .classType(ct) = sema.types.kind(of: receiverTypeForCheck),
               ct.classSymbol == baSymbol
            {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "decodeToString", args.count <= 3 {
                    let resultType = sema.types.stringType
                    let charsetExpectedType: TypeID? = {
                        let charsetFQName: [InternedString] = [
                            interner.intern("kotlin"),
                            interner.intern("text"),
                            interner.intern("Charset"),
                        ]
                        guard let charsetSym = sema.symbols.lookup(fqName: charsetFQName) else { return nil }
                        return sema.types.make(.classType(ClassType(
                            classSymbol: charsetSym,
                            args: [],
                            nullability: .nonNull
                        )))
                    }()
                    func isCharsetType(_ type: TypeID) -> Bool {
                        guard let charsetExpectedType else { return false }
                        return sema.types.isSubtype(type, charsetExpectedType)
                    }
                    func receiverMatches(_ signature: FunctionSignature) -> Bool {
                        guard let receiverType = signature.receiverType else { return false }
                        return receiverType == receiverTypeForCheck
                            || sema.types.isSubtype(receiverTypeForCheck, receiverType)
                    }
                    func parameterShapeMatches(_ signature: FunctionSignature) -> Bool {
                        let params = signature.parameterTypes
                        guard receiverMatches(signature), params.count == args.count else { return false }
                        switch args.count {
                        case 0:
                            return true
                        case 1:
                            return params.first.map(isCharsetType) ?? false
                        case 2:
                            return params == [sema.types.intType, sema.types.intType]
                        case 3:
                            return params == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                        default:
                            return false
                        }
                    }
                    // Try to bind to the synthetic extension function symbol.
                    let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
                    let decodeToStringFQName = kotlinTextPkg + [interner.intern("decodeToString")]
                    let candidates = sema.symbols.lookupAll(fqName: decodeToStringFQName)
                    if let chosen = candidates.first(where: { candidate in
                        guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                        return parameterShapeMatches(sig)
                    }) {
                        _ = bindCallAndResolveReturnType(
                            id,
                            chosen: chosen,
                            resolved: ResolvedCall(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [:],
                                parameterMapping: [:],
                                diagnostic: nil
                            ),
                            sema: sema
                        )
                    }
                    // Infer arguments with overload-specific expected types.
                    if args.count == 1 {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: charsetExpectedType)
                    } else if args.count >= 2 {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                        if args.count == 3 {
                            _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                        }
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // STDLIB-HEX-001: HexFormat extension methods with default format parameter.
        do {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let isSupportedHexReceiver =
                (calleeStr == "toHexString" && (receiverTypeForCheck == sema.types.intType || receiverTypeForCheck == sema.types.longType))
                    || (calleeStr == "hexToInt" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToShort" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToUByte" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToUShort" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToUByteArray" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToUInt" && receiverTypeForCheck == sema.types.stringType)
                    || (calleeStr == "hexToULong" && receiverTypeForCheck == sema.types.stringType)
            if isSupportedHexReceiver, args.count <= 1 {
                let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
                let functionFQName = kotlinTextPkg + [calleeName]
                let hexFormatFQName = kotlinTextPkg + [interner.intern("HexFormat")]
                let hexFormatType: TypeID? = {
                    guard let hexFormatSymbol = sema.symbols.lookup(fqName: hexFormatFQName) else { return nil }
                    return sema.types.make(.classType(ClassType(classSymbol: hexFormatSymbol, args: [], nullability: .nonNull)))
                }()
                if let chosen = sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          signature.receiverType == receiverTypeForCheck
                    else {
                        return false
                    }
                    guard args.count <= signature.parameterTypes.count else {
                        return false
                    }
                    if args.count < signature.parameterTypes.count {
                        let remainingDefaults = signature.valueParameterHasDefaultValues.dropFirst(args.count)
                        guard remainingDefaults.allSatisfy({ $0 }) else {
                            return false
                        }
                    }
                    if args.count == 1,
                       let expectedType = hexFormatType,
                       signature.parameterTypes.first != expectedType
                    {
                        return false
                    }
                    return true
                }) {
                    if args.count == 1, let expectedType = hexFormatType {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                    }
                    driver.helpers.checkOptIn(
                        for: chosen,
                        ctx: ctx,
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: args.count == 1 ? [0: 0] : [:],
                            diagnostic: nil
                        ),
                        sema: sema
                    )
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: nullable-receiver 0-arg methods (NULL-002)
        // isNullOrEmpty/isNullOrBlank accept String? receiver directly (no safe-call needed).
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if !isNullLiteralReceiver,
               calleeStr == "isNullOrEmpty",
               isNullableCollectionIsNullOrEmptyReceiver(lookupReceiverType, sema: sema, interner: interner)
            {
                let resultType = sema.types.booleanType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            if !isNullLiteralReceiver,
               calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
            {
                // Strip nullability so that String? and String both match.
                let baseType = sema.types.makeNonNullable(lookupReceiverType)
                if sema.types.isSubtype(baseType, sema.types.stringType) {
                    let resultType = sema.types.booleanType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
        }
        // String stdlib: 0-arg methods (STDLIB-006)
        let listCharType = makeSyntheticListType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: sema.types.make(.primitive(.char, .nonNull))
        )
        let charArrayType = makeSyntheticNominalType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            fqName: [interner.intern("kotlin"), interner.intern("CharArray")]
        )
        if args.isEmpty {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "trim":
                    sema.types.stringType
                case "trimIndent", "trimMargin":
                    sema.types.stringType
                case "lowercase", "uppercase":
                    sema.types.stringType
                case "toInt":
                    sema.types.intType
                case "toIntOrNull":
                    sema.types.make(.primitive(.int, .nullable))
                case "toDouble":
                    sema.types.make(.primitive(.double, .nonNull))
                case "toDoubleOrNull":
                    sema.types.make(.primitive(.double, .nullable))
                case "toBigDecimal":
                    makeSyntheticNominalType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        fqName: [interner.intern("java"), interner.intern("math"), interner.intern("BigDecimal")]
                    )
                case "toBigInteger":
                    makeSyntheticNominalType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        fqName: [interner.intern("java"), interner.intern("math"), interner.intern("BigInteger")]
                    )
                case "reversed", "trimStart", "trimEnd":
                    sema.types.stringType
                case "prependIndent", "replaceIndent", "replaceIndentByMargin":
                    sema.types.stringType
                case "toList":
                    listCharType
                case "toCharArray":
                    charArrayType
                case "toBoolean", "toBooleanStrict":
                    sema.types.make(.primitive(.boolean, .nonNull))
                case "toBooleanStrictOrNull":
                    sema.types.make(.primitive(.boolean, .nullable))
                case "toShort", "toByte":
                    sema.types.intType
                case "toShortOrNull", "toByteOrNull":
                    sema.types.make(.primitive(.int, .nullable))
                case "isEmpty", "isNotEmpty", "isBlank", "isNotBlank":
                    sema.types.make(.primitive(.boolean, .nonNull))
                case "first", "last", "single":
                    sema.types.make(.primitive(.char, .nonNull))
                case "firstOrNull", "lastOrNull", "singleOrNull":
                    sema.types.make(.primitive(.char, .nullable))
                case "lines":
                    makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.stringType
                    )
                case "lineSequence":
                    makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.stringType
                    )
                case "asSequence":
                    makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.make(.primitive(.char, .nonNull))
                    )
                case "toByteArray", "encodeToByteArray":
                    makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.intType
                    )
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // CharSequence stdlib: removePrefix / removeSuffix / removeSurrounding (STDLIB-185)
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let calleeStr = interner.resolve(calleeName)
            if ["removePrefix", "removeSuffix", "removeSurrounding"].contains(calleeStr),
               isSyntheticStringLikeType(receiverTypeForCheck, sema: sema),
               isSyntheticStringLikeType(arg0Type, sema: sema)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.stringType)
            {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "startsWith", "endsWith", "contains":
                    sema.types.make(.primitive(.boolean, .nonNull))
                case "split":
                    sema.types.anyType
                case "indexOf", "lastIndexOf", "compareTo":
                    sema.types.make(.primitive(.int, .nonNull))
                case "substringBefore", "substringAfter", "substringBeforeLast", "substringAfterLast":
                    sema.types.stringType
                case "prependIndent", "replaceIndent", "replaceIndentByMargin":
                    sema.types.stringType
                case "commonPrefixWith", "commonSuffixWith":
                    sema.types.stringType
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               isJavaUtilLocaleType(arg0Type, sema: sema, interner: interner)
            {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "lowercase", "uppercase":
                    sema.types.stringType
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "normalize":
                    sema.types.stringType
                case "isNormalized":
                    sema.types.booleanType
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // STDLIB-581: String.toByteArray(charset: Charset)
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            // Only match when the argument is NOT a String or Int to avoid
            // shadowing other toByteArray overloads (e.g. toByteArray(Int)).
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               interner.resolve(calleeName) == "toByteArray",
               !sema.types.isSubtype(arg0Type, sema.types.stringType),
               !sema.types.isSubtype(arg0Type, sema.types.intType)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    sema.bindings.markCollectionExpr(id)
                    return boundType
                }
                let resultType = makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: sema.types.intType
                )
                sema.bindings.markCollectionExpr(id)
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // CharSequence stdlib: 2-arg removeSurrounding(prefix, suffix) (STDLIB-185)
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            if isSyntheticStringLikeType(receiverTypeForCheck, sema: sema),
               isSyntheticStringLikeType(arg0Type, sema: sema),
               isSyntheticStringLikeType(arg1Type, sema: sema),
               interner.resolve(calleeName) == "removeSurrounding"
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: 2-arg commonPrefixWith/commonSuffixWith(other, ignoreCase) (STDLIB-575/576)
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            let boolType = sema.types.make(.primitive(.boolean, .nonNull))
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.stringType),
               sema.types.isSubtype(arg1Type, boolType)
            {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith" {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String.replaceIndentByMargin(newIndent, marginPrefix)
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.stringType),
               sema.types.isSubtype(arg1Type, sema.types.stringType),
               interner.resolve(calleeName) == "replaceIndentByMargin"
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.intType),
               sema.types.isSubtype(arg1Type, sema.types.intType)
            {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "encodeToByteArray" || calleeStr == "toByteArray" {
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.intType
                    )
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.intType)
            {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "repeat", "drop", "take", "takeLast", "dropLast",
                     "padStart", "padEnd":
                    sema.types.stringType
                case "toInt":
                    sema.types.intType
                case "toUByteOrNull":
                    sema.types.makeNullable(sema.types.ubyteType)
                case "toUShortOrNull":
                    sema.types.makeNullable(sema.types.ushortType)
                case "toUIntOrNull":
                    sema.types.makeNullable(sema.types.uintType)
                case "toULongOrNull":
                    sema.types.makeNullable(sema.types.ulongType)
                case "get":
                    sema.types.make(.primitive(.char, .nonNull))
                case "encodeToByteArray", "toByteArray":
                    makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.intType
                    )
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    switch calleeStr {
                    case "encodeToByteArray", "toByteArray":
                        sema.bindings.markCollectionExpr(id)
                    default:
                        break
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: 1-arg substring overload (STDLIB-009)
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let startType = sema.types.makeNonNullable(argTypes[0])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(startType, sema.types.intType)
            {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "substring" {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: equals(other: String?) / equals(other, ignoreCase) (STDLIB-192)
        if interner.resolve(calleeName) == "equals" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let nullableStringType = sema.types.make(.primitive(.string, .nullable))
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if args.count == 1,
                   sema.types.isSubtype(argTypes[0], nullableStringType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if args.count == 2,
                   sema.types.isSubtype(argTypes[0], nullableStringType),
                   sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: 2-arg compareTo(String, Boolean) (STDLIB-141)
        if args.count == 2, interner.resolve(calleeName) == "compareTo" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                let finalType = safeCall
                    ? sema.types.makeNullable(sema.types.intType)
                    : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: 2-arg commonPrefixWith/commonSuffixWith(other, ignoreCase) (STDLIB-575/576)
        if args.count == 2 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let oldType = sema.types.makeNonNullable(argTypes[0])
            let newType = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(oldType, sema.types.stringType),
               sema.types.isSubtype(newType, sema.types.stringType)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: replaceRange(range, replacement) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceRange" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rangeType = sema.types.makeNonNullable(argTypes[0])
            let replacementType = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(rangeType, sema.types.intType),
               sema.types.isSubtype(replacementType, sema.types.stringType)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: removeRange(startIndex, endIndex) (STDLIB-TEXT-EDGE-008)
        if args.count == 2, interner.resolve(calleeName) == "removeRange" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let startType = sema.types.makeNonNullable(argTypes[0])
            let endType = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(startType, sema.types.intType),
               sema.types.isSubtype(endType, sema.types.intType)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: removeRange(range) (STDLIB-TEXT-EDGE-008)
        if args.count == 1, interner.resolve(calleeName) == "removeRange" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rangeType = sema.types.makeNonNullable(argTypes[0])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(rangeType, sema.types.intType)
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        let stringHOFReceiverType = safeCall
            ? sema.types.makeNonNullable(lookupReceiverType)
            : lookupReceiverType
        if let boundType = tryBindStringChunkedSequenceTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }
        if let boundType = tryBindStringWindowedSequenceTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }
        // String stdlib: HOF filter/map/count/any/all/none (STDLIB-189)
        if args.count == 2, interner.resolve(calleeName) == "chunkedSequence" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if let result = tryInferStringChunkedSequenceTransform(
                id,
                calleeName: calleeName,
                receiverType: receiverTypeForCheck,
                args: args,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs,
                safeCall: safeCall
            ) {
                return result
            }
        }
        if args.count == 1 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let isStringHOFReceiver = sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType)
                || ((calleeStr == "ifBlank" || calleeStr == "ifEmpty" || calleeStr == "zipWithNext" || calleeStr == "sumBy" || calleeStr == "sumByDouble")
                    && isSyntheticStringLikeType(receiverTypeForCheck, sema: sema))
            if isStringHOFReceiver,
               [
                   "filter", "map", "count", "any", "all", "none",
                   "indexOfFirst", "indexOfLast",
                   "mapIndexed", "mapNotNull", "filterIndexed", "filterNot",
                   "takeWhile", "dropWhile", "find", "findLast", "splitToSequence",
                   "trim", "trimStart", "trimEnd",
                   "zipWithNext",
                   "partition",
                   "ifBlank",
                   "ifEmpty",
                   "firstNotNullOf",
                   "firstNotNullOfOrNull",
                   "reduceRightIndexed",
                   "reduceRightIndexedOrNull",
                   "reduceRightOrNull",
                   "sumBy",
                   "sumByDouble",
               ].contains(calleeStr)
            {
                let charType = sema.types.make(.primitive(.char, .nonNull))
                let intType = sema.types.intType
                if calleeStr != "splitToSequence" && calleeStr != "zipWithNext" {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let lambdaParamTypes: [TypeID] = switch calleeStr {
                    case "mapIndexed", "filterIndexed":
                        [intType, charType]
                    case "reduceRightIndexed", "reduceRightIndexedOrNull":
                        [intType, charType, charType]
                    case "reduceRightOrNull":
                        [charType, charType]
                    case "zipWithNext":
                        [charType, charType]
                    case "ifBlank", "ifEmpty":
                        []
                    default:
                        [charType]
                    }
                    let lambdaReturnType: TypeID = switch calleeStr {
                    case "map", "mapIndexed":
                        sema.types.anyType
                    case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull":
                        sema.types.nullableAnyType
                    case "reduceRightIndexed", "reduceRightIndexedOrNull":
                        charType
                    case "reduceRightOrNull":
                        charType
                    case "zipWithNext":
                        sema.types.anyType
                    case "ifBlank", "ifEmpty":
                        sema.types.stringType
                    case "sumBy":
                        sema.types.intType
                    case "sumByDouble":
                        sema.types.doubleType
                    default:
                        sema.types.booleanType
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: lambdaParamTypes,
                        returnType: lambdaReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
                if calleeStr == "zipWithNext" {
                    // Re-run inference with the transform overload so the result type
                    // comes from the lambda body rather than the placeholder `Any`.
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType, charType],
                        returnType: explicitTypeArgs.first ?? sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                    if let chosen = sema.symbols.lookupAll(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: calleeName,
                            receiverType: receiverTypeForCheck,
                            sema: sema,
                            interner: interner
                        )
                            && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if calleeStr == "firstNotNullOf" {
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    let lambdaExpectedReturn = explicitTypeArgs.first.map { sema.types.makeNullable($0) }
                        ?? sema.types.nullableAnyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType],
                        returnType: lambdaExpectedReturn,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? sema.types.makeNonNullable(inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema))
                    if let chosen = sema.symbols.lookupAll(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: calleeName,
                            receiverType: receiverTypeForCheck,
                            sema: sema,
                            interner: interner
                        )
                            && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(bodyType) : bodyType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if calleeStr == "firstNotNullOfOrNull" {
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.nullableAnyType)
                        return sema.types.nullableAnyType
                    }
                    let lambdaExpectedReturn = explicitTypeArgs.first.map { sema.types.makeNullable($0) }
                        ?? sema.types.nullableAnyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType],
                        returnType: lambdaExpectedReturn,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? sema.types.makeNonNullable(inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema))
                    if let chosen = sema.symbols.lookupAll(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: calleeName,
                            receiverType: receiverTypeForCheck,
                            sema: sema,
                            interner: interner
                        )
                            && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    let resultType = sema.types.makeNullable(bodyType)
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                let sequenceStringType: TypeID = {
                    let knownNames = KnownCompilerNames(interner: interner)
                    guard let sequenceSymbol = sema.symbols.lookupAll(fqName: knownNames.kotlinSequenceFQName).first else {
                        return sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                bindSyntheticStringMemberDirectlyIfAvailable(
                    id,
                    calleeName: calleeName,
                    argumentCount: args.count,
                    receiverType: receiverTypeForCheck,
                    sema: sema,
                    interner: interner
                )
                let pairStringStringType: TypeID = {
                    let pairFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("Pair"),
                    ]
                    guard let pairSymbol = sema.symbols.lookup(fqName: pairFQName) else {
                        return sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(sema.types.stringType), .out(sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                let resultType: TypeID = switch calleeStr {
                case "filter": sema.types.stringType
                case "map": sema.types.anyType
                case "mapIndexed", "mapNotNull": sema.types.anyType
                case "count": sema.types.intType
                case "indexOfFirst", "indexOfLast": sema.types.intType
                case "any", "all", "none": sema.types.booleanType
                case "filterIndexed", "filterNot", "takeWhile", "dropWhile": sema.types.stringType
                case "find", "findLast": sema.types.make(.primitive(.char, .nullable))
                case "splitToSequence": sequenceStringType
                case "partition": pairStringStringType
                case "ifBlank", "ifEmpty": sema.types.stringType
                case "reduceRightIndexed": charType
                case "reduceRightIndexedOrNull": sema.types.make(.primitive(.char, .nullable))
                case "reduceRightOrNull": sema.types.make(.primitive(.char, .nullable))
                case "sumBy": sema.types.intType
                case "sumByDouble": sema.types.doubleType
                default: sema.types.anyType
                }
                // For "partition", skip the fallback resolver (which may fail due to
                // lambda argType mismatch) and bind the synthetic symbol directly.
                if calleeStr == "partition" {
                    bindSyntheticStringMemberDirectlyIfAvailable(
                        id,
                        calleeName: calleeName,
                        argumentCount: args.count,
                        receiverType: receiverTypeForCheck,
                        sema: sema,
                        interner: interner
                    )
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                switch calleeStr {
                case "map":
                    sema.bindings.markCollectionExpr(id)
                default:
                    break
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: replaceFirstChar(transform) (STDLIB-315)
        if args.count == 1, interner.resolve(calleeName) == "replaceFirstChar" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let charType = sema.types.make(.primitive(.char, .nonNull))
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [charType],
                    returnType: charType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let resolvedArgTypes = zip(args.indices, argTypes).map { index, originalType in
                    sema.bindings.exprTypes[args[index].expr] ?? originalType
                }
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: resolvedArgTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let stringMemberFQName = [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    calleeName,
                ]
                if let chosen = sema.symbols.lookup(fqName: stringMemberFQName) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: 2-arg methods (STDLIB-006)
        if args.count == 2, interner.resolve(calleeName) == "replace" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let oldType = sema.types.makeNonNullable(argTypes[0])
            let newType = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(oldType, sema.types.stringType),
               sema.types.isSubtype(newType, sema.types.stringType)
            {
                let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(arg0Type, sema.types.stringType),
               isJavaUtilLocaleType(arg1Type, sema: sema, interner: interner),
               interner.resolve(calleeName) == "compareTo"
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }
        // String stdlib: 2-arg substring overload (STDLIB-009)
        if args.count == 2 {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let startType = sema.types.makeNonNullable(argTypes[0])
            let arg1Type = sema.types.makeNonNullable(argTypes[1])
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               sema.types.isSubtype(startType, sema.types.intType)
            {
                let calleeStr = interner.resolve(calleeName)
                let resultType: TypeID? = switch calleeStr {
                case "indexOf" where sema.types.isSubtype(arg1Type, sema.types.intType):
                    sema.types.intType
                case "substring" where sema.types.isSubtype(arg1Type, sema.types.intType):
                    sema.types.stringType
                case "padStart" where arg1Type == sema.types.charType:
                    sema.types.stringType
                case "padEnd" where arg1Type == sema.types.charType:
                    sema.types.stringType
                default:
                    nil
                }
                if let resultType {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        // String stdlib: format(vararg args) (STDLIB-006)
        if calleeName == interner.intern("format"), !hasLeadingLocaleArgument {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if let boundType = tryBindSyntheticStringFormatFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
            }
        }
        // For non-empty-arg member calls, try member property/field lookup.
        // This handles callable property syntax (e.g. `receiver.f(...)`).
        // Skip this for class-name receivers — only companion members are
        // accessible via `ClassName.member`, not instance properties.
        if !isClassNameReceiver,
           !args.isEmpty,
           let propResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               receiverType: memberLookupType,
               sema: sema
           )
        {
            // Check visibility before trying callable-style resolution.
            if let propSymbol = sema.symbols.symbol(propResult.symbol),
               !ctx.visibilityChecker.isAccessible(propSymbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol)
            {
                driver.helpers.emitVisibilityError(for: propSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // Property value call with function type (`receiver.f(...)`).
            if let callableType = inferFunctionTypeOrError(from: propResult.type, sema: sema) {
                if let callableResult = inferCallableValueInvocation(
                    id,
                    calleeType: callableType,
                    callableTarget: .localValue(propResult.symbol),
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType
                ) {
                    let finalType = safeCall ? sema.types.makeNullable(callableResult) : callableResult
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // Property value call through `operator fun invoke(...)`.
            let invokeName = interner.intern("invoke")
            let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: propResult.type,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }

            if !invokeCandidates.isEmpty {
                let resolvedArgs = zip(args, argTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: invokeCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: invokeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: propResult.type,
                    ctx: ctx.semaCtx
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    sema.bindings.markInvokeOperatorCall(id)
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        if lookupReceiverType == sema.types.errorType {
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        // Kotlin infix `to` is effectively a universal extension used by
        // destructuring-friendly literals (e.g. `1 to "a"`). Keep a
        // lightweight fallback when no symbol candidate was discovered.
        if !isClassNameReceiver,
           args.count == 1,
           calleeName == knownNames.to
        {
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if let firstInvisible = invisibleCandidates.first {
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        if let fallbackType = tryRegexMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryKFunctionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryStringMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryPathCharsetReadExtensionFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryFileMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryArrayMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryRangeMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        // Flow member access fallback (CORO-003): allow flow chain calls
        // only when receiver provenance is known as Flow.
        if !isClassNameReceiver, isFlowReceiver {
            let memberName = interner.resolve(calleeName)
            let flowMembers: Set = ["map", "filter", "take", "collect", "single", "catch", "retry", "retryWhen"]
            if flowMembers.contains(memberName) {
                let acceptsArity = memberName == "single" ? args.isEmpty : args.count == 1
                if memberName == "single", acceptsArity {
                    let resultType = safeCall ? sema.types.makeNullable(flowElementType) : flowElementType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                if acceptsArity,
                   memberName == "map" || memberName == "filter" || memberName == "collect" ||
                   memberName == "catch" || memberName == "retryWhen"
                {
                    let expectsLambdaTypeConstraint = switch ast.arena.expr(args[0].expr) {
                    case .callableRef:
                        false
                    default:
                        true
                    }
                    let lambdaReturnType: TypeID = switch memberName {
                    case "filter":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "collect":
                        sema.types.unitType
                    case "catch":
                        sema.types.unitType
                    case "retryWhen":
                        sema.types.booleanType
                    default:
                        sema.types.anyType
                    }
                    let lambdaParameterTypes: [TypeID] = switch memberName {
                    case "catch":
                        [sema.types.anyType]
                    case "retryWhen":
                        [sema.types.anyType, sema.types.longType]
                    default:
                        [flowElementType]
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: memberName == "collect",
                        nullability: .nonNull
                    )))
                    if expectsLambdaTypeConstraint {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    }
                }

                if acceptsArity {
                    if memberName == "map" || memberName == "filter" || memberName == "take" ||
                        memberName == "catch" || memberName == "retry" || memberName == "retryWhen"
                    {
                        sema.bindings.markFlowExpr(id)
                        let resultElementType: TypeID = switch memberName {
                        case "map":
                            if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                               let mappedType = sema.bindings.exprType(for: bodyExpr)
                            {
                                mappedType
                            } else {
                                sema.types.anyType
                            }
                        case "filter", "take", "catch", "retry", "retryWhen":
                            flowElementType
                        default:
                            sema.types.anyType
                        }
                        sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
                    }
                    let resultType: TypeID
                    if memberName == "collect" {
                        resultType = sema.types.unitType
                    } else {
                        let resultElement = sema.bindings.flowElementType(forExpr: id) ?? flowElementType
                        resultType = driver.helpers.makeFlowType(
                            elementType: resultElement, sema: sema, interner: interner
                        ) ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        let isCoroutineHandleReceiver = isCoroutineHandleReceiverType(
            lookupReceiverType,
            sema: sema,
            interner: interner
        )
        if !isClassNameReceiver, args.isEmpty, isCoroutineHandleReceiver {
            let memberName = interner.resolve(calleeName)
            switch memberName {
            case "cancel":
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case "join":
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case "await":
                let resultType = sema.types.nullableAnyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case "isActive", "isCompleted", "isCancelled", "isClosedForReceive", "isClosedForSend":
                let resultType = sema.types.booleanType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            default:
                break
            }
        }
        // Builder DSL member functions (STDLIB-002).
        if ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
            let name = interner.resolve(calleeName)
            let isBuilderMember: Bool = switch activeBuilderKind {
            case .buildString:
                (name == "append" && args.count == 1)
                    || (name == "appendLine" && args.count <= 1)
                    || (name == "appendRange" && args.count == 3)
            case .buildList, .buildSet: name == "add" && args.count == 1
            case .buildMap: name == "put" && args.count == 2
            }
            if isBuilderMember {
                _ = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                sema.bindings.markBuilderDSLExpr(id, kind: activeBuilderKind)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }

        // STDLIB-532/533/534, STDLIB-SEQ-011: orEmpty() on nullable receivers
        if interner.resolve(calleeName) == "orEmpty", args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let resultType = sema.types.stringType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            if isListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let resultType = nonNullReceiverType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let resultType = nonNullReceiverType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            let knownNames = KnownCompilerNames(interner: interner)
            if case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
               let symbol = sema.symbols.symbol(classType.classSymbol),
               knownNames.isMapLikeSymbol(symbol)
            {
                let resultType = nonNullReceiverType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // Collection fallback needs to run before the generic overload resolver
        // so synthetic collection members can use their specialized lambda
        // expectations without type-variable noise from the general path.
        if let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindThreadLocalGetOrSetFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindMapGetOrElseFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindMapWithDefaultFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindReadWriteLockReadFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindComparatorMemberFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }

        // Receiver-lambda invocation: `receiver.localVar()` where localVar
        // has a function-with-receiver type matching the receiver.
        // e.g. `sb.action()` where action: StringBuilder.() -> Unit
        if let local = locals[calleeName] {
            let localType = local.type
            if case let .functionType(fnType) = sema.types.kind(of: localType),
               fnType.receiver != nil
            {
                let argTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                _ = argTypes // suppress unused warning
                let resultType = fnType.returnType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                // Mark as callable-value call so KIR emits an indirect call
                // through the closure pointer with the receiver prepended.
                sema.bindings.bindCallableValueCall(
                    id,
                    binding: CallableValueCallBinding(
                        target: .localValue(local.symbol),
                        functionType: localType,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            // Support function values that were represented as a regular
            // function type where the first parameter is the receiver.
            // Example: `val f: StringBuilder.() -> Unit` may be encoded as
            // `(StringBuilder) -> Unit` in some contexts.
            if case let .functionType(fnType) = sema.types.kind(of: localType),
               !fnType.params.isEmpty,
               args.count == fnType.params.count - 1,
               sema.types.isSubtype(
                   sema.types.makeNonNullable(receiverType),
                   fnType.params[0]
               )
            {
                for (index, argument) in args.enumerated() {
                    let expectedArgumentType = fnType.params[index + 1]
                    _ = driver.inferExpr(
                        argument.expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: expectedArgumentType
                    )
                }
                let boundFunctionType = sema.types.make(.functionType(FunctionType(
                    receiver: fnType.params[0],
                    params: Array(fnType.params.dropFirst()),
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                )))
                let resultType = fnType.returnType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindCallableValueCall(
                    id,
                    binding: CallableValueCallBinding(
                        target: .localValue(local.symbol),
                        functionType: boundFunctionType,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
    }
}
