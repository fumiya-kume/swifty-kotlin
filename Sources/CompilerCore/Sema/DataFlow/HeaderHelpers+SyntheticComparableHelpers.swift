
/// Synthetic Comparable helpers retained after the KSP-697 nominal shell migration.
/// Comparable<in T> sub-helpers for primitive compatibility.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    /// Set up primitive types to implement Comparable<Self>
    func setupPrimitiveComparableImplementations(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableSymbol: SymbolID
    ) {
        let kotlinPkg = [interner.intern("kotlin")]

        let primitiveTypeNames = ["Int", "Long", "Double", "Float", "Char", "Boolean", "UInt", "ULong", "UByte", "UShort"]

        for typeName in primitiveTypeNames {
            let primitiveSymbol = ensureClassSymbol(named: typeName, in: kotlinPkg, symbols: symbols, interner: interner)

            let primitiveType = types.make(.classType(ClassType(
                classSymbol: primitiveSymbol,
                args: [],
                nullability: .nonNull
            )))

            // Set direct supertypes for member resolution
            symbols.setDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            types.setNominalDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            symbols.setSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)
            types.setNominalSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)

            // KSP-853/KSP-904/KSP-907/KSP-910/KSP-913: Int, UByte, UInt,
            // ULong, and UShort
            // are compiler primitives, so retain only the synthetic Companion
            // anchors needed by source-backed extensions.
            if typeName == "Int" || typeName == "UByte" || typeName == "UInt" || typeName == "ULong" || typeName == "UShort" {
                ensureSyntheticPrimitiveCompanionSymbol(
                    ownerSymbol: primitiveSymbol,
                    symbols: symbols,
                    interner: interner
                )
            }
        }
    }

    private func ensureSyntheticPrimitiveCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        if symbols.companionObjectSymbol(for: ownerSymbol) != nil {
            return
        }
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        if let existing = symbols.lookupAll(fqName: companionFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == .object || symbol.kind == .class || symbol.kind == .interface
        }) {
            symbols.setParentSymbol(ownerSymbol, for: existing)
            symbols.setCompanionObjectSymbol(existing, for: ownerSymbol)
            return
        }
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
    }
}
