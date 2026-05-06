import Foundation

/// Synthetic Kotlin/JS `Promise<out T>` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsPromiseStubs(
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

        let promiseName = interner.intern("Promise")
        let promiseFQName = kotlinJsPkg + [promiseName]
        let promiseSymbol: SymbolID
        if let existing = symbols.lookup(fqName: promiseFQName),
           symbols.symbol(existing)?.kind == .class {
            promiseSymbol = existing
        } else {
            promiseSymbol = symbols.define(
                kind: .class,
                name: promiseName,
                fqName: promiseFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: promiseSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = promiseFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let promiseType = types.make(.classType(ClassType(
            classSymbol: promiseSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: promiseSymbol)
        types.setNominalTypeParameterVariances([.out], for: promiseSymbol)
        symbols.setPropertyType(promiseType, for: promiseSymbol)
    }
}
