import Foundation

/// Synthetic Kotlin/JS `JsClass<T : Any>` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsClassStubs(
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

        let jsClassSymbol = ensureInterfaceSymbol(
            named: "JsClass",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsClassSymbol)
        }

        let typeParamName = interner.intern("T")
        let jsClassFQName = kotlinJsPkg + [interner.intern("JsClass")]
        let typeParamFQName = jsClassFQName + [typeParamName]
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
        symbols.setParentSymbol(jsClassSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let jsClassType = types.make(.classType(ClassType(
            classSymbol: jsClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: jsClassSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: jsClassSymbol)
        symbols.setPropertyType(jsClassType, for: jsClassSymbol)

        registerJsClassNameProperty(
            ownerSymbol: jsClassSymbol,
            propertyType: types.stringType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsClassNameProperty(
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern("name")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
            return
        }
        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }
}
