import Foundation

/// Synthetic Kotlin/JS `JsBigInt` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsBigIntStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let jsBigIntSymbol = ensureClassSymbol(
            named: "JsBigInt",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsBigIntSymbol)
        }

        let jsBigIntType = types.make(.classType(ClassType(
            classSymbol: jsBigIntSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsBigIntType, for: jsBigIntSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: jsBigIntSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: jsBigIntSymbol)
    }
}
