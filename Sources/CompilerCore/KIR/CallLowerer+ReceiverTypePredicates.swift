/// Receiver-type predicate helpers used by CallLowerer to dispatch
/// member-call lowerings (Regex / StringBuilder / Sequence / Iterable /
/// Collection / Map / Set / Array / Grouping / ArrayDeque etc.).
///
/// Split out from `CallLowerer+MemberCalls.swift` so that the dispatcher
/// file stays focused on lowering control flow.
extension CallLowerer {
    func isRegexLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isRegexSymbol(symbol)
    }

    func isStringBuilderLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isStringBuilderSymbol(symbol)
    }

    /// Check whether a type is Sequence-like (for member-call and operator
    /// lowering decisions).  Shared across `CallLowerer+MemberCalls` and
    /// `CallLowerer+Operators`; kept `internal` to avoid exposing it beyond
    /// the `CallLowerer` extensions.
    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isSequenceSymbol(symbol)
    }

    func isIterableOrCollectionInterfaceType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let symbolName = interner.resolve(symbol.name)
        return symbolName == "Iterable" || symbolName == "Collection"
    }

    func toMutableListRuntimeCalleeForSequenceOrIterableFallback(
        chosenCallee: SymbolID?,
        useIterableFallback: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        if useIterableFallback,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName == "kk_collection_toMutableList" || externalLinkName == "kk_iterable_toMutableList"
        {
            return interner.intern(externalLinkName)
        }
        return interner.intern(useIterableFallback ? "kk_iterable_toMutableList" : "kk_sequence_toMutableList")
    }

    func isGroupingLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isGroupingSymbol(symbol)
    }

    func isConcreteListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    func collectionElementPrimitiveCompareKind(
        of receiverType: TypeID,
        sema: SemaModule
    ) -> PrimitiveCompareABIKind? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let firstArg = classType.args.first
        else {
            return nil
        }
        let elementType: TypeID = switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
        return primitiveCompareABIKind(for: elementType, sema: sema)
    }

    func arraySizeRuntimeCallee(
        for receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return interner.intern("kk_array_size")
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch symbol.name {
        case knownNames.intArray:
            return interner.intern("kk_intArray_size")
        case knownNames.longArray:
            return interner.intern("kk_longArray_size")
        case knownNames.byteArray:
            return interner.intern("kk_byteArray_size")
        case knownNames.shortArray:
            return interner.intern("kk_shortArray_size")
        case knownNames.uintArray:
            return interner.intern("kk_uIntArray_size")
        case knownNames.ulongArray:
            return interner.intern("kk_uLongArray_size")
        case knownNames.doubleArray:
            return interner.intern("kk_doubleArray_size")
        case knownNames.floatArray:
            return interner.intern("kk_floatArray_size")
        case knownNames.booleanArray:
            return interner.intern("kk_booleanArray_size")
        case knownNames.charArray:
            return interner.intern("kk_charArray_size")
        case knownNames.ubyteArray:
            return interner.intern("kk_uByteArray_size")
        case knownNames.ushortArray:
            return interner.intern("kk_uShortArray_size")
        default:
            return interner.intern("kk_array_size")
        }
    }

    func collectionSelectorPrimitiveCompareKind(
        of selectorExpr: ExprID?,
        sema: SemaModule
    ) -> PrimitiveCompareABIKind? {
        guard let selectorExpr,
              let selectorType = sema.bindings.exprTypes[selectorExpr]
        else {
            return nil
        }
        switch sema.types.kind(of: sema.types.makeNonNullable(selectorType)) {
        case let .functionType(functionType):
            return primitiveCompareABIKind(for: functionType.returnType, sema: sema)
        default:
            return nil
        }
    }

    func isMutableListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == knownNames.mutableList
            || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
    }

    func isMutableSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol)
    }

    func isMapLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol)
    }

    func isArrayDequeLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isArrayDequeSymbol(symbol)
    }

    func isConcreteCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCollectionLikeSymbol(symbol)
    }

    func isConcreteArrayLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    func isGenericArrayLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == knownNames.array && classType.args.count == 1
    }

    func arrayBinarySearchRuntimeName(
        for receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let runtimeName: String
        switch symbol.name {
        case knownNames.array: runtimeName = "kk_array_binarySearch"
        case knownNames.intArray: runtimeName = "kk_intArray_binarySearch"
        case knownNames.longArray: runtimeName = "kk_longArray_binarySearch"
        case knownNames.byteArray: runtimeName = "kk_byteArray_binarySearch"
        case knownNames.shortArray: runtimeName = "kk_shortArray_binarySearch"
        case knownNames.uintArray: runtimeName = "kk_uIntArray_binarySearch"
        case knownNames.ulongArray: runtimeName = "kk_uLongArray_binarySearch"
        case knownNames.doubleArray: runtimeName = "kk_doubleArray_binarySearch"
        case knownNames.floatArray: runtimeName = "kk_floatArray_binarySearch"
        case knownNames.booleanArray: runtimeName = "kk_booleanArray_binarySearch"
        case knownNames.charArray: runtimeName = "kk_charArray_binarySearch"
        case knownNames.ubyteArray: runtimeName = "kk_uByteArray_binarySearch"
        case knownNames.ushortArray: runtimeName = "kk_uShortArray_binarySearch"
        default: return nil
        }
        return interner.intern(runtimeName)
    }

    func isArrayBinarySearchRuntimeCallee(
        _ callee: InternedString,
        interner: StringInterner
    ) -> Bool {
        let names = [
            "kk_array_binarySearch",
            "kk_intArray_binarySearch",
            "kk_longArray_binarySearch",
            "kk_byteArray_binarySearch",
            "kk_shortArray_binarySearch",
            "kk_uIntArray_binarySearch",
            "kk_uLongArray_binarySearch",
            "kk_doubleArray_binarySearch",
            "kk_floatArray_binarySearch",
            "kk_booleanArray_binarySearch",
            "kk_charArray_binarySearch",
            "kk_uByteArray_binarySearch",
            "kk_uShortArray_binarySearch",
        ]
        return names.contains { callee == interner.intern($0) }
    }

    func isSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isSetLikeSymbol(symbol)
    }

    /// Returns `true` when the receiver type is `Iterable<Char>` (the type produced by `String.asIterable()`).
    /// This allows routing `.toList()` and `.iterator()` to the specialised string-iterable runtime functions.
    func isStringIterableType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard symbol.fqName == iterableFQName else {
            return false
        }
        // Verify the type argument is Char
        guard let firstArg = classType.args.first else {
            return false
        }
        let elementType: TypeID = switch firstArg {
        case let .invariant(t), let .out(t), let .in(t): t
        case .star: sema.types.anyType
        }
        return sema.types.makeNonNullable(elementType) == sema.types.make(.primitive(.char, .nonNull))
    }
}
