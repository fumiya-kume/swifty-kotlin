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
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [listName]),
              let mutableListSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableListName]),
              let mapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mapName]),
              let mutableMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableMapName])
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
        let existingBuildList = symbols.lookupAll(fqName: buildListFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
                && signature.receiverType == nil
        }
        if existingBuildList {
            return
        }

        let eName = interner.intern("E")
        let eFQName = buildListFQName + [eName]
        let eSymbol = symbols.define(
            kind: .typeParameter,
            name: eName,
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

        let builderActionName = interner.intern("builderAction")
        let builderActionSymbol = symbols.define(
            kind: .valueParameter,
            name: builderActionName,
            fqName: buildListFQName + [builderActionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let buildListSymbol = symbols.define(
            kind: .function,
            name: buildListName,
            fqName: buildListFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) {
            symbols.setParentSymbol(packageSymbol, for: buildListSymbol)
        }
        symbols.setParentSymbol(buildListSymbol, for: eSymbol)
        symbols.setParentSymbol(buildListSymbol, for: builderActionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [builderActionType],
                returnType: listOfEType,
                isSuspend: false,
                valueParameterSymbols: [builderActionSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [eSymbol],
                classTypeParameterCount: 0
            ),
            for: buildListSymbol
        )
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
