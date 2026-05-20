import Foundation

/// Synthetic Kotlin/JS `JsBoolean` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsBooleanStubs(
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

        let jsBooleanSymbol = ensureClassSymbol(
            named: "JsBoolean",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsBooleanSymbol)
        }

        let jsBooleanType = types.make(.classType(ClassType(
            classSymbol: jsBooleanSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsBooleanType, for: jsBooleanSymbol)

        registerJsBooleanToBoolean(
            ownerSymbol: jsBooleanSymbol,
            ownerType: jsBooleanType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJsBooleanToBoolean(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toBoolean")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_boolean_toBoolean"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.booleanType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: types.booleanType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }
}
