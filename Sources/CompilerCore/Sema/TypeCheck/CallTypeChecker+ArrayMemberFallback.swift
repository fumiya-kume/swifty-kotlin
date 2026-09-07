/// Member-call fallback resolution for `Array<T>` and primitive-array
/// receivers (STDLIB-087/088/089).
///
/// Split out from `CallTypeChecker+MemberCallFallbacks.swift`.
extension CallTypeChecker {
    private static let primitiveArraySourceHOFNames: Set<String> = [
        "map", "mapIndexed", "mapNotNull", "flatMap", "forEach",
        "filter", "filterIndexed", "filterNot",
        "reduce", "reduceIndexed", "reduceOrNull", "fold", "foldIndexed",
        "find", "findLast", "first", "firstOrNull", "last", "lastOrNull",
        "any", "all", "none", "count", "joinToString",
        "contentEquals", "contentHashCode", "contentToString",
        "copyOf", "copyOfRange", "copyInto",
    ]

    private static let arraySourceConversionNames: Set<String> = [
        "sliceArray", "reversedArray", "asList", "toTypedArray",
    ]

    /// Finds the exact primitive-array source overload before the default-import
    /// scope fallback can select a same-named Sequence extension. Primitive
    /// arrays are compiler-provided nominal classes, while their bundled HOFs
    /// live in kotlin.collections as top-level extensions.
    func collectPrimitiveArraySourceHOFs(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let memberName = interner.resolve(calleeName)
        guard Self.primitiveArraySourceHOFNames.contains(memberName),
              let receiverClass = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(receiverType), types: sema.types),
              let receiverSymbol = sema.symbols.symbol(receiverClass),
              receiverSymbol.fqName.count == 2,
              receiverSymbol.fqName[0] == interner.intern("kotlin"),
              receiverSymbol.name != interner.intern("Array"),
              KnownCompilerNames(interner: interner).isArrayLikeName(receiverSymbol.name)
        else {
            return []
        }

        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        return sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let signatureClass = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(signatureReceiver), types: sema.types),
                  let signatureSymbol = sema.symbols.symbol(signatureClass)
            else {
                return false
            }
            return signatureSymbol.fqName == receiverSymbol.fqName
        }
    }

    /// Finds the exact bundled source overload for an Array or primitive-array
    /// conversion. These functions are top-level extensions in
    /// kotlin.collections, so member lookup can otherwise select a synthetic
    /// array stub or a same-named generic collection extension first.
    func collectArraySourceConversionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let memberName = interner.resolve(calleeName)
        guard Self.arraySourceConversionNames.contains(memberName),
              let receiverClass = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(receiverType), types: sema.types),
              let receiverSymbol = sema.symbols.symbol(receiverClass),
              receiverSymbol.fqName.count == 2,
              receiverSymbol.fqName[0] == interner.intern("kotlin"),
              KnownCompilerNames(interner: interner).isArrayLikeName(receiverSymbol.name)
        else {
            return []
        }

        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        return sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let signatureClass = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(signatureReceiver), types: sema.types),
                  let signatureSymbol = sema.symbols.symbol(signatureClass)
            else {
                return false
            }
            return signatureSymbol.fqName == receiverSymbol.fqName
        }
    }

    func tryArrayMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard !isClassNameReceiver,
              isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard isSupportedArrayMember(memberName),
              isValidArrayMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        // KSP-687: primitive-array HOFs are bundled Kotlin extensions, not
        // unresolved members. Let ordinary overload resolution select the
        // source declaration so the legacy raw-array bridge cannot intercept
        // the call (especially joinToString(transform)).
        if !collectPrimitiveArraySourceHOFs(
            named: calleeName,
            receiverType: sema.bindings.exprTypes[receiverID] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        if !collectArraySourceConversionCandidates(
            named: calleeName,
            receiverType: sema.bindings.exprTypes[receiverID] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }

        // Extract the actual element type from the Array<T> receiver (TYPE-103).
        let receiverElementType = arrayFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if memberName == "copyOf", args.indices.contains(0) {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.intType
            )
        }
        // The accumulator of `fold`/`foldIndexed` takes the type of the initial
        // value: typing it as `Any` makes a primitive accumulator arrive at the
        // operator lowering as a reference, so `DoubleArray.fold(0.0) { a, b -> a + b }`
        // reinterprets the accumulator's raw word as an Int.
        var accumulatorType: TypeID?
        if (memberName == "fold" || memberName == "foldIndexed"), args.indices.contains(0) {
            accumulatorType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
        }
        if let expectation = arrayMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            accumulatorType: accumulatorType ?? sema.types.anyType,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        // Mark result as collection if it returns a List
        if isArrayMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }

        let resultType = arrayMemberResultType(
            memberName: memberName,
            receiverID: receiverID,
            elementType: receiverElementType,
            accumulatorType: accumulatorType ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func isSupportedArrayMember(_ memberName: String) -> Bool {
        let arrayMembers: Set = [
            "toList", "toMutableList",
            "copyOf", "copyOfRange", "copyInto", "fill",
            "size", "get", "contains", "isEmpty",
            "concatToString",
        ]
        return arrayMembers.contains(memberName)
    }

    private func isValidArrayMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "toList", "toMutableList", "size", "isEmpty", "concatToString":
            argCount == 0
        case "copyOf":
            (0...2).contains(argCount)
        case "fill", "get", "contains":
            argCount == 1
        case "copyOfRange":
            argCount == 2
        case "copyInto":
            (1...4).contains(argCount)
        default:
            true
        }
    }

    private func isArrayMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "toMutableList", "copyOf", "copyOfRange"].contains(memberName)
    }

    private func arrayMemberResultType(
        memberName: String,
        receiverID: ExprID,
        elementType: TypeID,
        accumulatorType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        switch memberName {
        case "size":
            return sema.types.intType
        case "isEmpty", "contains":
            return sema.types.booleanType
        case "forEach", "fill":
            return sema.types.unitType
        case "count":
            return sema.types.intType
        case "concatToString":
            return sema.types.stringType
        case "get":
            return elementType
        case "copyOf", "copyOfRange":
            let receiverType = sema.bindings.exprTypes[receiverID]
                ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
                ?? sema.types.anyType
            return sema.types.makeNonNullable(receiverType)
        case "toList":
            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case "toMutableList":
            if let mutableListSymbol = sema.symbols.lookupByShortName(interner.intern("MutableList")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: mutableListSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        default:
            return sema.types.anyType
        }
    }

    private func arrayMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        accumulatorType: TypeID,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        if memberName == "copyOf", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }
        return nil
    }

    /// Extract the element type from an `Array<T>` receiver.
    /// For generic `Array<T>`, returns `T`; for primitive arrays (IntArray, etc.)
    /// returns the corresponding primitive type.  Falls back to `Any` when the
    /// element type cannot be determined.
    private func arrayFallbackElementType(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let receiverType = sema.bindings.exprTypes[receiverID]
            ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNull, sema: sema) else {
            return sema.types.anyType
        }

        let knownNames = KnownCompilerNames(interner: interner)

        // Generic Array<T>: extract type argument.
        if symbol.name == knownNames.array, let firstArg = classType.args.first {
            return switch firstArg {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
        }

        return primitiveArrayElementType(
            className: symbol.name,
            sema: sema,
            interner: interner
        ) ?? sema.types.anyType
    }

    /// Element type of a primitive array class (`IntArray`, `DoubleArray`, ...),
    /// or `nil` when the class is not a primitive array.
    ///
    /// Primitive arrays carry no type argument, so their element type has to be
    /// recovered from the class name.
    /// Note: Byte/Short map to intType (same as builtinType resolution).
    func primitiveArrayElementType(
        className: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let primitiveMapping: [(InternedString, TypeID)] = [
            (knownNames.intArray, sema.types.intType),
            (knownNames.longArray, sema.types.longType),
            (knownNames.shortArray, sema.types.intType),
            (knownNames.byteArray, sema.types.intType),
            (knownNames.ubyteArray, sema.types.ubyteType),
            (knownNames.ushortArray, sema.types.ushortType),
            (knownNames.uintArray, sema.types.uintType),
            (knownNames.ulongArray, sema.types.ulongType),
            (knownNames.doubleArray, sema.types.doubleType),
            (knownNames.floatArray, sema.types.floatType),
            (knownNames.booleanArray, sema.types.booleanType),
            (knownNames.charArray, sema.types.charType),
        ]
        return primitiveMapping.first { $0.0 == className }?.1
    }

    // MARK: - KFunction member call fallback (STDLIB-REFLECT-063)

    /// Checks whether the receiver type is `kotlin.reflect.KFunction<*>`.
    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard let classType = resolveClassType(receiverType, sema: sema),
              let kFuncSym = sema.types.kFunctionInterfaceSymbol,
              classType.classSymbol == kFuncSym
        else {
            return false
        }
        return true
    }

    /// Returns the return-type argument of a `KFunction<R>` type, or `anyType` when not available.
    private func kFunctionReturnType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard let classType = resolveClassType(receiverType, sema: sema),
              classType.args.count == 1
        else {
            return sema.types.anyType
        }
        switch classType.args[0] {
        case let .out(t), let .invariant(t): return t
        default: return sema.types.anyType
        }
    }

    /// Handles member calls on `KFunction<R>` receivers:
    /// - `call(vararg args)` → returns R (the KFunction type argument)
    func tryKFunctionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema) else { return nil }
        let memberName = interner.resolve(calleeName)

        switch memberName {
        case "call":
            // Infer argument types (accept any).
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            let returnType = kFunctionReturnType(receiverType, sema: sema)
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "name":
            let resultType = sema.types.stringType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "returnType":
            let kTypeSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("reflect"),
                interner.intern("KType"),
            ])
            let resultType = kTypeSymbol.map { symbol in
                sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
            } ?? sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "isSuspend":
            let resultType = sema.types.booleanType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "parameters":
            // parameters returns List<Any?>, but at this stage use anyType as a safe fallback.
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        default:
            return nil
        }
    }
}
