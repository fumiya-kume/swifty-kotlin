import Foundation

/// Synthetic Kotlin/JS `JsArray<T : JsAny?>` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let jsArraySymbol = ensureClassSymbol(
            named: "JsArray",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsArraySymbol)
        }

        let typeParamName = interner.intern("T")
        let jsArrayFQName = kotlinJsPkg + [interner.intern("JsArray")]
        let typeParamFQName = jsArrayFQName + [typeParamName]
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
        symbols.setParentSymbol(jsArraySymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.nullableAnyType], for: typeParamSymbol)

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

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: jsArraySymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: jsArraySymbol)

        let arraySymbol = ensureClassSymbol(
            named: "Array",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let arrayReturnType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        registerJsArrayToArray(
            ownerSymbol: jsArraySymbol,
            ownerType: jsArrayType,
            returnType: arrayReturnType,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        registerJsArrayConstructor(
            ownerSymbol: jsArraySymbol,
            ownerType: jsArrayType,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsArrayToArray(
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
        let functionName = interner.intern("toArray")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_array_toArray"

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
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }

    private func registerJsArrayConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let externalLinkName = "kk_js_array_create"

        if let existing = symbols.lookupAll(fqName: constructorFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
                && signature.returnType == ownerType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 1
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: constructorSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
    }
}
