import Foundation

/// Synthetic Kotlin/JS array interop surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsArrayInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinCollectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )

        let jsArray = ensureJsArrayType(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")]),
              let listTypeParamSymbol = types.nominalTypeParameterSymbols(for: listSymbol).first
        else {
            return
        }

        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol,
            nullability: .nonNull
        )))
        let listType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let jsArrayReturnType = types.make(.classType(ClassType(
            classSymbol: jsArray.symbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))

        registerListToJsArrayMember(
            listSymbol: listSymbol,
            listType: listType,
            listTypeParamSymbol: listTypeParamSymbol,
            returnType: jsArrayReturnType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsArrayType(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let jsArrayName = interner.intern("JsArray")
        let jsArrayFQName = kotlinJsPkg + [jsArrayName]
        let jsArraySymbol: SymbolID
        if let existing = symbols.lookup(fqName: jsArrayFQName),
           symbols.symbol(existing)?.kind == .class {
            jsArraySymbol = existing
        } else {
            jsArraySymbol = symbols.define(
                kind: .class,
                name: jsArrayName,
                fqName: jsArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsArraySymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = jsArrayFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
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
        let jsArrayType = types.make(.classType(ClassType(
            classSymbol: jsArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: jsArraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: jsArraySymbol)
        symbols.setPropertyType(jsArrayType, for: jsArraySymbol)

        return (jsArraySymbol, typeParamSymbol)
    }

    private func registerListToJsArrayMember(
        listSymbol: SymbolID,
        listType: TypeID,
        listTypeParamSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let listInfo = symbols.symbol(listSymbol) else {
            return
        }
        let functionName = interner.intern("toJsArray")
        let functionFQName = listInfo.fqName + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == listType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [listTypeParamSymbol]
        }) {
            symbols.setExternalLinkName("kk_list_toJsArray", for: existing)
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
        symbols.setParentSymbol(listSymbol, for: functionSymbol)
        symbols.setExternalLinkName("kk_list_toJsArray", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
    }
}
