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

        // LinkedList<E> : MutableList<E>
        registerSyntheticLinkedListClass(
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

    /// Register concrete `LinkedList<E>` backed by the same runtime list box as MutableList.
    private func registerSyntheticLinkedListClass(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let linkedListName = interner.intern("LinkedList")
        let linkedListFQName = kotlinCollectionsPkg + [linkedListName]
        guard symbols.lookup(fqName: linkedListFQName) == nil else { return }

        let mutableListFQName = kotlinCollectionsPkg + [interner.intern("MutableList")]
        guard let mutableListSymbol = symbols.lookup(fqName: mutableListFQName) else {
            assertionFailure("Synthetic LinkedList: target 'MutableList' not found in symbol table")
            return
        }

        let linkedListSymbol = symbols.define(
            kind: .class,
            name: linkedListName,
            fqName: linkedListFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .openType]
        )

        let typeParamName = interner.intern("E")
        let typeParamFQName = linkedListFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: linkedListSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: linkedListSymbol)

        let linkedListType = types.make(.classType(ClassType(
            classSymbol: linkedListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(linkedListType, for: linkedListSymbol)

        let abstractMutableListSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("AbstractMutableList")]
        )
        let directSupertypes = [abstractMutableListSymbol, mutableListSymbol].compactMap { $0 }
        symbols.setDirectSupertypes(directSupertypes, for: linkedListSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: linkedListSymbol)
        for supertype in directSupertypes {
            symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: linkedListSymbol, supertype: supertype)
            types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: linkedListSymbol, supertype: supertype)
        }

        let initName = interner.intern("<init>")
        let initFQName = linkedListFQName + [initName]
        let initSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(linkedListSymbol, for: initSymbol)
        symbols.setExternalLinkName("kk_emptyList", for: initSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [],
                returnType: linkedListType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: initSymbol
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
