import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Type aliases ArrayList, HashMap, HashSet, LinkedHashMap (STDLIB-560)
/// plus concrete LinkedHashSet class surface.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Collection Type Aliases (STDLIB-560)

    /// Register the synthetic collection aliases and concrete collection classes.
    func registerSyntheticCollectionTypeAliases(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        // ArrayList<E> → MutableList<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "ArrayList",
            targetName: "MutableList",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedList<E> → MutableList<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "LinkedList",
            targetName: "MutableList",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // HashSet<E> → MutableSet<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "HashSet",
            targetName: "MutableSet",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedHashSet<E> concrete class implementing MutableSet<E>
        registerSyntheticLinkedHashSetClass(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // HashMap<K, V> → MutableMap<K, V>
        registerTwoTypeParamCollectionAlias(
            aliasName: "HashMap",
            targetName: "MutableMap",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedHashMap<K, V> → MutableMap<K, V>
        registerTwoTypeParamCollectionAlias(
            aliasName: "LinkedHashMap",
            targetName: "MutableMap",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
    }

    /// Register a type alias with one type parameter (e.g. `ArrayList<E> = MutableList<E>`).
    private func registerSingleTypeParamCollectionAlias(
        aliasName: String,
        targetName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let internedAlias = interner.intern(aliasName)
        let aliasFQName = kotlinCollectionsPkg + [internedAlias]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        // Validate target symbol exists before registering alias
        let internedTarget = interner.intern(targetName)
        let targetFQName = kotlinCollectionsPkg + [internedTarget]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else {
            assertionFailure("Synthetic collection type alias '\(aliasName)': target '\(targetName)' not found in symbol table")
            return
        }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: internedAlias,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define type parameter E
        let typeParamName = interner.intern("E")
        let typeParamFQName = aliasFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setTypeAliasTypeParameters([typeParamSymbol], for: aliasSymbol)

        // Build underlying type: TargetType<E>
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    /// Register a type alias with two type parameters (e.g. `HashMap<K, V> = MutableMap<K, V>`).
    private func registerTwoTypeParamCollectionAlias(
        aliasName: String,
        targetName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let internedAlias = interner.intern(aliasName)
        let aliasFQName = kotlinCollectionsPkg + [internedAlias]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        // Validate target symbol exists before registering alias
        let internedTarget = interner.intern(targetName)
        let targetFQName = kotlinCollectionsPkg + [internedTarget]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else {
            assertionFailure("Synthetic collection type alias '\(aliasName)': target '\(targetName)' not found in symbol table")
            return
        }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: internedAlias,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define type parameters K, V
        let keyParamName = interner.intern("K")
        let valueParamName = interner.intern("V")
        let keyParamFQName = aliasFQName + [keyParamName]
        let valueParamFQName = aliasFQName + [valueParamName]
        let keyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyParamName,
            fqName: keyParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueParamName,
            fqName: valueParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setTypeAliasTypeParameters([keyParamSymbol, valueParamSymbol], for: aliasSymbol)

        // Build underlying type: TargetType<K, V>
        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyParamSymbol, nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueParamSymbol, nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    /// Register `LinkedHashSet<E>` as a concrete synthetic class implementing `MutableSet<E>`.
    private func registerSyntheticLinkedHashSetClass(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let linkedHashSetName = interner.intern("LinkedHashSet")
        let linkedHashSetFQName = kotlinCollectionsPkg + [linkedHashSetName]
        guard symbols.lookup(fqName: linkedHashSetFQName) == nil else { return }

        let mutableSetName = interner.intern("MutableSet")
        let mutableSetFQName = kotlinCollectionsPkg + [mutableSetName]
        guard let mutableSetSymbol = symbols.lookup(fqName: mutableSetFQName) else {
            assertionFailure("Synthetic LinkedHashSet: target MutableSet not found in symbol table")
            return
        }

        let linkedHashSetSymbol = symbols.define(
            kind: .class,
            name: linkedHashSetName,
            fqName: linkedHashSetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .openType]
        )

        let typeParamName = interner.intern("E")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: linkedHashSetFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: linkedHashSetSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: linkedHashSetSymbol)
        symbols.setDirectSupertypes([mutableSetSymbol], for: linkedHashSetSymbol)
        types.setNominalDirectSupertypes([mutableSetSymbol], for: linkedHashSetSymbol)
        let mutableSetArgs: [TypeArg] = [.invariant(typeParamType)]
        symbols.setSupertypeTypeArgs(mutableSetArgs, for: linkedHashSetSymbol, supertype: mutableSetSymbol)
        types.setNominalSupertypeTypeArgs(mutableSetArgs, for: linkedHashSetSymbol, supertype: mutableSetSymbol)

        let initName = interner.intern("<init>")
        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: linkedHashSetFQName + [initName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(linkedHashSetSymbol, for: constructorSymbol)
        symbols.setExternalLinkName("kk_emptySet", for: constructorSymbol)
        let returnType = types.make(.classType(ClassType(
            classSymbol: linkedHashSetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: constructorSymbol
        )
    }
}
