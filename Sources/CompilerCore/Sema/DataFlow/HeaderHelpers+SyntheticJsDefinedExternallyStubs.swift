import Foundation

/// Synthetic Kotlin/JS `definedExternally` placeholder property surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsDefinedExternallyStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let propertySymbol = ensureJsDefinedExternallyProperty(
            packageFQName: kotlinJsPkg,
            returnType: types.nothingType,
            symbols: symbols,
            interner: interner
        )

        if let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: propertySymbol)
        }
    }

    private func ensureJsDefinedExternallyProperty(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let propertyName = interner.intern("definedExternally")
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(returnType, for: existing)
            return existing
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setPropertyType(returnType, for: propertySymbol)
        return propertySymbol
    }
}
