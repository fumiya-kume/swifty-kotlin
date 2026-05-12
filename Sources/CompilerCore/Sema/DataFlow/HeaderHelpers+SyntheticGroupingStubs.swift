/// Synthetic stub for `kotlin.collections.Grouping<T, K>` and the
/// `Grouping.aggregate*`/`fold*`/`reduce*`/`eachCount*` family used by
/// `groupingBy`-based aggregations (STDLIB-285/286).
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift` to keep
/// each header-helpers file scoped to a single responsibility.
extension DataFlowSemaPhase {
    func registerSyntheticGroupingStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let collectionsPkg = kotlinPkg + [interner.intern("collections")]
        _ = ensureSyntheticPackage(fqName: collectionsPkg, symbols: symbols)

        let groupingName = interner.intern("Grouping")
        let groupingFQName = collectionsPkg + [groupingName]
        let groupingSymbol: SymbolID = if let existing = symbols.lookup(fqName: groupingFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: groupingName,
                fqName: groupingFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Type parameters: T (source element type) and K (key type)
        let tParamName = interner.intern("T")
        let tParamFQName = groupingFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let kParamName = interner.intern("K")
        let kParamFQName = groupingFQName + [kParamName]
        let kParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: kParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: kParamName,
                fqName: kParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        types.setNominalTypeParameterSymbols([tParamSymbol, kParamSymbol], for: groupingSymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: groupingSymbol)

        let tTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol)))
        let kTypeParam = types.make(.typeParam(TypeParamType(symbol: kParamSymbol)))

        let groupingType = types.make(.classType(ClassType(
            classSymbol: groupingSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Build Map<K, V> return types when Map symbol is available.
        let mapName = interner.intern("Map")
        let mutableMapName = interner.intern("MutableMap")
        let mapSymbol = symbols.lookup(fqName: collectionsPkg + [mapName])
            ?? symbols.lookupByShortName(mapName).first
        let mutableMapSymbol = symbols.lookup(fqName: collectionsPkg + [mutableMapName])
            ?? symbols.lookupByShortName(mutableMapName).first

        let groupingTypeParameterSymbols: [SymbolID] = [tParamSymbol, kParamSymbol]

        func makeMapType(valueType: TypeID) -> TypeID {
            guard let mapSymbol else {
                return types.anyType
            }
            return types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(kTypeParam), .invariant(valueType)],
                nullability: .nonNull
            )))
        }

        func registerGroupingMember(
            named name: String,
            parameters: [TypeID],
            returnType: TypeID,
            externalLinkName: String,
            typeParameterSymbols: [SymbolID] = groupingTypeParameterSymbols,
            classTypeParameterCount: Int = 2
        ) {
            let memberName = interner.intern(name)
            let memberFQName = groupingFQName + [memberName]
            let memberSignature = FunctionSignature(
                receiverType: groupingType,
                parameterTypes: parameters,
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            )
            if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                symbols.functionSignature(for: symbolID) == memberSignature
            }) {
                if symbols.externalLinkName(for: existing) != externalLinkName {
                    symbols.setExternalLinkName(externalLinkName, for: existing)
                }
                return
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(groupingSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(memberSignature, for: memberSymbol)
        }

        // eachCount() -> Map<K, Int>
        registerGroupingMember(
            named: "eachCount",
            parameters: [],
            returnType: makeMapType(valueType: types.intType),
            externalLinkName: "kk_grouping_eachCount"
        )

        // aggregate(operation: (K, R?, T, Boolean) -> R) -> Map<K, R>
        let aggregateRName = interner.intern("AggregateR")
        let aggregateRFQName = groupingFQName + [interner.intern("aggregate"), aggregateRName]
        let aggregateRSymbol: SymbolID = if let existing = symbols.lookup(fqName: aggregateRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: aggregateRName,
                fqName: aggregateRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let aggregateRType = types.make(.typeParam(TypeParamType(symbol: aggregateRSymbol)))
        let aggregateOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.makeNullable(aggregateRType), tTypeParam, types.booleanType],
            returnType: aggregateRType
        )))
        registerGroupingMember(
            named: "aggregate",
            parameters: [
                aggregateOperationType,
            ],
            returnType: makeMapType(valueType: aggregateRType),
            externalLinkName: "kk_grouping_aggregate",
            typeParameterSymbols: groupingTypeParameterSymbols + [aggregateRSymbol]
        )

        // aggregateTo(destination, operation) -> destination
        let aggregateToRName = interner.intern("AggregateToR")
        let aggregateToRFQName = groupingFQName + [interner.intern("aggregateTo"), aggregateToRName]
        let aggregateToRSymbol: SymbolID = if let existing = symbols.lookup(fqName: aggregateToRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: aggregateToRName,
                fqName: aggregateToRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let aggregateToRType = types.make(.typeParam(TypeParamType(symbol: aggregateToRSymbol)))
        let aggregateToDestinationType: TypeID
        if let mutableMapSymbol {
            aggregateToDestinationType = types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.invariant(kTypeParam), .invariant(aggregateToRType)],
                nullability: .nonNull
            )))
        } else {
            aggregateToDestinationType = types.anyType
        }
        let aggregateToOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.makeNullable(aggregateToRType), tTypeParam, types.booleanType],
            returnType: aggregateToRType
        )))
        registerGroupingMember(
            named: "aggregateTo",
            parameters: [
                aggregateToDestinationType,
                aggregateToOperationType,
            ],
            returnType: aggregateToDestinationType,
            externalLinkName: "kk_grouping_aggregateTo",
            typeParameterSymbols: groupingTypeParameterSymbols + [aggregateToRSymbol]
        )

        // eachCountTo(destination: MutableMap<in K, Int>) -> MutableMap<in K, Int>
        let eachCountToDestinationType: TypeID
        if let mutableMapSymbol {
            eachCountToDestinationType = types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.in(kTypeParam), .invariant(types.intType)],
                nullability: .nonNull
            )))
        } else {
            eachCountToDestinationType = types.anyType
        }
        registerGroupingMember(
            named: "eachCountTo",
            parameters: [
                eachCountToDestinationType,
            ],
            returnType: eachCountToDestinationType,
            externalLinkName: "kk_grouping_eachCountTo"
        )

        // fold(initialValue: R, operation: (R, T) -> R) -> Map<K, R>
        let foldRName = interner.intern("R")
        let foldRFQName = groupingFQName + [foldRName]
        let foldRSymbol: SymbolID = if let existing = symbols.lookup(fqName: foldRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: foldRName,
                fqName: foldRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let foldRType = types.make(.typeParam(TypeParamType(symbol: foldRSymbol)))
        let foldOperationType = types.make(.functionType(FunctionType(
            params: [foldRType, tTypeParam],
            returnType: foldRType
        )))
        registerGroupingMember(
            named: "fold",
            parameters: [
                foldRType,
                foldOperationType,
            ],
            returnType: makeMapType(valueType: foldRType),
            externalLinkName: "kk_grouping_fold",
            typeParameterSymbols: groupingTypeParameterSymbols + [foldRSymbol]
        )

        // fold(initialValueSelector: (K, T) -> R, operation: (K, R, T) -> R) -> Map<K, R>
        let foldInitialValueSelectorType = types.make(.functionType(FunctionType(
            params: [kTypeParam, tTypeParam],
            returnType: foldRType
        )))
        let foldWithSelectorOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, foldRType, tTypeParam],
            returnType: foldRType
        )))
        registerGroupingMember(
            named: "fold",
            parameters: [
                foldInitialValueSelectorType,
                foldWithSelectorOperationType,
            ],
            returnType: makeMapType(valueType: foldRType),
            externalLinkName: "kk_grouping_fold_initialValueSelector",
            typeParameterSymbols: groupingTypeParameterSymbols + [foldRSymbol]
        )

        // foldTo(destination, initialValue, operation) -> destination
        let foldToOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, tTypeParam],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "foldTo",
            parameters: [
                types.anyType,
                types.anyType,
                foldToOperationType,
            ],
            returnType: types.anyType,
            externalLinkName: "kk_grouping_foldTo"
        )

        // foldTo(destination, initialValueSelector, operation) -> destination
        let foldToInitialValueSelectorType = types.make(.functionType(FunctionType(
            params: [kTypeParam, tTypeParam],
            returnType: types.anyType
        )))
        let foldToKeyedOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.anyType, tTypeParam],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "foldTo",
            parameters: [
                types.anyType,
                foldToInitialValueSelectorType,
                foldToKeyedOperationType,
            ],
            returnType: types.anyType,
            externalLinkName: "kk_grouping_foldTo_selector"
        )

        // reduce(operation: (S, T) -> S) -> Map<K, S>
        let reduceSName = interner.intern("S")
        let reduceSFQName = groupingFQName + [reduceSName]
        let reduceSSymbol: SymbolID = if let existing = symbols.lookup(fqName: reduceSFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: reduceSName,
                fqName: reduceSFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let reduceSType = types.make(.typeParam(TypeParamType(symbol: reduceSSymbol)))
        let reduceOperationType = types.make(.functionType(FunctionType(
            params: [reduceSType, tTypeParam],
            returnType: reduceSType
        )))
        registerGroupingMember(
            named: "reduce",
            parameters: [
                reduceOperationType,
            ],
            returnType: makeMapType(valueType: reduceSType),
            externalLinkName: "kk_grouping_reduce",
            typeParameterSymbols: groupingTypeParameterSymbols + [reduceSSymbol]
        )

        // reduceTo(destination, operation) -> destination
        let reduceToDestinationType: TypeID
        if let mapSymbol {
            reduceToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.out(types.anyType), .out(types.anyType)],
                nullability: .nonNull
            )))
        } else {
            reduceToDestinationType = types.anyType
        }
        let reduceToOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, types.anyType, types.anyType],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "reduceTo",
            parameters: [
                reduceToDestinationType,
                reduceToOperationType,
            ],
            returnType: reduceToDestinationType,
            externalLinkName: "kk_grouping_reduceTo",
            typeParameterSymbols: groupingTypeParameterSymbols
        )
    }

    private func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }
}
