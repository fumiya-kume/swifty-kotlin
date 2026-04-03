import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticJsInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsCollectionsPkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let kotlinCollectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )
        let kotlinReflectFullPkg = ensurePackage(
            path: ["kotlin", "reflect", "full"],
            symbols: symbols,
            interner: interner
        )

        for annotationName in [
            "ExperimentalJsExport",
            "ExperimentalJsFileName",
            "ExperimentalJsStatic",
            "ExperimentalJsReflectionCreateInstance",
        ] {
            _ = ensureAnnotationClassSymbol(
                named: annotationName,
                in: kotlinJsPkg,
                symbols: symbols,
                interner: interner
            )
        }

        _ = ensureAnnotationClassSymbol(
            named: "ExperimentalJsCollectionsApi",
            in: kotlinJsCollectionsPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsCollectionViewStub(
            name: "asJsReadonlyArrayView",
            externalLinkName: "kk_js_readonly_array_view",
            packageFQName: kotlinJsCollectionsPkg,
            receiverType: collectionType(
                named: "List",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            returnType: collectionType(
                named: "List",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsCollectionViewStub(
            name: "asJsReadonlyMapView",
            externalLinkName: "kk_js_readonly_map_view",
            packageFQName: kotlinJsCollectionsPkg,
            receiverType: collectionType(
                named: "Map",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            returnType: collectionType(
                named: "Map",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsCollectionViewStub(
            name: "asJsMapView",
            externalLinkName: "kk_js_map_view",
            packageFQName: kotlinJsCollectionsPkg,
            receiverType: collectionType(
                named: "MutableMap",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            returnType: collectionType(
                named: "MutableMap",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsCollectionViewStub(
            name: "asJsReadonlySetView",
            externalLinkName: "kk_js_readonly_set_view",
            packageFQName: kotlinJsCollectionsPkg,
            receiverType: collectionType(
                named: "Set",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            returnType: collectionType(
                named: "Set",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJsCollectionViewStub(
            name: "asJsSetView",
            externalLinkName: "kk_js_set_view",
            packageFQName: kotlinJsCollectionsPkg,
            receiverType: collectionType(
                named: "MutableSet",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            returnType: collectionType(
                named: "MutableSet",
                in: kotlinCollectionsPkg,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        let createInstanceReceiver = types.makeKClassType(argument: types.anyType)
        registerSyntheticCreateInstanceStub(
            packageFQName: kotlinReflectPkg,
            receiverType: createInstanceReceiver,
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCreateInstanceStub(
            packageFQName: kotlinReflectFullPkg,
            receiverType: createInstanceReceiver,
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
    }

    private func collectionType(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let symbol = ensureInterfaceSymbol(
            named: name,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticJsCollectionViewStub(
        name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let internedName = interner.intern(name)
        let fqName = packageFQName + [internedName]
        let functionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            functionSymbol = existing
        } else {
            functionSymbol = symbols.define(
                kind: .function,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol = symbols.lookup(fqName: packageFQName), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }

    private func registerSyntheticCreateInstanceStub(
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let name = interner.intern("createInstance")
        let fqName = packageFQName + [name]
        let functionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            functionSymbol = existing
        } else {
            functionSymbol = symbols.define(
                kind: .function,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol = symbols.lookup(fqName: packageFQName), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName("kk_kclass_create_instance", for: functionSymbol)
    }
}
