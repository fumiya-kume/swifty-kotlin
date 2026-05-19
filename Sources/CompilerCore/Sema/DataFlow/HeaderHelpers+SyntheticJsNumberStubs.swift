import Foundation

/// Synthetic Kotlin/JS `JsNumber` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsNumberStubs(
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

        let jsNumberSymbol = ensureClassSymbol(
            named: "JsNumber",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsNumberSymbol)
        }

        let jsNumberType = types.make(.classType(ClassType(
            classSymbol: jsNumberSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsNumberType, for: jsNumberSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: jsNumberSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: jsNumberSymbol)
    }
}
