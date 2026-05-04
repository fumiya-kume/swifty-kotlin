import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Map<K,V>, Map.Entry<K,V>, and MutableMap<K,V> interfaces with higher-order members.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> (mapSymbol: SymbolID, keyTypeParamSymbol: SymbolID, valueTypeParamSymbol: SymbolID) {
        let mapName = interner.intern("Map")
        let mapFQName = kotlinCollectionsPkg + [mapName]
        let mapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mapName,
                fqName: mapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: mapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: mapSymbol)

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        let getName = interner.intern("get")
        let getFQName = mapFQName + [getName]
        if symbols.lookup(fqName: getFQName) == nil {
            let getSymbol = symbols.define(
                kind: .function,
                name: getName,
                fqName: getFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(mapSymbol, for: getSymbol)
            symbols.setExternalLinkName("kk_map_get", for: getSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [keyType],
                    returnType: types.makeNullable(valueType),
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: getSymbol
            )
        }

        let containsKeyName = interner.intern("containsKey")
        let containsKeyFQName = mapFQName + [containsKeyName]
        if symbols.lookup(fqName: containsKeyFQName) == nil {
            let containsKeySymbol = symbols.define(
                kind: .function,
                name: containsKeyName,
                fqName: containsKeyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapSymbol, for: containsKeySymbol)
            symbols.setExternalLinkName("kk_map_contains_key", for: containsKeySymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [keyType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: containsKeySymbol
            )
        }

        let containsValueName = interner.intern("containsValue")
        let containsValueFQName = mapFQName + [containsValueName]
        if symbols.lookup(fqName: containsValueFQName) == nil {
            let containsValueSymbol = symbols.define(
                kind: .function,
                name: containsValueName,
                fqName: containsValueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapSymbol, for: containsValueSymbol)
            symbols.setExternalLinkName("kk_map_contains_value", for: containsValueSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [valueType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: containsValueSymbol
            )
        }

        return (mapSymbol, keyParamSymbol, valueParamSymbol)
    }

    func registerMapToMutableMapMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let toMutableMapName = interner.intern("toMutableMap")
        let toMutableMapFQName = mapFQName + [toMutableMapName]
        guard symbols.lookup(fqName: toMutableMapFQName) == nil else { return }
        guard let mutableMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("MutableMap")]) else {
            return
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: toMutableMapName,
            fqName: toMutableMapFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_map_to_mutable_map", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.invariant(keyType), .invariant(valueType)],
                    nullability: .nonNull
                ))),
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
                classTypeParameterCount: 2
            ),
            for: memberSymbol
        )
    }

    func registerMapHigherOrderMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let entryType = registerSyntheticMapEntryStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            keyTypeParamSymbol: keyTypeParamSymbol,
            valueTypeParamSymbol: valueTypeParamSymbol
        )
        let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
            ?? symbols.lookupByShortName(interner.intern("Pair")).first
        let pairType = if let pairSymbol {
            types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(keyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")])
            ?? symbols.lookupByShortName(interner.intern("List")).first
        let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Set")])
            ?? symbols.lookupByShortName(interner.intern("Set")).first
        let mutableMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("MutableMap")])
            ?? symbols.lookupByShortName(interner.intern("MutableMap")).first

        func registerMember(
            name: String,
            externalLinkName: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            typeParameterSymbols: [SymbolID],
            flags: SymbolFlags = [.synthetic]
        ) {
            let memberName = interner.intern(name)
            let memberFQName = mapFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    typeParameterSymbols: typeParameterSymbols,
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        if let setSymbol {
            let keysType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(keyType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "keys",
                externalLinkName: "kk_map_keys",
                parameterTypes: [],
                returnType: keysType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )

            let entriesType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(entryType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "entries",
                externalLinkName: "kk_map_entries",
                parameterTypes: [],
                returnType: entriesType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )
        }

        let valuesType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(valueType)],
            nullability: .nonNull
        )))
        registerMember(
            name: "values",
            externalLinkName: "kk_map_values",
            parameterTypes: [],
            returnType: valuesType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        let forEachLambdaType = types.make(.functionType(FunctionType(
            params: [entryType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "forEach",
            externalLinkName: "kk_map_forEach",
            parameterTypes: [forEachLambdaType],
            returnType: types.unitType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        if let listSymbol {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapFQName + [interner.intern("map"), rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let mapLambdaType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "map",
                externalLinkName: "kk_map_map",
                parameterTypes: [mapLambdaType],
                returnType: listRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )

            // mapNotNull: (Map.Entry<K,V>) -> R? → List<R>
            let mapNotNullRName = interner.intern("R")
            let mapNotNullRSymbol = symbols.define(
                kind: .typeParameter,
                name: mapNotNullRName,
                fqName: mapFQName + [interner.intern("mapNotNull"), mapNotNullRName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let mapNotNullRType = types.make(.typeParam(TypeParamType(symbol: mapNotNullRSymbol, nullability: .nonNull)))
            let mapNotNullLambdaType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: types.make(.typeParam(TypeParamType(symbol: mapNotNullRSymbol, nullability: .nullable))),
                isSuspend: false,
                nullability: .nonNull
            )))
            let listMapNotNullRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(mapNotNullRType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "mapNotNull",
                externalLinkName: "kk_map_mapNotNull",
                parameterTypes: [mapNotNullLambdaType],
                returnType: listMapNotNullRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, mapNotNullRSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapValuesName = interner.intern("mapValues")
        let mapValuesFQName = mapFQName + [mapValuesName]
        if symbols.lookup(fqName: mapValuesFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapValuesFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let mapRType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(keyType), .out(rType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "mapValues",
                externalLinkName: "kk_map_mapValues",
                parameterTypes: [transformType],
                returnType: mapRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapKeysName = interner.intern("mapKeys")
        let mapKeysFQName = mapFQName + [mapKeysName]
        if symbols.lookup(fqName: mapKeysFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapKeysFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let mapRType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(rType), .out(valueType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "mapKeys",
                externalLinkName: "kk_map_mapKeys",
                parameterTypes: [transformType],
                returnType: mapRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapKeysToName = interner.intern("mapKeysTo")
        let mapKeysToFQName = mapFQName + [mapKeysToName]
        if symbols.lookup(fqName: mapKeysToFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapKeysToFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let destinationType = if let mutableMapSymbol {
                types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.in(rType), .in(valueType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            registerMember(
                name: "mapKeysTo",
                externalLinkName: "kk_map_mapKeysTo",
                parameterTypes: [destinationType, transformType],
                returnType: destinationType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapValuesToName = interner.intern("mapValuesTo")
        let mapValuesToFQName = mapFQName + [mapValuesToName]
        if symbols.lookup(fqName: mapValuesToFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapValuesToFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let destinationType = if let mutableMapSymbol {
                types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.in(keyType), .in(rType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            registerMember(
                name: "mapValuesTo",
                externalLinkName: "kk_map_mapValuesTo",
                parameterTypes: [destinationType, transformType],
                returnType: destinationType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let filterLambdaType = types.make(.functionType(FunctionType(
            params: [entryType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let filterKeyLambdaType = types.make(.functionType(FunctionType(
            params: [keyType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let filterValueLambdaType = types.make(.functionType(FunctionType(
            params: [valueType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "filter",
            externalLinkName: "kk_map_filter",
            parameterTypes: [filterLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterNot",
            externalLinkName: "kk_map_filterNot",
            parameterTypes: [filterLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterKeys",
            externalLinkName: "kk_map_filterKeys",
            parameterTypes: [filterKeyLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterValues",
            externalLinkName: "kk_map_filterValues",
            parameterTypes: [filterValueLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "count",
            externalLinkName: "kk_map_count",
            parameterTypes: [filterLambdaType],
            returnType: types.intType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "any",
            externalLinkName: "kk_map_any",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "all",
            externalLinkName: "kk_map_all",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "none",
            externalLinkName: "kk_map_none",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "getValue",
            externalLinkName: "kk_map_getValue",
            parameterTypes: [keyType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        registerMember(
            name: "getOrDefault",
            externalLinkName: "kk_map_getOrDefault",
            parameterTypes: [keyType, valueType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        registerMember(
            name: "plus",
            externalLinkName: "kk_map_plus",
            parameterTypes: [pairType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        registerMember(
            name: "minus",
            externalLinkName: "kk_map_minus",
            parameterTypes: [keyType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        let getOrElseLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "getOrElse",
            externalLinkName: "kk_map_getOrElse",
            parameterTypes: [keyType, getOrElseLambdaType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        let withDefaultLambdaType = types.make(.functionType(FunctionType(
            params: [keyType],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "withDefault",
            externalLinkName: "kk_map_withDefault",
            parameterTypes: [withDefaultLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        if let listSymbol {
            let toListType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(pairType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "toList",
                externalLinkName: "kk_map_toList",
                parameterTypes: [],
                returnType: toListType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )

            let rName = interner.intern("R")
            let flatMapRSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapFQName + [interner.intern("flatMap"), rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let flatMapRType = types.make(.typeParam(TypeParamType(symbol: flatMapRSymbol, nullability: .nullable)))
            let flatMapLambdaReturnType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(flatMapRType)],
                nullability: .nonNull
            )))
            let flatMapLambdaType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: flatMapLambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let flatMapReturnType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(flatMapRType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "flatMap",
                externalLinkName: "kk_map_flatMap",
                parameterTypes: [flatMapLambdaType],
                returnType: flatMapReturnType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, flatMapRSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // maxByOrNull / minByOrNull with R: Comparable<R> selector
        let nullableEntryType = types.makeNullable(entryType)
        do {
            func registerMapByOrNull(name: String, externalLinkName: String) {
                let memberName = interner.intern(name)
                let memberFQName = mapFQName + [memberName]
                guard symbols.lookup(fqName: memberFQName) == nil else { return }

                let selectorReturnType: TypeID
                let extraTypeParamSymbols: [SymbolID]
                let extraUpperBoundsList: [[TypeID]]
                if let rParam = makeComparableTypeParam(
                    symbols: symbols, types: types, interner: interner,
                    memberFQName: memberFQName
                ) {
                    selectorReturnType = rParam.type
                    extraTypeParamSymbols = [rParam.symbol]
                    extraUpperBoundsList = [rParam.upperBounds]
                } else {
                    selectorReturnType = types.anyType
                    extraTypeParamSymbols = []
                    extraUpperBoundsList = []
                }
                let selectorType = types.make(.functionType(FunctionType(
                    params: [entryType],
                    returnType: selectorReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [selectorType],
                        returnType: nullableEntryType,
                        typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol] + extraTypeParamSymbols,
                        typeParameterUpperBoundsList: [[], []] + extraUpperBoundsList,
                        classTypeParameterCount: 2
                    ),
                    for: memberSymbol
                )
            }

            registerMapByOrNull(name: "maxByOrNull", externalLinkName: "kk_map_maxByOrNull")
            registerMapByOrNull(name: "minByOrNull", externalLinkName: "kk_map_minByOrNull")
        }
    }

    private func registerSyntheticMapEntryStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID
    ) -> TypeID {
        let entryName = interner.intern("Entry")
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let entryFQName = mapFQName + [entryName]
        let entrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: entryFQName) {
            entrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: symbol)
            entrySymbol = symbol
        }

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: entrySymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: entrySymbol)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let pairType: TypeID? = if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
            ?? symbols.lookupByShortName(interner.intern("Pair")).first
        {
            types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(keyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        } else {
            nil
        }

        func registerMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            flags: SymbolFlags = [.synthetic]
        ) {
            let memberName = interner.intern(name)
            let memberFQName = entryFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(entrySymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "component1", returnType: keyType, externalLinkName: "kk_pair_first", flags: [.synthetic, .operatorFunction])
        registerMember(name: "component2", returnType: valueType, externalLinkName: "kk_pair_second", flags: [.synthetic, .operatorFunction])
        registerMember(name: "key", returnType: keyType, externalLinkName: "kk_pair_first")
        registerMember(name: "value", returnType: valueType, externalLinkName: "kk_pair_second")
        if let pairType {
            registerMember(name: "toPair", returnType: pairType, externalLinkName: "kk_map_entry_to_pair")
        }

        return receiverType
    }

    func registerSyntheticMutableMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol _: SymbolID,
        valueTypeParamSymbol _: SymbolID
    ) {
        let mutableMapName = interner.intern("MutableMap")
        let mutableMapFQName = kotlinCollectionsPkg + [mutableMapName]
        let mutableMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableMapName,
                fqName: mutableMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)
        types.setNominalDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let mutableKeyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mutableMapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mutableValueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mutableMapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let keyType = types.make(.typeParam(TypeParamType(symbol: mutableKeyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mutableValueParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([mutableKeyParamSymbol, mutableValueParamSymbol], for: mutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableMapSymbol)
        symbols.setSupertypeTypeArgs([.out(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))

        let getOrPutLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let mapParamType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            ("set", [keyType, valueType], types.unitType, "kk_mutable_map_put", [.synthetic, .operatorFunction]),
            ("put", [keyType, valueType], types.makeNullable(valueType), "kk_mutable_map_put", [.synthetic]),
            ("remove", [keyType], types.makeNullable(valueType), "kk_mutable_map_remove", [.synthetic]),
            ("clear", [], types.unitType, "kk_mutable_map_clear", [.synthetic]),
            ("getOrPut", [keyType, getOrPutLambdaType], valueType, "kk_mutable_map_getOrPut", [.synthetic, .inlineFunction]),
            ("putAll", [mapParamType], types.unitType, "kk_mutable_map_putAll", [.synthetic]),
        ]

        for member in members {
            let memberName = interner.intern(member.name)
            let memberFQName = mutableMapFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: member.flags
            )
            symbols.setParentSymbol(mutableMapSymbol, for: memberSymbol)
            symbols.setExternalLinkName(member.external, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: member.params,
                    returnType: member.ret,
                    typeParameterSymbols: [mutableKeyParamSymbol, mutableValueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }
    }
}
