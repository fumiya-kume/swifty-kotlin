import Foundation

/// Synthetic Kotlin/JS `JsException` class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsExceptionSymbol = ensureClassSymbol(
            named: "JsException",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: jsExceptionSymbol)
        }

        let kotlinPkg = [interner.intern("kotlin")]
        guard let throwableSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Throwable")]) else {
            return
        }
        symbols.setDirectSupertypes([throwableSymbol], for: jsExceptionSymbol)
        types.setNominalDirectSupertypes([throwableSymbol], for: jsExceptionSymbol)

        let jsExceptionType = types.make(.classType(ClassType(
            classSymbol: jsExceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsExceptionType, for: jsExceptionSymbol)
    }
}
