import Foundation

/// Synthetic Kotlin/JS `JsReference<T : Any>` external interface surface.
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

        let jsReferenceSymbol = ensureInterfaceSymbol(
            named: "JsReference",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsReferenceSymbol)
        }

        let typeParamName = interner.intern("T")
        let jsReferenceFQName = kotlinJsPkg + [interner.intern("JsReference")]
        let typeParamFQName = jsReferenceFQName + [typeParamName]
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
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(jsReferenceSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let jsReferenceType = types.make(.classType(ClassType(
            classSymbol: jsReferenceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: jsReferenceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: jsReferenceSymbol)
        symbols.setPropertyType(jsReferenceType, for: jsReferenceSymbol)

        registerJsReferenceGet(
            ownerSymbol: jsReferenceSymbol,
            ownerType: jsReferenceType,
            returnType: typeParamType,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsReferenceGet(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("get")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_reference_get"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 1
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
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }
}
