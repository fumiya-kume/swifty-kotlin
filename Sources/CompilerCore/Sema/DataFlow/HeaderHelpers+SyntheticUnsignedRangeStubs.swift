/// Synthetic UIntRange / ULongRange stub registration helpers.
///
/// Split out from `HeaderHelpers+SyntheticRangeProgressionStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticUIntRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("UIntRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let rangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.uintType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.uintType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )
        let progressionType = syntheticNominalType(
            named: "UIntProgression",
            in: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.uintType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let uintArrayType = syntheticNominalType(
            named: "UIntArray",
            in: [interner.intern("kotlin")],
            symbols: symbols,
            types: types,
            interner: interner
        )
        let randomType = syntheticNominalType(
            named: "Random",
            in: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols,
            types: types,
            interner: interner
        )

        for property in [
            ("start", "kk_uint_range_first"),
            ("end", "kk_uint_range_last"),
            ("first", "kk_uint_range_first"),
            ("last", "kk_uint_range_last"),
            ("endExclusive", "kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.uintType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.intType,
            externalLinkName: "kk_uint_range_step",
            symbols: symbols,
            interner: interner
        )

        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.uintType],
            returnType: types.booleanType,
            externalLinkName: "kk_uint_range_contains",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "kk_uint_range_isEmpty",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "kk_uint_range_iterator",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: progressionType,
            externalLinkName: "kk_uint_range_reversed",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_uint_range_toList",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toUIntArray",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: uintArrayType,
            externalLinkName: "kk_uint_range_toUIntArray",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "firstOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.uintType),
            externalLinkName: "kk_uint_range_firstOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "lastOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.uintType),
            externalLinkName: "kk_uint_range_lastOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.uintType),
            externalLinkName: "kk_uint_range_randomOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [randomType],
            returnType: types.makeNullable(types.uintType),
            externalLinkName: "kk_uint_range_randomOrNull_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_uint_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_uint_range_drop",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "average",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.doubleType,
            externalLinkName: "kk_uint_range_average",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "sorted",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_uint_range_sorted",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.uintType,
            externalLinkName: "kk_uint_range_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [randomType],
            returnType: types.uintType,
            externalLinkName: "kk_uint_range_random_random",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticConstructor(
            ownerSymbol: classSymbol,
            ownerType: rangeType,
            parameterTypes: [types.uintType, types.uintType],
            parameterNames: ["start", "end"],
            externalLinkName: "kk_uint_rangeTo",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticULongRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("ULongRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let rangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.ulongType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.ulongType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )
        let progressionType = syntheticNominalType(
            named: "ULongProgression",
            in: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.ulongType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ulongArrayType = syntheticNominalType(
            named: "ULongArray",
            in: [interner.intern("kotlin")],
            symbols: symbols,
            types: types,
            interner: interner
        )
        let randomType = syntheticNominalType(
            named: "Random",
            in: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols,
            types: types,
            interner: interner
        )

        for property in [
            ("start", "kk_ulong_range_first"),
            ("endInclusive", "kk_ulong_range_last"),
            ("first", "kk_ulong_range_first"),
            ("last", "kk_ulong_range_last"),
            ("endExclusive", "kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.ulongType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.intType,
            externalLinkName: "kk_ulong_range_step",
            symbols: symbols,
            interner: interner
        )

        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.ulongType],
            returnType: types.booleanType,
            externalLinkName: "kk_ulong_range_contains",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "kk_ulong_range_isEmpty",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "kk_ulong_range_iterator",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: progressionType,
            externalLinkName: "kk_ulong_range_reversed",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_ulong_range_toList",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toULongArray",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: ulongArrayType,
            externalLinkName: "kk_ulong_range_toULongArray",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "firstOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.ulongType),
            externalLinkName: "kk_ulong_range_firstOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "lastOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.ulongType),
            externalLinkName: "kk_ulong_range_lastOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.ulongType),
            externalLinkName: "kk_ulong_range_randomOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [randomType],
            returnType: types.makeNullable(types.ulongType),
            externalLinkName: "kk_ulong_range_randomOrNull_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_ulong_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_ulong_range_drop",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "average",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.doubleType,
            externalLinkName: "kk_ulong_range_average",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "sorted",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_ulong_range_sorted",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.ulongType,
            externalLinkName: "kk_ulong_range_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [randomType],
            returnType: types.ulongType,
            externalLinkName: "kk_ulong_range_random_random",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticConstructor(
            ownerSymbol: classSymbol,
            ownerType: rangeType,
            parameterTypes: [types.ulongType, types.ulongType],
            parameterNames: ["start", "endInclusive"],
            externalLinkName: "kk_ulong_rangeTo",
            symbols: symbols,
            interner: interner
        )
    }

}

extension DataFlowSemaPhase {
    fileprivate func syntheticListType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let listSymbol = symbols.lookupByShortName(interner.intern("List")).first else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
