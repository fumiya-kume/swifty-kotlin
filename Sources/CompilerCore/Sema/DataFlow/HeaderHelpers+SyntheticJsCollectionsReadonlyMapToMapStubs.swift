import Foundation

/// Synthetic Kotlin/JS collections `JsReadonlyMap<K, V>.toMap()` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlyMapToMapStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlyMap = ensureJsReadonlyMapForToMap(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let mapSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Map")]) else {
            return
        }

        let keyType = types.make(.typeParam(TypeParamType(
            symbol: readonlyMap.keyTypeParameterSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: readonlyMap.valueTypeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlyMap.symbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        registerJsReadonlyMapToMapMember(
            ownerSymbol: readonlyMap.symbol,
            ownerType: receiverType,
            returnType: returnType,
            keyTypeParamSymbol: readonlyMap.keyTypeParameterSymbol,
            valueTypeParamSymbol: readonlyMap.valueTypeParameterSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureJsReadonlyMapForToMap(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, keyTypeParameterSymbol: SymbolID, valueTypeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlyMap")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlyMap",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsReadonlyMapToMapAnnotation(to: interfaceSymbol, symbols: symbols)

        let keyTypeParamSymbol = ensureJsReadonlyMapToMapTypeParameter(
            named: "K",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
        let valueTypeParamSymbol = ensureJsReadonlyMapToMapTypeParameter(
            named: "V",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, keyTypeParamSymbol, valueTypeParamSymbol)
    }

    private func ensureJsReadonlyMapToMapTypeParameter(
        named name: String,
        in ownerFQName: [InternedString],
        owner: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeParamName = interner.intern(name)
        let typeParamFQName = ownerFQName + [typeParamName]
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
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(owner, for: typeParamSymbol)
        return typeParamSymbol
    }

    private func registerJsReadonlyMapToMapMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toMap")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_map_toMap"
        let typeParameterSymbols = [keyTypeParamSymbol, valueTypeParamSymbol]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == 2
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsCollectionsReadonlyMapToMapAnnotation(to: existing, symbols: symbols)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsCollectionsReadonlyMapToMapAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 2
            ),
            for: functionSymbol
        )
    }

    private func appendJsCollectionsReadonlyMapToMapAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalJsCollectionsApi"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
