import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticRangeProgressionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinName = interner.intern("kotlin")
        let rangesName = interner.intern("ranges")
        let kotlinFQName: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQName) == nil {
            _ = symbols.define(
                kind: .package,
                name: kotlinName,
                fqName: kotlinFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let rangesFQName: [InternedString] = [kotlinName, rangesName]
        let rangesPackageSymbol: SymbolID
        if let existing = symbols.lookup(fqName: rangesFQName) {
            rangesPackageSymbol = existing
        } else {
            rangesPackageSymbol = symbols.define(
                kind: .package,
                name: rangesName,
                fqName: rangesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        registerSyntheticProgressionStub(
            named: "IntProgression",
            elementType: types.intType,
            stepType: types.intType,
            externalLinkName: "kk_int_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "LongProgression",
            elementType: types.longType,
            stepType: types.intType,
            externalLinkName: "kk_long_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "UIntProgression",
            elementType: types.uintType,
            stepType: types.intType,
            externalLinkName: "kk_uint_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticUIntRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "ULongProgression",
            elementType: types.ulongType,
            stepType: types.intType,
            externalLinkName: "kk_ulong_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticULongRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticIntRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticLongRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCharRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticProgressionStub(
        named name: String,
        elementType: TypeID,
        stepType: TypeID,
        externalLinkName: String,
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
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

        let companionSymbol: SymbolID
        if let existing = symbols.companionObjectSymbol(for: classSymbol) {
            companionSymbol = existing
        } else {
            let companionName = interner.intern("Companion")
            let companionFQName = classFQName + [companionName]
            let created = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(classSymbol, for: created)
            symbols.setCompanionObjectSymbol(created, for: classSymbol)
            companionSymbol = created
        }

        guard let companionInfo = symbols.symbol(companionSymbol) else {
            return
        }
        let progressionType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: elementType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionName = interner.intern("fromClosedRange")
        let functionFQName = companionInfo.fqName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == companionType
                && signature.parameterTypes == [elementType, elementType, stepType]
        }) {
            return
        }

        let parameterNames = ["rangeStart", "rangeEnd", "step"].map(interner.intern)
        let parameterSymbols = parameterNames.map { parameterName in
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(companionSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(companionSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: companionType,
                parameterTypes: [elementType, elementType, stepType],
                returnType: progressionType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: [false, false, false],
                valueParameterIsVararg: [false, false, false]
            ),
            for: functionSymbol
        )

        let listType = syntheticListType(elementType: elementType, symbols: symbols, types: types, interner: interner)
        let firstLastRuntime: (String, String)
        switch name {
        case "UIntProgression":
            firstLastRuntime = ("kk_uint_range_first", "kk_uint_range_last")
        case "ULongProgression":
            firstLastRuntime = ("kk_ulong_range_first", "kk_ulong_range_last")
        case "LongProgression":
            firstLastRuntime = ("kk_long_range_first", "kk_long_range_last")
        default:
            firstLastRuntime = ("kk_range_first", "kk_range_last")
        }
        let stepRuntime: String
        switch name {
        case "UIntProgression": stepRuntime = "kk_uint_range_step"
        case "ULongProgression": stepRuntime = "kk_ulong_range_step"
        case "LongProgression": stepRuntime = "kk_long_range_step"
        default: stepRuntime = "kk_range_step"
        }
        let isEmptyRuntime: String
        switch name {
        case "UIntProgression": isEmptyRuntime = "kk_uint_range_isEmpty"
        case "ULongProgression": isEmptyRuntime = "kk_ulong_range_isEmpty"
        case "LongProgression": isEmptyRuntime = "kk_long_range_isEmpty"
        default: isEmptyRuntime = "kk_range_isEmpty"
        }
        let reversedRuntime: String
        let toListRuntime: String
        switch name {
        case "UIntProgression":
            reversedRuntime = "kk_uint_range_reversed"
            toListRuntime = "kk_uint_range_toList"
        case "ULongProgression":
            reversedRuntime = "kk_ulong_range_reversed"
            toListRuntime = "kk_ulong_range_toList"
        case "LongProgression":
            reversedRuntime = "kk_long_range_reversed"
            toListRuntime = "kk_long_range_toList"
        default:
            reversedRuntime = "kk_range_reversed"
            toListRuntime = "kk_range_toList"
        }

        registerProgressionProperty(
            named: "first",
            ownerSymbol: classSymbol,
            propertyType: elementType,
            externalLinkName: firstLastRuntime.0,
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "last",
            ownerSymbol: classSymbol,
            propertyType: elementType,
            externalLinkName: firstLastRuntime.1,
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: stepType,
            externalLinkName: stepRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: listType,
            externalLinkName: toListRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: progressionType,
            externalLinkName: reversedRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: isEmptyRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "step",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [stepType],
            returnType: progressionType,
            externalLinkName: name == "ULongProgression" ? "kk_ulong_step" : (name == "UIntProgression" ? "kk_uint_step" : "kk_op_step"),
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticUIntRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
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

        for property in [
            ("start", "kk_uint_range_first"),
            ("end", "kk_uint_range_last"),
            ("first", "kk_uint_range_first"),
            ("last", "kk_uint_range_last"),
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

    private func registerSyntheticULongRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
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

        for property in [
            ("start", "kk_ulong_range_first"),
            ("endInclusive", "kk_ulong_range_last"),
            ("first", "kk_ulong_range_first"),
            ("last", "kk_ulong_range_last"),
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

    private func registerProgressionProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if symbols.lookupAll(fqName: propertyFQName).contains(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func registerProgressionMethod(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
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

        let parameterSymbols = parameterTypes.enumerated().map { index, _ in
            let parameterName = interner.intern("p\(index)")
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: parameterSymbol)
            return parameterSymbol
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
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func syntheticListType(
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

    private func registerSyntheticIntRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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
    }

    private func registerSyntheticIntRangeConstructor(
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

    private func registerSyntheticIntRangeProperty(
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

    private func registerSyntheticIntRangeMethod(
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
        guard symbols.lookup(fqName: functionFQName) == nil else { return }

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

    private func syntheticPrimitiveArrayType(
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

    private func syntheticIteratorType(
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

    private func syntheticNominalType(
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

    private func registerSyntheticConstructor(
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

    private func registerSyntheticLongRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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

        // Properties: start, end, first, last, step
        for property in [
            ("start", "kk_long_range_first"),
            ("endInclusive", "kk_long_range_last"),
            ("first", "kk_long_range_first"),
            ("last", "kk_long_range_last"),
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

        // Methods: contains, isEmpty, iterator, reversed, toList, toLongArray
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

    private func registerSyntheticCharRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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
        let iteratorType = syntheticIteratorType(
            elementType: types.charType,
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

    private func registerIterableSupertype(
        classSymbol: SymbolID,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableInterfaceSymbol = symbols.lookup(fqName: iterableFQName) else {
            return
        }
        symbols.setDirectSupertypes([iterableInterfaceSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iterableInterfaceSymbol)
    }
}
