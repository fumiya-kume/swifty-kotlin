import Foundation

/// Synthetic Kotlin/JS collections `JsReadonlySet<E>.toSet()` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlySetToSetStubs(
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
        let readonlySet = ensureJsReadonlySetForToSet(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let setSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]) else {
            return
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: readonlySet.typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlySet.symbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        registerJsReadonlySetToSetMember(
            ownerSymbol: readonlySet.symbol,
            ownerType: receiverType,
            returnType: returnType,
            typeParamSymbol: readonlySet.typeParameterSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureJsReadonlySetForToSet(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlySet")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlySet",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsReadonlySetToSetAnnotation(to: interfaceSymbol, symbols: symbols)

        let typeParamName = interner.intern("E")
        let typeParamFQName = interfaceFQName + [typeParamName]
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
        symbols.setParentSymbol(interfaceSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, typeParamSymbol)
    }

    private func registerJsReadonlySetToSetMember(
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
        let functionName = interner.intern("toSet")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_set_toSet"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 1
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsCollectionsReadonlySetToSetAnnotation(to: existing, symbols: symbols)
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
        appendJsCollectionsReadonlySetToSetAnnotation(to: functionSymbol, symbols: symbols)
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
    }

    private func appendJsCollectionsReadonlySetToSetAnnotation(
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
