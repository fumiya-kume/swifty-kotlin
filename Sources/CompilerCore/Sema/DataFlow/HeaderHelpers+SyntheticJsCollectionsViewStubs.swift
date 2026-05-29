import Foundation

/// Synthetic Kotlin/JS collection view conversion surfaces.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsViewStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsCollectionsPkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsArrayViewStubs(
            jsCollectionsPkg: jsCollectionsPkg,
            collectionsPkg: collectionsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJsMapViewStubs(
            jsCollectionsPkg: jsCollectionsPkg,
            collectionsPkg: collectionsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJsSetViewStubs(
            jsCollectionsPkg: jsCollectionsPkg,
            collectionsPkg: collectionsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticJsArrayViewStubs(
        jsCollectionsPkg: [InternedString],
        collectionsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let listSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]),
              let mutableListSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableList")]),
              let jsReadonlyArraySymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsReadonlyArray")]),
              let jsArraySymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsArray")])
        else {
            return
        }

        registerSyntheticJsSingleTypeViewFunction(
            named: "asJsReadonlyArrayView",
            externalLinkName: "kk_list_asJsReadonlyArrayView",
            packageFQName: jsCollectionsPkg,
            typeParameterName: "E",
            receiverSymbol: listSymbol,
            receiverProjection: .out,
            returnSymbol: jsReadonlyArraySymbol,
            returnProjection: .out,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJsSingleTypeViewFunction(
            named: "asJsArrayView",
            externalLinkName: "kk_mutable_list_asJsArrayView",
            packageFQName: jsCollectionsPkg,
            typeParameterName: "E",
            receiverSymbol: mutableListSymbol,
            receiverProjection: .invariant,
            returnSymbol: jsArraySymbol,
            returnProjection: .invariant,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticJsMapViewStubs(
        jsCollectionsPkg: [InternedString],
        collectionsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let mapSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Map")]),
              let mutableMapSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableMap")]),
              let jsReadonlyMapSymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsReadonlyMap")]),
              let jsMapSymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsMap")])
        else {
            return
        }

        registerSyntheticJsMapViewFunction(
            named: "asJsReadonlyMapView",
            externalLinkName: "kk_map_asJsReadonlyMapView",
            packageFQName: jsCollectionsPkg,
            receiverSymbol: mapSymbol,
            receiverKeyProjection: .invariant,
            receiverValueProjection: .out,
            returnSymbol: jsReadonlyMapSymbol,
            returnKeyProjection: .invariant,
            returnValueProjection: .out,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJsMapViewFunction(
            named: "asJsMapView",
            externalLinkName: "kk_mutable_map_asJsMapView",
            packageFQName: jsCollectionsPkg,
            receiverSymbol: mutableMapSymbol,
            receiverKeyProjection: .invariant,
            receiverValueProjection: .invariant,
            returnSymbol: jsMapSymbol,
            returnKeyProjection: .invariant,
            returnValueProjection: .invariant,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticJsSetViewStubs(
        jsCollectionsPkg: [InternedString],
        collectionsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let setSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]),
              let mutableSetSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableSet")]),
              let jsReadonlySetSymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsReadonlySet")]),
              let jsSetSymbol = symbols.lookup(fqName: jsCollectionsPkg + [interner.intern("JsSet")])
        else {
            return
        }

        registerSyntheticJsSingleTypeViewFunction(
            named: "asJsReadonlySetView",
            externalLinkName: "kk_set_asJsReadonlySetView",
            packageFQName: jsCollectionsPkg,
            typeParameterName: "E",
            receiverSymbol: setSymbol,
            receiverProjection: .out,
            returnSymbol: jsReadonlySetSymbol,
            returnProjection: .out,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJsSingleTypeViewFunction(
            named: "asJsSetView",
            externalLinkName: "kk_mutable_set_asJsSetView",
            packageFQName: jsCollectionsPkg,
            typeParameterName: "E",
            receiverSymbol: mutableSetSymbol,
            receiverProjection: .invariant,
            returnSymbol: jsSetSymbol,
            returnProjection: .invariant,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticJsSingleTypeViewFunction(
        named name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        typeParameterName: String,
        receiverSymbol: SymbolID,
        receiverProjection: SyntheticJsTypeProjection,
        returnSymbol: SymbolID,
        returnProjection: SyntheticJsTypeProjection,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let typeParamSymbol = ensureSyntheticJsViewTypeParameter(
            named: typeParameterName,
            ownerFQName: functionFQName,
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [receiverProjection.makeArgument(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: returnSymbol,
            args: [returnProjection.makeArgument(typeParamType)],
            nullability: .nonNull
        )))

        registerSyntheticJsCollectionsViewFunction(
            named: name,
            packageFQName: packageFQName,
            receiverType: receiverType,
            returnType: returnType,
            typeParameterSymbols: [typeParamSymbol],
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsMapViewFunction(
        named name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        receiverSymbol: SymbolID,
        receiverKeyProjection: SyntheticJsTypeProjection,
        receiverValueProjection: SyntheticJsTypeProjection,
        returnSymbol: SymbolID,
        returnKeyProjection: SyntheticJsTypeProjection,
        returnValueProjection: SyntheticJsTypeProjection,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let keyTypeParamSymbol = ensureSyntheticJsViewTypeParameter(
            named: "K",
            ownerFQName: functionFQName,
            symbols: symbols,
            interner: interner
        )
        let valueTypeParamSymbol = ensureSyntheticJsViewTypeParameter(
            named: "V",
            ownerFQName: functionFQName,
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [
                receiverKeyProjection.makeArgument(keyType),
                receiverValueProjection.makeArgument(valueType),
            ],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: returnSymbol,
            args: [
                returnKeyProjection.makeArgument(keyType),
                returnValueProjection.makeArgument(valueType),
            ],
            nullability: .nonNull
        )))

        registerSyntheticJsCollectionsViewFunction(
            named: name,
            packageFQName: packageFQName,
            receiverType: receiverType,
            returnType: returnType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticJsViewTypeParameter(
        named name: String,
        ownerFQName: [InternedString],
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
        symbols.insertFlags([.synthetic], for: typeParamSymbol)
        return typeParamSymbol
    }

    private func registerSyntheticJsCollectionsViewFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        typeParameterSymbols: [SymbolID],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) {
            symbols.insertFlags([.synthetic], for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendSyntheticJsCollectionsViewAnnotation(to: existing, symbols: symbols)
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(existing, for: typeParameterSymbol)
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendSyntheticJsCollectionsViewAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func appendSyntheticJsCollectionsViewAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.collections.ExperimentalJsCollectionsApi"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}

private enum SyntheticJsTypeProjection {
    case invariant
    case out

    func makeArgument(_ type: TypeID) -> TypeArg {
        switch self {
        case .invariant:
            return .invariant(type)
        case .out:
            return .out(type)
        }
    }
}
