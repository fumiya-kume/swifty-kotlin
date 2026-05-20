import Foundation

/// Synthetic Kotlin/JS primitive wrapper class surfaces.
extension DataFlowSemaPhase {
    func registerSyntheticJsPrimitiveWrapperStubs(
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

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }

        registerJsPrimitiveWrapperClass(
            named: "JsBoolean",
            in: kotlinJsPkg,
            packageSymbol: kotlinJsPkgSymbol,
            jsAnySymbol: jsAnySymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJsPrimitiveWrapperClass(
        named name: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        jsAnySymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureClassSymbol(
            named: name,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)
    }
}
