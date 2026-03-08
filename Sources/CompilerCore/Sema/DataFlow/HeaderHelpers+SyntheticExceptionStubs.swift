import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeExceptionSymbol = ensureClassSymbol(
            named: "RuntimeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let uninitializedSymbol = ensureClassSymbol(
            named: "UninitializedPropertyAccessException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let nullPointerSymbol = ensureClassSymbol(
            named: "NullPointerException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let numberFormatSymbol = ensureClassSymbol(
            named: "NumberFormatException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        symbols.setDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)

        for symbol in [
            throwableSymbol,
            exceptionSymbol,
            runtimeExceptionSymbol,
            uninitializedSymbol,
            nullPointerSymbol,
            numberFormatSymbol,
            cancellationSymbol,
        ] {
            let type = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            symbols.setPropertyType(type, for: symbol)
        }
    }
}
