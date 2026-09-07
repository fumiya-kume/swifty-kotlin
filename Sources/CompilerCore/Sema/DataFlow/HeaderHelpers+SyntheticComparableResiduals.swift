// KSP-697: compiler-side Comparable residuals.
//
// The nominal Comparable<in T> declaration is bundled Kotlin source. This
// residual keeps compareTo, primitive conformances, and range bounds available
// until their metadata and lowering constraints can be removed independently.
extension DataFlowSemaPhase {
    func registerSyntheticComparableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let comparableName = interner.intern("Comparable")
        let comparableFQName = kotlinPkg + [comparableName]
        let comparableSymbol: SymbolID = if let existing = symbols.lookup(fqName: comparableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: comparableName,
                fqName: comparableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Store in TypeSystem for use in isSubtype.
        types.comparableInterfaceSymbol = comparableSymbol
        types.setNominalTypeParameterVariances([.in], for: comparableSymbol)

        registerOpenEndRangeComparableUpperBound(
            comparableSymbol: comparableSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        setupPrimitiveComparableImplementations(
            symbols: symbols,
            types: types,
            interner: interner,
            comparableSymbol: comparableSymbol
        )
        patchSyntheticClosedRangeTypeParameterUpperBound(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
