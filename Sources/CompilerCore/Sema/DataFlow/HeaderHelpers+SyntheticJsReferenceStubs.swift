import Foundation

/// Synthetic Kotlin/JS `JsReference<T>` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsReferenceStubs(
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

        let referenceSymbol = ensureInterfaceSymbol(
            named: "JsReference",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: referenceSymbol)
        }

        let referenceFQName = kotlinJsPkg + [interner.intern("JsReference")]
        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.lookup(fqName: referenceFQName + [typeParamName]) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: referenceFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(referenceSymbol, for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: referenceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: referenceSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let referenceType = types.make(.classType(ClassType(
            classSymbol: referenceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(referenceType, for: referenceSymbol)
    }
}
