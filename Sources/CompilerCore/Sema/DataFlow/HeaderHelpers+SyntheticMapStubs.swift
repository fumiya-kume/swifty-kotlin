import RuntimeABI

/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
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
            symbols.setExternalLinkName("__kk_map_get", for: getSymbol)
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

        return (mapSymbol, keyParamSymbol, valueParamSymbol)
    }

    /// Register `kotlin.collections.AbstractMap<K, V>` surface (STDLIB-COL-ABSTRACT-004).
    func registerSyntheticAbstractMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractMapName = interner.intern("AbstractMap")
        let abstractMapFQName = kotlinCollectionsPkg + [abstractMapName]
        let abstractMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMapName,
                fqName: abstractMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamFQName = abstractMapFQName + [keyName]
        let valueParamFQName = abstractMapFQName + [valueName]
        let keyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: keyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: keyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let valueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: valueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))

        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: abstractMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: abstractMapSymbol)

        let abstractMapType = types.make(.classType(ClassType(
            classSymbol: abstractMapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMapType, for: abstractMapSymbol)
        symbols.setDirectSupertypes([mapInterfaceSymbol], for: abstractMapSymbol)
        types.setNominalDirectSupertypes([mapInterfaceSymbol], for: abstractMapSymbol)
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMapSymbol,
            supertype: mapInterfaceSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMapSymbol,
            supertype: mapInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMapFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMapSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMapType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        return abstractMapSymbol
    }

    func registerMapHigherOrderMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]

        // Keep the legacy Map vtable slot reserved when the source-backed
        // no-argument count extension replaces the synthetic member. Runtime
        // dispatch for Map.size uses the slot after the two existing Map
        // entries, so removing the synthetic count symbol must not shift that
        // ABI slot even though the source declaration is not a Map member.
        let sourceBackedMapCount = bundledIndex.contains(
            ownerFQName: mapFQName,
            name: interner.intern("count"),
            arity: 0
        )
        if sourceBackedMapCount {
            let existingHint = symbols.nominalLayoutHint(for: mapInterfaceSymbol)
            symbols.setNominalLayoutHint(
                NominalLayoutHint(
                    declaredFieldCount: existingHint?.declaredFieldCount,
                    declaredInstanceSizeWords: existingHint?.declaredInstanceSizeWords,
                    declaredVtableSize: max(existingHint?.declaredVtableSize ?? 0, 2),
                    declaredItableSize: existingHint?.declaredItableSize
                ),
                for: mapInterfaceSymbol
            )
        }

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        // Map<K, V> is declared with K invariant (only V is `out`, see
        // registerSyntheticMapStub). `receiverType` above widens K to `out` so these
        // members can be called on already-projected receivers, but that widened shape
        // must never leak into a RETURN type: callers expecting the exact `Map<K, V>`
        // (e.g. a data class `copy()` parameter) would then reject it as a supertype,
        // not a match. Use `selfMapType` for any member that hands back `Map<K, V>` as-is.
        let selfMapType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.invariant(keyType), .out(valueType)],
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
        // MutableMap is registered before Map.Entry, so its nested entry shell
        // cannot link its inherited Map.Entry surface during first registration.
        // Complete that relationship now, after Map.Entry exists, so key/value
        // lookup follows the Kotlin declaration rather than a duplicate member.
        let mutableMapFQName = kotlinCollectionsPkg + [interner.intern("MutableMap")]
        if let mutableEntrySymbol = symbols.lookup(
            fqName: mutableMapFQName + [interner.intern("MutableEntry")]
        ),
           let mutableEntryKeySymbol = symbols.lookup(
               fqName: mutableMapFQName
                   + [interner.intern("MutableEntry"), interner.intern("K")]
           ),
           let mutableEntryValueSymbol = symbols.lookup(
               fqName: mutableMapFQName
                   + [interner.intern("MutableEntry"), interner.intern("V")]
           ),
           let mapEntrySymbol = symbols.lookup(fqName: mapFQName + [interner.intern("Entry")])
        {
            let mutableEntryKeyType = types.make(.typeParam(TypeParamType(
                symbol: mutableEntryKeySymbol,
                nullability: .nonNull
            )))
            let mutableEntryValueType = types.make(.typeParam(TypeParamType(
                symbol: mutableEntryValueSymbol,
                nullability: .nonNull
            )))
            let mutableEntrySupertypeArgs: [TypeArg] = [
                .out(mutableEntryKeyType),
                .out(mutableEntryValueType),
            ]
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                mutableEntrySupertypeArgs,
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                mutableEntrySupertypeArgs,
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }
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
            if bundledIndex.contains(ownerFQName: mapFQName, name: memberName, arity: parameterTypes.count) {
                skipStats?.recordSkip(ownerFQName: mapFQName, name: memberName, arity: parameterTypes.count, interner: interner)
                return
            }
            if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes == parameterTypes
            }) {
                symbols.setExternalLinkName(externalLinkName, for: existing)
                return
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
            let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .map,
                memberName: interner.resolve(memberName),
                arity: parameterTypes.count,
                fallback: externalLinkName
            )
            symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
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
                args: [.invariant(keyType), .out(rType)],
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
                args: [.invariant(rType), .out(valueType)],
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
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterNot",
            externalLinkName: "kk_map_filterNot",
            parameterTypes: [filterLambdaType],
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterKeys",
            externalLinkName: "kk_map_filterKeys",
            parameterTypes: [filterKeyLambdaType],
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "filterValues",
            externalLinkName: "kk_map_filterValues",
            parameterTypes: [filterValueLambdaType],
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "count",
            externalLinkName: "kk_map_size",
            parameterTypes: [],
            returnType: types.intType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic]
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
            name: "plus",
            externalLinkName: "kk_map_plus",
            parameterTypes: [pairType],
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        registerMember(
            name: "minus",
            externalLinkName: "kk_map_minus",
            parameterTypes: [keyType],
            returnType: selfMapType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        if let listSymbol {
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
                if bundledIndex.contains(ownerFQName: mapFQName, name: memberName, arity: 1) {
                    skipStats?.recordSkip(ownerFQName: mapFQName, name: memberName, arity: 1, interner: interner)
                    return
                }

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

        registerMember(name: "component1", returnType: keyType, externalLinkName: "__kk_pair_first", flags: [.synthetic, .operatorFunction])
        registerMember(name: "component2", returnType: valueType, externalLinkName: "__kk_pair_second", flags: [.synthetic, .operatorFunction])
        registerMember(name: "key", returnType: keyType, externalLinkName: "__kk_pair_first")
        registerMember(name: "value", returnType: valueType, externalLinkName: "__kk_pair_second")
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

        // The source-backed AbstractMutableMap declaration names the official
        // nested MutableMap.MutableEntry type. Keep this nominal entry shell in
        // the shared fallback path until MutableMap itself becomes source-backed.
        let mutableEntryName = interner.intern("MutableEntry")
        let mutableEntryFQName = mutableMapFQName + [mutableEntryName]
        let mutableEntrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableEntryFQName) {
            mutableEntrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: mutableEntryName,
                fqName: mutableEntryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: symbol)
            mutableEntrySymbol = symbol
        }
        types.setNominalTypeParameterSymbols([mutableKeyParamSymbol, mutableValueParamSymbol], for: mutableEntrySymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableEntrySymbol)
        if let mapEntrySymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map"), interner.intern("Entry")]
        ) {
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }

        // Keep the official MutableMap.entries property available to the
        // source-backed AbstractMutableMap declaration. The runtime-backed
        // collection behavior remains on the existing shared map bridges.
        let mutableSetSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        )
        let mutableEntryType = types.make(.classType(ClassType(
            classSymbol: mutableEntrySymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        let mutableEntriesType: TypeID
        if let mutableSetSymbol {
            mutableEntriesType = types.make(.classType(ClassType(
                classSymbol: mutableSetSymbol,
                args: [.invariant(mutableEntryType)],
                nullability: .nonNull
            )))
        } else {
            mutableEntriesType = types.anyType
        }
        let entriesName = interner.intern("entries")
        let entriesFQName = mutableMapFQName + [entriesName]
        let entriesPropertySymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: entriesFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            entriesPropertySymbol = existing
        } else {
            entriesPropertySymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: entriesPropertySymbol)
        }
        symbols.setPropertyType(mutableEntriesType, for: entriesPropertySymbol)
        symbols.setExternalLinkName("__kk_map_entries", for: entriesPropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))

        let mapParamType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        _ = registerSyntheticMutableMapEntryStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            mutableMapSymbol: mutableMapSymbol,
            keyTypeParamSymbol: mutableKeyParamSymbol,
            valueTypeParamSymbol: mutableValueParamSymbol
        )

        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            // `set` and the higher-order MutableMap APIs are source-backed in
            // MapLookupAndTransform.kt; retain only the low-level put bridge.
            ("put", [keyType, valueType], types.makeNullable(valueType), "__kk_mutable_map_put", [.synthetic, .throwingFunction]),
            ("remove", [keyType], types.makeNullable(valueType), "__kk_mutable_map_remove", [.synthetic]),
            ("clear", [], types.unitType, "__kk_mutable_map_clear", [.synthetic]),
            ("putAll", [mapParamType], types.unitType, "__kk_mutable_map_putAll", [.synthetic]),
        ]

        for member in members {
            let memberName = interner.intern(member.name)
            let memberFQName = mutableMapFQName + [memberName]
            guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == member.params &&
                    signature.returnType == member.ret
            }) == nil else {
                continue
            }
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

        _ = registerSyntheticAbstractMutableMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            mutableMapSymbol: mutableMapSymbol
        )
    }

    private func registerSyntheticMutableMapEntryStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        mutableMapSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID
    ) -> TypeID {
        let mutableEntryName = interner.intern("MutableEntry")
        let mutableMapFQName = kotlinCollectionsPkg + [interner.intern("MutableMap")]
        let mutableEntryFQName = mutableMapFQName + [mutableEntryName]
        let mutableEntrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableEntryFQName) {
            mutableEntrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: mutableEntryName,
                fqName: mutableEntryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: symbol)
            mutableEntrySymbol = symbol
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let mutableKeyParamFQName = mutableEntryFQName + [keyName]
        let mutableValueParamFQName = mutableEntryFQName + [valueName]
        let mutableEntryKeyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableKeyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: mutableKeyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let mutableEntryValueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableValueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: mutableValueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: mutableEntryKeyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mutableEntryValueParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols(
            [mutableEntryKeyParamSymbol, mutableEntryValueParamSymbol],
            for: mutableEntrySymbol
        )
        types.setNominalTypeParameterVariances([.out, .out], for: mutableEntrySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableEntrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        if let mapEntrySymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map"), interner.intern("Entry")]
        ) {
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }

        let setValueName = interner.intern("setValue")
        let setValueFQName = mutableEntryFQName + [setValueName]
        if symbols.lookup(fqName: setValueFQName) == nil {
            let setValueSymbol = symbols.define(
                kind: .function,
                name: setValueName,
                fqName: setValueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableEntrySymbol, for: setValueSymbol)
            symbols.setExternalLinkName("__kk_mutable_map_entry_setValue", for: setValueSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [valueType],
                    returnType: valueType,
                    typeParameterSymbols: [mutableEntryKeyParamSymbol, mutableEntryValueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: setValueSymbol
            )
        }

        _ = mapInterfaceSymbol
        _ = keyTypeParamSymbol
        _ = valueTypeParamSymbol
        return receiverType
    }

    /// Register the fallback `kotlin.collections.AbstractMutableMap<K, V>` surface
    /// (STDLIB-COL-ABSTRACT-007). The bundled declaration in
    /// `Stdlib/kotlin/collections/AbstractMutableMap.kt` owns the normal source-backed
    /// path; this shell remains available for non-bundled metadata contexts.
    func registerSyntheticAbstractMutableMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        mutableMapSymbol: SymbolID
    ) -> SymbolID {
        let abstractMutableMapName = interner.intern("AbstractMutableMap")
        let abstractMutableMapFQName = kotlinCollectionsPkg + [abstractMutableMapName]
        let abstractMutableMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableMapName,
                fqName: abstractMutableMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamFQName = abstractMutableMapFQName + [keyName]
        let valueParamFQName = abstractMutableMapFQName + [valueName]
        let keyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: keyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: keyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let valueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: valueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))

        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: abstractMutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: abstractMutableMapSymbol)

        let abstractMutableMapType = types.make(.classType(ClassType(
            classSymbol: abstractMutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableMapType, for: abstractMutableMapSymbol)

        let abstractMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("AbstractMap")])
        let readonlySupertype = abstractMapSymbol ?? mapInterfaceSymbol
        symbols.setDirectSupertypes([readonlySupertype, mutableMapSymbol], for: abstractMutableMapSymbol)
        types.setNominalDirectSupertypes([readonlySupertype, mutableMapSymbol], for: abstractMutableMapSymbol)
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMutableMapSymbol,
            supertype: readonlySupertype
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMutableMapSymbol,
            supertype: readonlySupertype
        )
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .invariant(valueType)],
            for: abstractMutableMapSymbol,
            supertype: mutableMapSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .invariant(valueType)],
            for: abstractMutableMapSymbol,
            supertype: mutableMapSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableMapFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableMapSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableMapType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        return abstractMutableMapSymbol
    }
}
