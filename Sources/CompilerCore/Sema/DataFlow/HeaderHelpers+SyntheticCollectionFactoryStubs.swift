
/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
/// bootstrap symbols for the `kotlin.collections` factory functions.
///
/// The collection type aliases (`ArrayList` / `HashSet` / `LinkedHashMap`),
/// the source-backed `HashMap` class, and the concrete `LinkedHashSet` class
/// that used to be registered here are declared by
/// `Stdlib/kotlin/collections/CollectionAliases.kt`.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    /// Register bootstrap symbols for collection factory functions while the
    /// bundled CollectionFactories.kt source is being type-checked. The
    /// bundled declaration index is used to skip functions that are already
    /// provided by Kotlin source so they do not duplicate source declarations
    /// in the symbol table.
    func registerSyntheticCollectionFactoryStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg)

        func register(
            name: String,
            typeParameterNames: [String],
            isVararg: Bool,
            externalLinkName: String
        ) {
            let functionFQName = kotlinCollectionsPkg + [interner.intern(name)]
            let typeParameterSymbols = typeParameterNames.map { rawName in
                let nameID = interner.intern(rawName)
                if let existing = symbols.lookup(fqName: functionFQName + [nameID]) {
                    return existing
                }
                return symbols.define(
                    kind: .typeParameter,
                    name: nameID,
                    fqName: functionFQName + [nameID],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            let parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)] = isVararg
                ? [("elements", types.anyType, false, true)]
                : []
            let functionSymbol = registerSyntheticFunctionStub(
                named: name,
                ownerFQName: kotlinCollectionsPkg,
                parentSymbol: packageSymbol,
                parameters: parameters,
                returnType: types.anyType,
                externalLinkName: externalLinkName,
                typeParameterSymbols: typeParameterSymbols,
                bundledIndex: bundledIndex,
                skipStats: skipStats,
                symbols: symbols,
                interner: interner
            )
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }
        }

        register(name: "emptyList", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_emptyList")
        register(name: "listOf", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_emptyList")
        register(name: "listOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_list_of")
        register(name: "arrayListOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_array_list_of")
        register(name: "mutableListOf", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_list_of")
        register(name: "mutableListOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_list_of")

        register(name: "emptySet", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_emptySet")
        register(name: "setOf", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_emptySet")
        register(name: "setOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_set_of")
        register(name: "setOfNotNull", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_set_of_not_null")
        register(name: "mutableSetOf", typeParameterNames: ["T"], isVararg: false, externalLinkName: "__kk_set_of")
        register(name: "mutableSetOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_set_of")
        register(name: "hashSetOf", typeParameterNames: ["T"], isVararg: true, externalLinkName: "__kk_hash_set_of")

        register(name: "emptyMap", typeParameterNames: ["K", "V"], isVararg: false, externalLinkName: "__kk_emptyMap")
        register(name: "mapOf", typeParameterNames: ["K", "V"], isVararg: false, externalLinkName: "__kk_emptyMap")
        register(name: "mapOf", typeParameterNames: ["K", "V"], isVararg: true, externalLinkName: "__kk_map_of")
        register(name: "mutableMapOf", typeParameterNames: ["K", "V"], isVararg: false, externalLinkName: "__kk_map_of")
        register(name: "mutableMapOf", typeParameterNames: ["K", "V"], isVararg: true, externalLinkName: "__kk_map_of")
        register(name: "hashMapOf", typeParameterNames: ["K", "V"], isVararg: true, externalLinkName: "__kk_map_of")
    }
}
