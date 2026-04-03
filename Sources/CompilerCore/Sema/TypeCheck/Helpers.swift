import Foundation

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

    /// Returns the element type for iterating over the given type in a for-loop.
    /// Handles both array types and range/progression types (Int representing IntRange,
    /// UInt representing UIntRange (STDLIB-523), etc.).
    /// - Parameter isRangeExpr: true when the iterable expression is a range operator
    ///   (rangeTo, rangeUntil, downTo, step), allowing Int to be treated as iterable.
    func iterableElementType(
        for iterableType: TypeID,
        isRangeExpr: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        // Range/progression types (Int/Long/UInt/ULong) are iterable over their element type,
        // but only when the expression is actually a range operator.
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
        if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(iterableType)),
           let symbol = sema.symbols.symbol(classType.classSymbol)
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
        return customIteratorElementType(for: iterableType, sema: sema, interner: interner)
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
            sema: sema
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
            sema: sema
        )
        if let nextCandidate = nextCandidates.first,
           let nextSignature = sema.symbols.functionSignature(for: nextCandidate)
        {
            return nextSignature.returnType
        }
        return sema.types.anyType
    }

    /// For Map<K, V> and MutableMap<K, V>, return Map.Entry<K, V> as the element type.
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

        // Look up the Map.Entry type
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let entryFQName = kotlinCollectionsPkg + [mapName, interner.intern("Entry")]
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
        guard case let .classType(classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        switch symbol.name {
        case knownNames.intArray:
            return sema.types.intType
        case knownNames.longArray:
            return sema.types.longType
        case knownNames.shortArray:
            return sema.types.intType
        case knownNames.byteArray:
            return sema.types.intType
        case knownNames.ubyteArray:
            return sema.types.ubyteType
        case knownNames.ushortArray:
            return sema.types.ushortType
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
        case interner.intern("kk_array_get"), interner.intern("kk_list_get"):
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_set"):
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        // Flow (CORO-003): preserve `flow { ... }` fallback typing as Flow<Any>.
        // Member-like names such as `map`/`filter`/`take` stay conservative here
        // because this helper does not know whether the unresolved callee was
        // invoked on an actual Flow receiver.
        case knownNames.flow,
             interner.intern("channelFlow"),
             interner.intern("callbackFlow"):
            guard argumentCount == 1 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case interner.intern("flowOf"):
            guard argumentCount >= 0 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case interner.intern("emptyFlow"):
            guard argumentCount == 0 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.emit:
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("collect"):
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
        if name == interner.intern("Byte") || name == interner.intern("Short") {
            return types.make(.primitive(.int, nullability))
        }
        return nil
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
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
                let fqCandidates = sema.symbols.lookupAll(fqName: path).filter { symbolID in
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    switch sym.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }.sorted(by: { $0.rawValue < $1.rawValue })
                // Fall back to short-name lookup so that packaged types
                // (e.g. `package test; class Foo`) resolve when referenced
                // by simple name (`Foo`) during type checking.
                let candidates: [SymbolID] = if !fqCandidates.isEmpty {
                    fqCandidates
                } else {
                    sema.symbols.lookupByShortName(shortName).filter { symbolID in
                        guard let sym = sema.symbols.symbol(symbolID) else { return false }
                        switch sym.kind {
                        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                            return true
                        default:
                            return false
                        }
                    }.sorted(by: { $0.rawValue < $1.rawValue })
                }
                if let symbolID = candidates.first {
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
                    return sema.types.make(.classType(ClassType(
                        classSymbol: symbolID,
                        args: resolvedArgs,
                        nullability: nullability
                    )))
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(interner.resolve(shortName))'.",
                    range: nil
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
                diagnostics: diagnostics
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
