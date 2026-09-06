
/// Returns the element type for a nominal range/progression class with a
/// fixed primitive element type, such as `UIntRange` or `CharProgression`.
func nominalRangeElementType(
    for rangeType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    let nonNullType = sema.types.makeNonNullable(rangeType)
    guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
        return nil
    }

    switch interner.resolve(symbol.name) {
    case "IntRange", "IntProgression":
        return sema.types.intType
    case "LongRange", "LongProgression":
        return sema.types.longType
    case "UIntRange", "UIntProgression":
        return sema.types.uintType
    case "ULongRange", "ULongProgression":
        return sema.types.ulongType
    case "CharRange", "CharProgression":
        return sema.types.charType
    default:
        return nil
    }
}

struct TypeCheckHelpers {
    private func syntheticCoroutineNominalType(
        packageName: [InternedString],
        shortName: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let shortNameID = interner.intern(shortName)
        let candidates = sema.symbols.lookupAll(fqName: packageName + [shortNameID])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .object:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
        guard let symbolID = candidates.first else {
            return nil
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbolID, args: [], nullability: .nonNull)))
    }

    func emitVisibilityError(
        for symbol: SemanticSymbol,
        name: String,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let visLabel = symbol.visibility == .protected ? "protected" : "private"
        let code = symbol.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
        diagnostics.error(code, "Cannot access '\(name)': it is \(visLabel).", range: range)
    }

    func bindAndReturnErrorType(_ id: ExprID, sema: SemaModule) -> TypeID {
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    func isRangeLikeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "OpenEndRange", "ClosedRange", "ClosedFloatingPointRange",
             "IntRange", "IntProgression",
             "LongRange", "LongProgression",
             "UIntRange", "UIntProgression",
             "ULongRange", "ULongProgression",
             "CharRange", "CharProgression":
            return true
        default:
            return false
        }
    }

    /// Returns the expected scalar element type for a range-like declared type
    /// (a type for which `isRangeLikeType` returns `true`).
    ///
    /// Concrete classes such as `LongRange`/`CharProgression` have a fixed
    /// primitive element type. Generic interfaces (`OpenEndRange<T>`,
    /// `ClosedRange<T>`, `ClosedFloatingPointRange<T>`) are invariant in `T`,
    /// so their element type is read directly from the sole type argument.
    /// Returns `nil` when the element type cannot be determined (e.g. a
    /// star-projected type argument), in which case callers should not skip
    /// the nominal subtype check.
    func rangeLikeDeclaredElementType(
        for rangeType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        if let fixedElement = nominalRangeElementType(for: rangeType, sema: sema, interner: interner) {
            return fixedElement
        }
        guard let (classType, symbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(rangeType), sema: sema
        ) else {
            return nil
        }
        switch interner.resolve(symbol.name) {
        case "OpenEndRange", "ClosedRange", "ClosedFloatingPointRange":
            switch classType.args.first {
            case let .invariant(inner), let .out(inner), let .in(inner):
                return sema.types.makeNonNullable(inner)
            case .star, nil:
                return nil
            }
        default:
            return nil
        }
    }

    /// Returns the actual element type of an expression already marked as a
    /// range expression by the isRangeExpr duck-typing convention (see
    /// `rangeLikeDeclaredElementType`'s callers).
    ///
    /// A range literal's bound `bodyType` is usually the scalar element type
    /// itself (Int/Long/UInt/ULong), but two cases hide the true element type
    /// behind a side channel: Char ranges share Int's representation
    /// (STDLIB-290), and floating-point ranges are tracked separately
    /// (`floatingPointRangeElementType`) because the primary scalar inference
    /// in `ExprTypeChecker+BinaryAndFlowInference.swift` has no Double/Float
    /// branch. A range value produced by a resolved call (e.g.
    /// `IntProgression.fromClosedRange(...)`) instead binds `bodyType` to the
    /// real nominal class directly, so that case is unwrapped via
    /// `rangeLikeDeclaredElementType` too.
    func rangeExprActualElementType(
        for exprID: ExprID,
        bodyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let floatElement = sema.bindings.floatingPointRangeElementType(forExpr: exprID) {
            return floatElement
        }
        if sema.bindings.isCharRangeExpr(exprID) {
            return sema.types.charType
        }
        if isRangeLikeType(bodyType, sema: sema, interner: interner),
           let nominalElement = rangeLikeDeclaredElementType(for: bodyType, sema: sema, interner: interner)
        {
            return nominalElement
        }
        return sema.types.makeNonNullable(bodyType)
    }

    /// Decides whether the nominal subtype check between a range-literal
    /// body/initializer and a range-like declared/expected type may be
    /// skipped under the isRangeExpr duck-typing convention.
    ///
    /// The skip is only valid when the body's actual element type matches
    /// the declared type's expected element type exactly: range element
    /// types are invariant type parameters, and primitives don't implicitly
    /// widen in Kotlin (e.g. an `Int` range literal is not an acceptable
    /// `LongRange`). When the element types don't match — or the expected
    /// element type can't be determined, e.g. a star-projected type
    /// argument — this returns `false` so the caller falls through to the
    /// normal subtype constraint, which correctly rejects the mismatch.
    func rangeExprMatchesDeclaredElementType(
        bodyExprID: ExprID,
        bodyType: TypeID,
        declaredType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.bindings.isRangeExpr(bodyExprID),
              isRangeLikeType(declaredType, sema: sema, interner: interner),
              let expectedElement = rangeLikeDeclaredElementType(
                  for: declaredType, sema: sema, interner: interner
              )
        else {
            return false
        }
        let actualElement = rangeExprActualElementType(
            for: bodyExprID, bodyType: bodyType, sema: sema, interner: interner
        )
        return actualElement == expectedElement
    }

    /// Returns true only for the plain `kotlin.collections.Iterable` interface.
    ///
    /// A range expression uses its element type as the intermediate Sema type,
    /// so `LocalDeclTypeChecker` needs a narrow exemption for an explicitly
    /// annotated `Iterable<T>`. Concrete collection types and other iterable
    /// classes still require the normal subtype constraint.
    func isPlainIterableType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
    }

    /// Returns the element argument from a plain `kotlin.collections.Iterable` type.
    ///
    /// This deliberately reads the resolved nominal argument instead of asking
    /// `iterableElementType` to inspect the synthetic `iterator()` member. The
    /// latter can expose the declaration's unsubstituted `E` type parameter for
    /// the interface itself.
    func plainIterableElementType(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard isPlainIterableType(type, sema: sema, interner: interner),
              let (classType, _) = resolveClassTypeSymbol(type, sema: sema),
              let elementArgument = classType.args.first
        else {
            return nil
        }
        switch elementArgument {
        case let .invariant(element), let .out(element), let .in(element):
            return element
        case .star:
            return sema.types.anyType
        }
    }

    func isOpenEndRangeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return interner.resolve(symbol.name) == "OpenEndRange"
    }

    /// Returns the element type for iterating over the given type in a for-loop.
    /// Handles both array types and range/progression types (Int representing IntRange,
    /// UInt representing UIntRange (STDLIB-523), etc.).
    /// - Parameter isRangeExpr: true when the iterable expression is a range operator
    ///   (rangeTo, rangeUntil, downTo, step), allowing Int to be treated as iterable.
    /// - Parameter isCharRangeExpr: true when the range expression's operands were Char
    ///   (STDLIB-290). Char ranges share Int's runtime/static representation (see the
    ///   `.rangeTo`/`.rangeUntil`/`.downTo` binary op inference), so this must be checked
    ///   before the plain Int case below to avoid mistyping the loop variable as Int.
    func iterableElementType(
        for iterableType: TypeID,
        isRangeExpr: Bool,
        isCharRangeExpr: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        // String is iterable over its Char elements; the loop variable still needs
        // the correct static Char type for member resolution and explicit typing.
        if sema.types.makeNonNullable(iterableType) == sema.types.stringType {
            return sema.types.charType
        }
        // Range/progression types (Int/Long/UInt/ULong) are iterable over their element type,
        // but only when the expression is actually a range operator.
        if isRangeExpr, isCharRangeExpr, iterableType == sema.types.intType {
            return sema.types.charType
        }
        if isRangeExpr, iterableType == sema.types.intType {
            return sema.types.intType
        }
        if isRangeExpr, iterableType == sema.types.longType {
            return sema.types.longType
        }
        // STDLIB-523: UIntRange support
        if isRangeExpr, iterableType == sema.types.uintType {
            return sema.types.uintType
        }
        // Range expressions with element type ULong (i.e. ULong + range marker)
        // are iterable, yielding ULong elements (STDLIB-524).
        if isRangeExpr, iterableType == sema.types.ulongType {
            return sema.types.ulongType
        }
        if let (_, symbol) = resolveClassTypeSymbol(iterableType, sema: sema)
        {
            switch interner.resolve(symbol.name) {
            case "IntRange", "IntProgression":
                return sema.types.intType
            case "LongRange", "LongProgression":
                return sema.types.longType
            case "UIntRange", "UIntProgression":
                return sema.types.uintType
            case "ULongRange", "ULongProgression":
                return sema.types.ulongType
            case "CharRange", "CharProgression":
                return sema.types.charType
            default:
                break
            }
        }
        // Map/MutableMap iteration yields Map.Entry<K, V>, not the first type argument.
        if let entryType = mapEntryElementType(for: iterableType, sema: sema, interner: interner) {
            return entryType
        }
        if let arrayElement = arrayElementType(for: iterableType, sema: sema, interner: interner) {
            return arrayElement
        }
        // STDLIB-OP-032: Custom classes with operator fun iterator() are iterable.
        // Resolve the element type from the iterator's next() return type or the
        // Iterator<T> type argument.
        if let customElement = customIteratorElementType(for: iterableType, sema: sema, interner: interner) {
            return customElement
        }
        // BUG-167: A class implementing `Iterable<T>` iterates over `T` even when
        // its `iterator()` override carries no `operator` flag of its own.
        return iterableSupertypeElementType(for: iterableType, sema: sema, interner: interner)
    }

    /// Element type lifted from the `kotlin.collections.Iterable<T>` supertype of
    /// a class, or nil when the class does not implement `Iterable`.
    private func iterableSupertypeElementType(
        for iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let (classType, _) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(iterableType),
            sema: sema
        ),
            let iterableSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]),
            let args = sema.types.liftedNominalSupertypeArgs(
                from: classType.classSymbol,
                childArgs: classType.args,
                to: iterableSymbol
            ),
            let element = args.first
        else {
            return nil
        }
        return switch element {
        case let .invariant(type), let .out(type), let .in(type): type
        case .star: sema.types.anyType
        }
    }

    /// Resolves the element type of a custom class with `operator fun iterator()`.
    /// Returns nil if no such operator is defined.
    private func customIteratorElementType(
        for iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        guard case .classType = sema.types.kind(of: nonNullType) else { return nil }

        let iteratorName = interner.intern("iterator")
        let candidates = collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        guard let chosen = candidates.first,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        // The iterator() return type should be Iterator<T> — extract T from its type args.
        let returnType = signature.returnType
        if case let .classType(iteratorClassType) = sema.types.kind(of: returnType),
           !iteratorClassType.args.isEmpty
        {
            switch iteratorClassType.args[0] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                return inner
            case .star:
                return sema.types.nullableAnyType
            }
        }
        // Fallback: try to find next() on the iterator type and use its return type.
        let nextName = interner.intern("next")
        let nextCandidates = collectMemberFunctionCandidates(
            named: nextName,
            receiverType: returnType,
            sema: sema,
            interner: interner
        )
        if let nextCandidate = nextCandidates.first,
           let nextSignature = sema.symbols.functionSignature(for: nextCandidate)
        {
            return nextSignature.returnType
        }
        return sema.types.anyType
    }

    /// For Map<K, V>, return Map.Entry<K, V>; mutable maps iterate mutable entries.
    private func mapEntryElementType(
        for mapType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case let .classType(classType) = sema.types.kind(of: mapType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              classType.args.count >= 2
        else {
            return nil
        }
        let mapName = interner.intern("Map")
        let mutableMapName = interner.intern("MutableMap")
        guard symbol.name == mapName || symbol.name == mutableMapName else {
            return nil
        }

        // MutableMap.iterator() returns MutableMap.MutableEntry, while Map.iterator()
        // returns the read-only Map.Entry surface.
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let entryOwnerName = symbol.name == mutableMapName ? mutableMapName : mapName
        let entryName = symbol.name == mutableMapName ? interner.intern("MutableEntry") : interner.intern("Entry")
        let entryFQName = kotlinCollectionsPkg + [entryOwnerName, entryName]
        guard let entrySymbol = sema.symbols.lookup(fqName: entryFQName) else {
            return nil
        }

        // Extract K and V type arguments from Map<K, V>
        let keyArg = classType.args[0]
        let valueArg = classType.args[1]
        let keyType: TypeID
        let valueType: TypeID
        switch keyArg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            keyType = inner
        case .star:
            keyType = sema.types.nullableAnyType
        }
        switch valueArg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            valueType = inner
        case .star:
            valueType = sema.types.nullableAnyType
        }

        return sema.types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(arrayType, sema: sema) else {
            return nil
        }
        switch symbol.name {
        case knownNames.intArray:
            return sema.types.intType
        case knownNames.longArray:
            return sema.types.longType
        case knownNames.shortArray:
            return sema.types.shortType
        case knownNames.byteArray:
            return sema.types.byteType
        case knownNames.ubyteArray:
            return sema.types.ubyteType
        case knownNames.ushortArray:
            return sema.types.ushortType
        case knownNames.uintArray:
            return sema.types.uintType
        case knownNames.ulongArray:
            return sema.types.ulongType
        case knownNames.doubleArray:
            return sema.types.doubleType
        case knownNames.floatArray:
            return sema.types.floatType
        case knownNames.booleanArray:
            return sema.types.booleanType
        case knownNames.charArray:
            return sema.types.charType
        default:
            // For generic collection types (e.g. List<String?>, MutableList<Int>),
            // extract the first type argument as the element type.
            if !classType.args.isEmpty {
                switch classType.args[0] {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return inner
                case .star:
                    return sema.types.nullableAnyType
                }
            }
            return nil
        }
    }

    func kxMiniCoroutineBuiltinReturnType(
        calleeName: InternedString?,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let calleeName else {
            return nil
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch calleeName {
        case knownNames.runBlocking:
            guard argumentCount >= 1 else { return nil }
            return sema.types.anyType
        case knownNames.launch:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Job",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.async:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Deferred",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.produce:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("channels")],
                shortName: "Channel",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case interner.intern("delay"):
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("kk_array_new"),
             knownNames.intArray,
             knownNames.longArray,
             knownNames.doubleArray,
             knownNames.floatArray,
             knownNames.booleanArray,
             knownNames.charArray:
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_get"), interner.intern("__kk_list_get"):
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_set"):
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        // Flow (CORO-003): preserve `flow { ... }` fallback typing as Flow<Any>.
        // Member-like names such as `map`/`filter`/`take` stay conservative here
        // because this helper does not know whether the unresolved callee was
        // invoked on an actual Flow receiver.
        case knownNames.flow:
            guard argumentCount == 1 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        // KSP-674: flowOf / emptyFlow are Kotlin source now; they resolve
        // normally and no longer need unresolved-call fallback typing.
        case knownNames.emit:
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("collect"), interner.intern("collectLatest"):
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case interner.intern("map"), interner.intern("filter"), interner.intern("take"),
             interner.intern("transform"), interner.intern("takeWhile"), interner.intern("dropWhile"),
             interner.intern("flatMapConcat"), interner.intern("flatMapMerge"), interner.intern("flatMapLatest"),
             interner.intern("buffer"), interner.intern("conflate"), interner.intern("flowOn"),
             interner.intern("debounce"), interner.intern("sample"), interner.intern("delayEach"),
             interner.intern("zip"), interner.intern("combine"), interner.intern("merge"):
            guard argumentCount == 1 || argumentCount == 2 else { return nil }
            return sema.types.nullableAnyType
        case interner.intern("toList"):
            guard argumentCount == 0 || argumentCount == 1 else { return nil }
            return sema.types.anyType
        case interner.intern("first"):
            guard argumentCount == 0 || argumentCount == 1 else { return nil }
            return sema.types.anyType
        case interner.intern("single"):
            guard argumentCount == 0 || argumentCount == 1 else { return nil }
            return sema.types.anyType
        default:
            return nil
        }
    }

    /// Construct a `Flow<elementType>` ClassType by looking up the synthetic
    /// `kotlinx.coroutines.flow.Flow` interface symbol.  Returns `nil` when
    /// the symbol has not been registered (caller should fall back to `anyType`).
    func makeFlowType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let flowFQName: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
            interner.intern("flow"),
            interner.intern("Flow"),
        ]
        guard let symbolID = sema.symbols.lookup(fqName: flowFQName) else { return nil }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbolID,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func resolveBuiltinTypeName(
        _ name: InternedString,
        nullability: Nullability = .nonNull,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        if let builtin = BuiltinTypeNames(interner: interner).resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtin
        }
        return nil
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil,
        inferenceContext: TypeInferenceContext? = nil,
        usageRange: SourceRange? = nil
    ) -> TypeID {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return sema.types.errorType
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            guard let shortName = path.last else {
                return sema.types.errorType
            }
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(shortName, nullability: nullability, types: sema.types, interner: interner) {
                return builtin
            }
            if path.count == 1,
               let scope,
               let typeParameterSymbol = resolveTypeParameterSymbol(shortName, scope: scope, sema: sema)
            {
                return sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: nullability)))
            }
            do {
                func isTypeLikeSymbol(_ symbolID: SymbolID) -> Bool {
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    switch sym.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                // Prefer the lexically-scoped candidate (which encodes import
                // priority: explicit imports > wildcard imports > default
                // imports, same as expression name resolution) for unqualified
                // references. Without this, an unrelated same-named
                // declaration from a non-imported package (e.g.
                // `kotlin.properties.Lazy` vs. the in-scope `kotlin.Lazy`)
                // could shadow the correct symbol merely by having a lower
                // internal ID, since the short-name fallback below has no
                // notion of scope.
                let scopeCandidates: [SymbolID] = if path.count == 1, let scope {
                    scope.lookup(shortName).filter(isTypeLikeSymbol).sorted(by: { $0.rawValue < $1.rawValue })
                } else {
                    []
                }
                // A type imported by its outer declaration can be referenced by
                // a qualified nested name (for example, `Base64.Default`). The
                // full path is not globally qualified in that form, so walk the
                // imported outer symbol before falling back to short-name lookup.
                let qualifiedScopeCandidates: [SymbolID] = {
                    guard path.count > 1, let scope else { return [] }
                    var current = scope.lookup(path[0])
                        .filter(isTypeLikeSymbol)
                        .sorted(by: { $0.rawValue < $1.rawValue })
                    for component in path.dropFirst() {
                        current = current.flatMap { ownerID -> [SymbolID] in
                            guard let owner = sema.symbols.symbol(ownerID) else { return [] }
                            return sema.symbols.lookupAll(fqName: owner.fqName + [component])
                                .filter(isTypeLikeSymbol)
                        }
                        .sorted(by: { $0.rawValue < $1.rawValue })
                        if current.isEmpty {
                            break
                        }
                    }
                    return current
                }()
                let fqCandidates = sema.symbols.lookupAll(fqName: path).filter(isTypeLikeSymbol)
                    .sorted(by: { $0.rawValue < $1.rawValue })
                // Resolve nested types through the imported or package-scoped
                // nominal root before falling back to the short name. This is
                // required when several nominal types expose the same nested
                // name, such as kotlin.time.Clock.Companion.
                let nestedCandidates: [SymbolID] = {
                    guard path.count > 1, let scope else {
                        return []
                    }
                    let rootCandidates = scope.lookup(path[0]).filter(isTypeLikeSymbol)
                    return rootCandidates.flatMap { rootSymbol -> [SymbolID] in
                        guard let rootInfo = sema.symbols.symbol(rootSymbol) else {
                            return []
                        }
                        return sema.symbols.lookupAll(
                            fqName: rootInfo.fqName + Array(path.dropFirst())
                        ).filter(isTypeLikeSymbol)
                    }
                    .sorted(by: { $0.rawValue < $1.rawValue })
                }()
                // Fall back to short-name lookup so that packaged types
                // (e.g. `package test; class Foo`) resolve when referenced
                // by simple name (`Foo`) during type checking.
                let candidates: [SymbolID] = if !scopeCandidates.isEmpty {
                    scopeCandidates
                } else if !qualifiedScopeCandidates.isEmpty {
                    qualifiedScopeCandidates
                } else if !fqCandidates.isEmpty {
                    fqCandidates
                } else if !nestedCandidates.isEmpty {
                    nestedCandidates
                } else {
                    sema.symbols.lookupByShortName(shortName).filter(isTypeLikeSymbol)
                        .sorted(by: { $0.rawValue < $1.rawValue })
                }
                if let symbolID = candidates.first {
                    if let inferenceContext, let diagnostics {
                        checkOptIn(
                            for: symbolID,
                            ctx: inferenceContext,
                            range: usageRange,
                            diagnostics: diagnostics
                        )
                    }
                    let resolvedArgs = resolveTypeArgRefsForTypeCheck(
                        argRefs, ast: ast, sema: sema, interner: interner,
                        scope: scope, diagnostics: diagnostics
                    )
                    // Expand typealias at call-site
                    if let sym = sema.symbols.symbol(symbolID), sym.kind == .typeAlias {
                        if let expanded = expandTypeAlias(
                            symbolID,
                            typeArgs: resolvedArgs,
                            sema: sema,
                            visited: [],
                            depth: 0,
                            diagnostics: diagnostics
                        ) {
                            if nullability == .nullable {
                                return applyNullabilityForTypeCheck(expanded, types: sema.types)
                            }
                            return expanded
                        }
                        // Fall through to classType for error recovery
                    }
                    if let sym = sema.symbols.symbol(symbolID),
                       symbolID == sema.types.kClassInterfaceSymbol
                        || sym.fqName == [interner.intern("kotlin"), interner.intern("reflect"), interner.intern("KClass")]
                    {
                        // Preserve star and contravariant KClass projections in the
                        // nominal representation. A covariant projection is
                        // equivalent to the dedicated KClass<T> representation.
                        if let firstArg = resolvedArgs.first {
                            switch firstArg {
                            case .star, .in:
                                return sema.types.make(.classType(ClassType(
                                    classSymbol: symbolID,
                                    args: resolvedArgs,
                                    nullability: nullability
                                )))
                            case .invariant, .out:
                                break
                            }
                        }
                        let argumentType: TypeID = if let firstArg = resolvedArgs.first {
                            switch firstArg {
                            case let .invariant(t):
                                t
                            case .star:
                                sema.types.anyType
                            case let .out(t), let .in(t):
                                t
                            }
                        } else {
                            sema.types.anyType
                        }
                        return sema.types.makeKClassType(argument: argumentType, nullability: nullability)
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: symbolID,
                        args: resolvedArgs,
                        nullability: nullability
                    )))
                }
                let stringBuilderName = interner.intern("StringBuilder")
                let kotlinTextStringBuilderFQName = [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    stringBuilderName,
                ]
                if (path.count == 1 && shortName == stringBuilderName) || path == kotlinTextStringBuilderFQName {
                    let stringBuilderSymbol = ensureKotlinTextStringBuilderSymbol(
                        symbols: sema.symbols,
                        interner: interner
                    )
                    let resolvedArgs = resolveTypeArgRefsForTypeCheck(
                        argRefs, ast: ast, sema: sema, interner: interner,
                        scope: scope, diagnostics: diagnostics
                    )
                    return sema.types.make(.classType(ClassType(
                        classSymbol: stringBuilderSymbol,
                        args: resolvedArgs,
                        nullability: nullability
                    )))
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(interner.resolve(shortName))'.",
                    range: usageRange
                )
                return sema.types.errorType
            }

        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let contextReceiverTypes = contextReceiverRefIDs.map {
                resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
            }
            let receiverType: TypeID? = receiverRefID.flatMap { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics) }
            let paramTypes = paramRefIDs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics) }
            let returnType = resolveTypeRef(returnRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
            return sema.types.make(.functionType(FunctionType(
                contextReceivers: contextReceiverTypes,
                receiver: receiverType,
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case let .intersection(partRefs):
            let partTypes = partRefs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics) }
            return sema.types.make(.intersection(partTypes))

        case let .annotated(base, annotations):
            let baseType = resolveTypeRef(base, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
            return ExtensionFunctionTypeSupport.normalizeAnnotatedType(
                baseType: baseType,
                annotations: annotations,
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                diagnostics: diagnostics,
                range: usageRange
            )
        }
    }

    func resolveTypeArgRefsForTypeCheck(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case let .invariant(innerRef):
                .invariant(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case let .out(innerRef):
                .out(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case let .in(innerRef):
                .in(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case .star:
                .star
            }
        }
    }

    private func resolveTypeParameterSymbol(
        _ name: InternedString,
        scope: Scope,
        sema: SemaModule
    ) -> SymbolID? {
        scope.lookup(name).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .typeParameter
        }
    }

    /// Construct a non-null Throwable type from the kotlin.Throwable symbol.
    func throwableType(sema: SemaModule, interner: StringInterner) -> TypeID? {
        let throwableFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Throwable")]
        guard let throwableSymbol = sema.symbols.lookup(fqName: throwableFQName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }
}
