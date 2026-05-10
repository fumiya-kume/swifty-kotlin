import Foundation

/// Synthetic Kotlin/JS `RegExpMatch` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsRegExpMatchStubs(
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

        let regExpMatchSymbol = ensureInterfaceSymbol(
            named: "RegExpMatch",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: regExpMatchSymbol)
        }

        let regExpMatchType = types.make(.classType(ClassType(
            classSymbol: regExpMatchSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(regExpMatchType, for: regExpMatchSymbol)

        registerJsRegExpMatchProperty(
            named: "index",
            ownerSymbol: regExpMatchSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerJsRegExpMatchProperty(
            named: "input",
            ownerSymbol: regExpMatchSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )
        registerJsRegExpMatchProperty(
            named: "length",
            ownerSymbol: regExpMatchSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsRegExpMatchProperty(
        named name: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbol in
            symbols.symbol(symbol)?.kind == .property
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setPropertyType(returnType, for: existing)
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
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
