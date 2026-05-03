import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Type aliases ArrayList, HashMap, HashSet, LinkedHashMap, LinkedHashSet (STDLIB-560).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Collection Type Aliases (STDLIB-560)

    /// Register `ArrayList<E>`, `LinkedList<E>`, `HashMap<K,V>`, `HashSet<E>`, `LinkedHashMap<K,V>`, `LinkedHashSet<E>`
    /// as type aliases pointing to their corresponding mutable collection types.
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

        // LinkedHashSet<E> → MutableSet<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "LinkedHashSet",
            targetName: "MutableSet",
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
}
