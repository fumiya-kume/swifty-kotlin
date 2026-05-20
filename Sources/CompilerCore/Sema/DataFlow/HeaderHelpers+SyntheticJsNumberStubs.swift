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

        registerJsNumberMember(
            ownerSymbol: jsNumberSymbol,
            ownerType: jsNumberType,
            named: "toDouble",
            returnType: types.doubleType,
            externalLinkName: "kk_js_number_toDouble",
            symbols: symbols,
            interner: interner
        )
        registerJsNumberMember(
            ownerSymbol: jsNumberSymbol,
            ownerType: jsNumberType,
            named: "toInt",
            returnType: types.intType,
            externalLinkName: "kk_js_number_toInt",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsNumberMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        named name: String,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
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
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }
}
