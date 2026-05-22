// swiftlint:disable file_length

/// Synthetic IntRange / LongRange / CharRange stub registration plus
/// associated property/method/constructor helpers.
///
/// Split out from `HeaderHelpers+SyntheticRangeProgressionStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticIntRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        randomType: TypeID
    ) {
        let className = interner.intern("IntRange")
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

        let intRangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.intType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.intType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )

        registerSyntheticIntRangeConstructor(
            ownerSymbol: classSymbol,
            ownerType: intRangeType,
            classFQName: classFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticIntRangeProperty(
            named: "first",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_first",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeProperty(
            named: "last",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_last",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeProperty(
            named: "start",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_first",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeProperty(
            named: "endInclusive",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_last",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeProperty(
            named: "endExclusive",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_endExclusive",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeProperty(
            named: "step",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            propertyType: types.intType,
            externalLinkName: "kk_range_step",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticIntRangeMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [types.intType],
            returnType: types.booleanType,
            externalLinkName: "kk_op_contains",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "kk_range_isEmpty",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.intType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_toList",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "toIntArray",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: syntheticPrimitiveArrayType(named: "IntArray", symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_toIntArray",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: intRangeType,
            externalLinkName: "kk_range_reversed",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: syntheticIteratorType(elementType: types.intType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_iterator",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "firstOrNull",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.intType),
            externalLinkName: "kk_range_firstOrNull",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "lastOrNull",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.intType),
            externalLinkName: "kk_range_lastOrNull",
            symbols: symbols,
            interner: interner
        )
        let randomType = syntheticNominalType(
            named: "Random",
            in: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.intType),
            externalLinkName: "kk_range_randomOrNull",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [randomType],
            returnType: types.makeNullable(types.intType),
            externalLinkName: "kk_range_randomOrNull_random",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "take",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.intType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_take",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.intType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_drop",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "average",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.doubleType,
            externalLinkName: "kk_range_average",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "sorted",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.intType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_range_sorted",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "random",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [],
            returnType: types.intType,
            externalLinkName: "kk_range_random",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntRangeMethod(
            named: "random",
            ownerSymbol: classSymbol,
            classFQName: classFQName,
            receiverType: intRangeType,
            parameterTypes: [randomType],
            returnType: types.intType,
            externalLinkName: "kk_range_random_random",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticIntRangeConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        classFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let initFQName = classFQName + [initName]
        guard symbols.lookup(fqName: initFQName) == nil else { return }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName("kk_op_rangeTo", for: ctorSymbol)

        let startName = interner.intern("start")
        let startSymbol = symbols.define(
            kind: .valueParameter,
            name: startName,
            fqName: initFQName + [startName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: startSymbol)

        let endName = interner.intern("endInclusive")
        let endSymbol = symbols.define(
            kind: .valueParameter,
            name: endName,
            fqName: initFQName + [endName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: endSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.intType, types.intType],
                returnType: ownerType,
                valueParameterSymbols: [startSymbol, endSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false]
            ),
            for: ctorSymbol
        )
    }

    func registerSyntheticIntRangeProperty(
        named name: String,
        ownerSymbol: SymbolID,
        classFQName: [InternedString],
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = classFQName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else { return }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    func registerSyntheticIntRangeMethod(
        named name: String,
        ownerSymbol: SymbolID,
        classFQName: [InternedString],
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = classFQName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    func syntheticPrimitiveArrayType(
        named name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let symbol = symbols.lookupByShortName(interner.intern(name)).first else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func syntheticIteratorType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let iteratorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ]
        guard let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func syntheticNominalType(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: packageFQName + [interner.intern(name)]) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func registerSyntheticConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameterTypes: [TypeID],
        parameterNames: [String],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        let valueParameterSymbols = zip(parameterNames, parameterTypes).map { name, type in
            let parameterName = interner.intern(name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    // MARK: - LongRange stub (STDLIB-RANGE-035)

    func registerSyntheticLongRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        randomType: TypeID
    ) {
        let className = interner.intern("LongRange")
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

        let longRangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.longType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.longType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )

        let progressionType = syntheticNominalType(
            named: "LongProgression",
            in: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.longType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let longArrayType = syntheticPrimitiveArrayType(
            named: "LongArray",
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

        // Properties: start, end, first, last, step
        for property in [
            ("start", "kk_long_range_first"),
            ("endInclusive", "kk_long_range_last"),
            ("first", "kk_long_range_first"),
            ("last", "kk_long_range_last"),
            ("endExclusive", "kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.longType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.longType,
            externalLinkName: "kk_long_range_step",
            symbols: symbols,
            interner: interner
        )

        // Methods: contains, isEmpty, iterator, reversed, toList, toLongArray, random
        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [types.longType],
            returnType: types.booleanType,
            externalLinkName: "kk_long_range_contains",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "kk_long_range_isEmpty",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "kk_long_range_iterator",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: progressionType,
            externalLinkName: "kk_long_range_reversed",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.longType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_long_range_toList",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toLongArray",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: longArrayType,
            externalLinkName: "kk_long_range_toLongArray",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.longType),
            externalLinkName: "kk_long_range_randomOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [randomType],
            returnType: types.makeNullable(types.longType),
            externalLinkName: "kk_long_range_randomOrNull_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "firstOrNull",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.longType),
            externalLinkName: "kk_long_range_firstOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "lastOrNull",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.longType),
            externalLinkName: "kk_long_range_lastOrNull",
            symbols: symbols,
            interner: interner
        )

        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.longType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_long_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.longType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_long_range_drop",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "average",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.doubleType,
            externalLinkName: "kk_long_range_average",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "sorted",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.longType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_long_range_sorted",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [],
            returnType: types.longType,
            externalLinkName: "kk_long_range_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: longRangeType,
            parameterTypes: [randomType],
            returnType: types.longType,
            externalLinkName: "kk_long_range_random_random",
            symbols: symbols,
            interner: interner
        )

        // Constructor: LongRange(start, end)
        registerSyntheticConstructor(
            ownerSymbol: classSymbol,
            ownerType: longRangeType,
            parameterTypes: [types.longType, types.longType],
            parameterNames: ["start", "endInclusive"],
            externalLinkName: "kk_long_rangeTo",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticCharRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        randomType: TypeID
    ) {
        let className = interner.intern("CharRange")
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

        let charRangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.charType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.charType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.charType,
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
            ("start", "kk_range_first"),
            ("end", "kk_range_last"),
            ("endInclusive", "kk_range_last"),
            ("first", "kk_range_first"),
            ("last", "kk_range_last"),
            ("endExclusive", "kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.charType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.intType,
            externalLinkName: "kk_range_step",
            symbols: symbols,
            interner: interner
        )

        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [types.charType],
            returnType: types.booleanType,
            externalLinkName: "kk_op_contains",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "kk_range_isEmpty",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "kk_range_iterator",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "firstOrNull",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.charType),
            externalLinkName: "kk_range_firstOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "lastOrNull",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.charType),
            externalLinkName: "kk_range_lastOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: types.makeNullable(types.charType),
            externalLinkName: "kk_char_range_randomOrNull",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "randomOrNull",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [randomType],
            returnType: types.makeNullable(types.charType),
            externalLinkName: "kk_char_range_randomOrNull_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: charRangeType,
            externalLinkName: "kk_range_reversed",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.charType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_char_range_toList",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.charType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_char_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.charType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_char_range_drop",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "sorted",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: syntheticListType(elementType: types.charType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "kk_char_range_sorted",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [],
            returnType: types.charType,
            externalLinkName: "kk_range_random",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "random",
            ownerSymbol: classSymbol,
            receiverType: charRangeType,
            parameterTypes: [randomType],
            returnType: types.charType,
            externalLinkName: "kk_char_range_random_random",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticConstructor(
            ownerSymbol: classSymbol,
            ownerType: charRangeType,
            parameterTypes: [types.charType, types.charType],
            parameterNames: ["start", "endInclusive"],
            externalLinkName: "kk_char_rangeTo",
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - ClosedRange stub (STDLIB-RANGE-IFACE-001)
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
