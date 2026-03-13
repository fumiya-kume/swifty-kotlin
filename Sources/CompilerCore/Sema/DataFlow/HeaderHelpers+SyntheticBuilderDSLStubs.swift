import Foundation

/// Synthetic stdlib stubs for buildList (STDLIB-070), buildMap (STDLIB-071), and related builder DSL functions.
/// buildList<E>(builderAction: MutableList<E>.() -> Unit): List<E>
/// buildMap<K,V>(builderAction: MutableMap<K,V>.() -> Unit): Map<K,V>
/// Lowering rewrites these to kk_build_* runtime calls.
extension DataFlowSemaPhase {
    func registerSyntheticBuilderDSLStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinCollectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        guard symbols.lookup(fqName: kotlinCollectionsPkg) != nil else {
            return
        }
        let listName = interner.intern("List")
        let mutableListName = interner.intern("MutableList")
        let mapName = interner.intern("Map")
        let mutableMapName = interner.intern("MutableMap")
        let setName = interner.intern("Set")
        let mutableSetName = interner.intern("MutableSet")
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [listName]),
              let mutableListSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableListName]),
              let mapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mapName]),
              let mutableMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableMapName]),
              let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [setName]),
              let mutableSetSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableSetName])
        else {
            return
        }

        registerSyntheticBuildListStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol
        )
        registerSyntheticBuildMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapSymbol: mapSymbol,
            mutableMapSymbol: mutableMapSymbol
        )
        registerSyntheticBuildSetStub(symbols: symbols, types: types, interner: interner, kotlinCollectionsPkg: kotlinCollectionsPkg, setSymbol: setSymbol, mutableSetSymbol: mutableSetSymbol)
    }

    private func registerSyntheticBuildListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        let buildListName = interner.intern("buildList")
        let buildListFQName = kotlinCollectionsPkg + [buildListName]
        let eName = interner.intern("E")
        registerSyntheticBuildListOverload(
            named: buildListName,
            fqName: buildListFQName,
            packageFQName: kotlinCollectionsPkg,
            typeParameterName: eName,
            extraParameterTypes: [],
            extraParameterNames: [],
            externalLinkName: nil,
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticBuildListOverload(
            named: buildListName,
            fqName: buildListFQName,
            packageFQName: kotlinCollectionsPkg,
            typeParameterName: eName,
            extraParameterTypes: [types.intType],
            extraParameterNames: ["capacity"],
            externalLinkName: "kk_build_list_with_capacity",
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticBuildListOverload(
        named buildListName: InternedString,
        fqName buildListFQName: [InternedString],
        packageFQName: [InternedString],
        typeParameterName: InternedString,
        extraParameterTypes: [TypeID],
        extraParameterNames: [String],
        externalLinkName: String?,
        listSymbol: SymbolID,
        mutableListSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard extraParameterTypes.count == extraParameterNames.count else {
            return
        }
        let parameterCount = extraParameterTypes.count + 1
        let alreadyDefined = symbols.lookupAll(fqName: buildListFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == parameterCount
                && signature.typeParameterSymbols.count == 1
        }
        if alreadyDefined {
            return
        }

        let eFQName = buildListFQName + [typeParameterName]
        let eSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParameterName,
            fqName: eFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let eType = types.make(.typeParam(TypeParamType(symbol: eSymbol, nullability: .nonNull)))
        let mutableListOfEType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(eType)],
            nullability: .nonNull
        )))
        let listOfEType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(eType)],
            nullability: .nonNull
        )))
        let builderActionType = types.make(.functionType(FunctionType(
            receiver: mutableListOfEType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let buildListSymbol = symbols.define(
            kind: .function,
            name: buildListName,
            fqName: buildListFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: buildListSymbol)
        }
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: buildListSymbol)
        }
        symbols.setParentSymbol(buildListSymbol, for: eSymbol)

        let parameterNames = extraParameterNames + ["builderAction"]
        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterNames.count)
        for parameterName in parameterNames {
            let parameterNameID = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterNameID,
                fqName: buildListFQName + [parameterNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(buildListSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: extraParameterTypes + [builderActionType],
                returnType: listOfEType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: [eSymbol],
                classTypeParameterCount: 0
            ),
            for: buildListSymbol
        )
    }

    private func registerSyntheticBuildSetStub(symbols: SymbolTable, types: TypeSystem, interner: StringInterner, kotlinCollectionsPkg: [InternedString], setSymbol: SymbolID, mutableSetSymbol: SymbolID) {
        let buildSetName = interner.intern("buildSet")
        let buildSetFQName = kotlinCollectionsPkg + [buildSetName]
        let existingBuildSet = symbols.lookupAll(fqName: buildSetFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID), symbol.kind == .function, let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes.count == 1 && signature.typeParameterSymbols.count == 1 && signature.receiverType == nil
        }
        if existingBuildSet { return }
        let eName = interner.intern("E")
        let eSymbol = symbols.define(kind: .typeParameter, name: eName, fqName: buildSetFQName + [eName], declSite: nil, visibility: .private, flags: [])
        let eType = types.make(.typeParam(TypeParamType(symbol: eSymbol, nullability: .nonNull)))
        let mutableSetOfEType = types.make(.classType(ClassType(classSymbol: mutableSetSymbol, args: [.invariant(eType)], nullability: .nonNull)))
        let setOfEType = types.make(.classType(ClassType(classSymbol: setSymbol, args: [.out(eType)], nullability: .nonNull)))
        let builderActionType = types.make(.functionType(FunctionType(receiver: mutableSetOfEType, params: [], returnType: types.unitType, isSuspend: false, nullability: .nonNull)))
        let builderActionName = interner.intern("builderAction")
        let builderActionSymbol = symbols.define(kind: .valueParameter, name: builderActionName, fqName: buildSetFQName + [builderActionName], declSite: nil, visibility: .private, flags: [.synthetic])
        let buildSetSymbol = symbols.define(kind: .function, name: buildSetName, fqName: buildSetFQName, declSite: nil, visibility: .public, flags: [.synthetic])
        if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) { symbols.setParentSymbol(packageSymbol, for: buildSetSymbol) }
        symbols.setParentSymbol(buildSetSymbol, for: eSymbol)
        symbols.setParentSymbol(buildSetSymbol, for: builderActionSymbol)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [builderActionType], returnType: setOfEType, isSuspend: false, valueParameterSymbols: [builderActionSymbol], valueParameterHasDefaultValues: [false], valueParameterIsVararg: [false], typeParameterSymbols: [eSymbol], classTypeParameterCount: 0), for: buildSetSymbol)
    }

    private func registerSyntheticBuildMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapSymbol: SymbolID,
        mutableMapSymbol: SymbolID
    ) {
        let buildMapName = interner.intern("buildMap")
        let buildMapFQName = kotlinCollectionsPkg + [buildMapName]
        let existingBuildMap = symbols.lookupAll(fqName: buildMapFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 2
                && signature.receiverType == nil
        }
        if existingBuildMap {
            return
        }

        let kName = interner.intern("K")
        let vName = interner.intern("V")
        let kFQName = buildMapFQName + [kName]
        let vFQName = buildMapFQName + [vName]
        let kSymbol = symbols.define(
            kind: .typeParameter,
            name: kName,
            fqName: kFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let vSymbol = symbols.define(
            kind: .typeParameter,
            name: vName,
            fqName: vFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let kType = types.make(.typeParam(TypeParamType(symbol: kSymbol, nullability: .nonNull)))
        let vType = types.make(.typeParam(TypeParamType(symbol: vSymbol, nullability: .nonNull)))

        let mutableMapOfKVType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(kType), .invariant(vType)],
            nullability: .nonNull
        )))
        let mapOfKVType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(kType), .out(vType)],
            nullability: .nonNull
        )))

        let builderActionType = types.make(.functionType(FunctionType(
            receiver: mutableMapOfKVType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let builderActionName = interner.intern("builderAction")
        let builderActionSymbol = symbols.define(
            kind: .valueParameter,
            name: builderActionName,
            fqName: buildMapFQName + [builderActionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let buildMapSymbol = symbols.define(
            kind: .function,
            name: buildMapName,
            fqName: buildMapFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) {
            symbols.setParentSymbol(packageSymbol, for: buildMapSymbol)
        }
        symbols.setParentSymbol(buildMapSymbol, for: kSymbol)
        symbols.setParentSymbol(buildMapSymbol, for: vSymbol)
        symbols.setParentSymbol(buildMapSymbol, for: builderActionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [builderActionType],
                returnType: mapOfKVType,
                isSuspend: false,
                valueParameterSymbols: [builderActionSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [kSymbol, vSymbol],
                classTypeParameterCount: 0
            ),
            for: buildMapSymbol
        )
    }
}
