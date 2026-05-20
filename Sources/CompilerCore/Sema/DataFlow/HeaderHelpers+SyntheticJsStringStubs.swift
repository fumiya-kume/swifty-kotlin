import Foundation

/// Synthetic Kotlin/JS `JsString` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsStringStubs(
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

        let jsStringSymbol = ensureClassSymbol(
            named: "JsString",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsStringSymbol)
        }

        let jsStringType = types.make(.classType(ClassType(
            classSymbol: jsStringSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsStringType, for: jsStringSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: jsStringSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: jsStringSymbol)
    }
}
