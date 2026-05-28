import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticComparisonStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let comparisonsPackageSymbol = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        // 2-arg overloads: Int, Long, Double, Float
        let twoArgTypes: [(TypeID, TypeID)] = [
            (types.intType, types.intType),
            (types.longType, types.longType),
            (types.doubleType, types.doubleType),
            (types.floatType, types.floatType),
        ]
        for (paramType, returnType) in twoArgTypes {
            registerSyntheticComparisonFunction(
                named: "maxOf",
                parameterTypes: [paramType, paramType],
                returnType: returnType,
                parameterNames: ["a", "b"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: "minOf",
                parameterTypes: [paramType, paramType],
                returnType: returnType,
                parameterNames: ["a", "b"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
        }

        // 3-arg overloads: Int, Long, Double, Float
        let threeArgTypes: [(TypeID, TypeID)] = [
            (types.intType, types.intType),
            (types.longType, types.longType),
            (types.doubleType, types.doubleType),
            (types.floatType, types.floatType),
        ]
        for (paramType, returnType) in threeArgTypes {
            registerSyntheticComparisonFunction(
                named: "maxOf",
                parameterTypes: [paramType, paramType, paramType],
                returnType: returnType,
                parameterNames: ["a", "b", "c"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: "minOf",
                parameterTypes: [paramType, paramType, paramType],
                returnType: returnType,
                parameterNames: ["a", "b", "c"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticMaxOfComparableStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )
        registerSyntheticMinOfComparable3Stub(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )
        registerSyntheticMinOfComparableVarargStub(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )

        let comparatorFQName = kotlinPkg + [interner.intern("Comparator")]
        guard let comparatorSymbol = symbols.lookup(fqName: comparatorFQName) else {
            return
        }

        registerSyntheticMaxOfComparatorStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
        registerSyntheticMinOfUnsignedStub(
            typeID: types.ushortType,
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )

        registerSyntheticMaxOfUnsignedStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )
        registerSyntheticMinOfUnsignedStub(
            typeID: types.ubyteType,
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )
        registerSyntheticMinOfUnsignedStub(
            typeID: types.uintType,
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )

        registerCompareValuesAndCompareValuesBy(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
        registerSyntheticMinOfUnsignedStub(
            typeID: types.ulongType,
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol
        )
    }

    private func registerSyntheticComparisonFunction(
        named name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        parameterNames: [String],
        valueParameterIsVararg: [Bool] = [],
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let normalizedVararg = valueParameterIsVararg.isEmpty
            ? Array(repeating: false, count: parameterNames.count)
            : valueParameterIsVararg
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.valueParameterIsVararg == normalizedVararg
                && signature.typeParameterSymbols.count == typeParameterSymbols.count
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for paramName in parameterNames {
            let internedName = interner.intern(paramName)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: internedName,
                fqName: functionFQName + [internedName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterNames.count),
                valueParameterIsVararg: normalizedVararg,
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticMaxOfComparableStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID
    ) {
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return
        }

        let maxOfName = "maxOf"
        let functionName = interner.intern(maxOfName)
        let functionFQName = comparisonsPkg + [functionName]
        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol = symbols.lookup(fqName: tParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let comparableUpperBounds: [TypeID] = [types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(tParamType)],
            nullability: .nonNull
        )))]

        registerSyntheticComparisonFunction(
            named: maxOfName,
            parameterTypes: [tParamType, tParamType],
            returnType: tParamType,
            parameterNames: ["a", "b"],
            typeParameterSymbols: [tParamSymbol],
            typeParameterUpperBoundsList: [comparableUpperBounds],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticComparisonFunction(
            named: maxOfName,
            parameterTypes: [tParamType, tParamType, tParamType],
            returnType: tParamType,
            parameterNames: ["a", "b", "c"],
            typeParameterSymbols: [tParamSymbol],
            typeParameterUpperBoundsList: [comparableUpperBounds],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticComparisonFunction(
            named: maxOfName,
            parameterTypes: [tParamType],
            returnType: tParamType,
            parameterNames: ["a"],
            valueParameterIsVararg: [true],
            typeParameterSymbols: [tParamSymbol],
            typeParameterUpperBoundsList: [comparableUpperBounds],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMinOfComparable3Stub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID
    ) {
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return
        }

        let minOfName = "minOf"
        let functionName = interner.intern(minOfName)
        let functionFQName = comparisonsPkg + [functionName]
        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol = symbols.lookup(fqName: tParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let comparableUpperBounds: [TypeID] = [types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(tParamType)],
            nullability: .nonNull
        )))]

        registerSyntheticComparisonFunction(
            named: minOfName,
            parameterTypes: [tParamType, tParamType, tParamType],
            returnType: tParamType,
            parameterNames: ["a", "b", "c"],
            typeParameterSymbols: [tParamSymbol],
            typeParameterUpperBoundsList: [comparableUpperBounds],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMinOfComparableVarargStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID
    ) {
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return
        }

        let minOfName = "minOf"
        let functionName = interner.intern(minOfName)
        let functionFQName = comparisonsPkg + [functionName]
        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol = symbols.lookup(fqName: tParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let comparableUpperBounds: [TypeID] = [types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(tParamType)],
            nullability: .nonNull
        )))]

        registerSyntheticComparisonFunction(
            named: minOfName,
            parameterTypes: [tParamType],
            returnType: tParamType,
            parameterNames: ["a"],
            valueParameterIsVararg: [true],
            typeParameterSymbols: [tParamSymbol],
            typeParameterUpperBoundsList: [comparableUpperBounds],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMaxOfComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        for functionName in ["maxOf", "minOf"] {
            let functionNameID = interner.intern(functionName)
            let functionFQName = comparisonsPkg + [functionNameID]
            let tParamName = interner.intern("T")
            let tParamFQName = functionFQName + [tParamName]
            let tParamSymbol = symbols.lookup(fqName: tParamFQName) ?? symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let tParamType = types.make(.typeParam(TypeParamType(
                symbol: tParamSymbol,
                nullability: .nonNull
            )))
            let comparatorType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(tParamType)],
                nullability: .nonNull
            )))

            registerSyntheticComparisonFunction(
                named: functionName,
                parameterTypes: [tParamType, tParamType, comparatorType],
                returnType: tParamType,
                parameterNames: ["a", "b", "comparator"],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: functionName,
                parameterTypes: [tParamType, tParamType, tParamType, comparatorType],
                returnType: tParamType,
                parameterNames: ["a", "b", "c", "comparator"],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: functionName,
                parameterTypes: [tParamType, tParamType, comparatorType],
                returnType: tParamType,
                parameterNames: ["a", "other", "comparator"],
                valueParameterIsVararg: [false, true, false],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticMaxOfUnsignedStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID
    ) {
        let unsignedTypes: [(String, TypeID)] = [
            ("UByte", types.ubyteType),
            ("UShort", types.ushortType),
            ("UInt", types.uintType),
            ("ULong", types.ulongType),
        ]

        for (_, typeID) in unsignedTypes {
            registerSyntheticComparisonFunction(
                named: "maxOf",
                parameterTypes: [typeID, typeID],
                returnType: typeID,
                parameterNames: ["a", "b"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: "maxOf",
                parameterTypes: [typeID, typeID, typeID],
                returnType: typeID,
                parameterNames: ["a", "b", "c"],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticComparisonFunction(
                named: "maxOf",
                parameterTypes: [typeID, typeID],
                returnType: typeID,
                parameterNames: ["a", "other"],
                valueParameterIsVararg: [false, true],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                types: types,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticMinOfUnsignedStub(
        typeID: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID
    ) {
        registerSyntheticComparisonFunction(
            named: "minOf",
            parameterTypes: [typeID, typeID],
            returnType: typeID,
            parameterNames: ["a", "b"],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticComparisonFunction(
            named: "minOf",
            parameterTypes: [typeID, typeID, typeID],
            returnType: typeID,
            parameterNames: ["a", "b", "c"],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticComparisonFunction(
            named: "minOf",
            parameterTypes: [typeID, typeID],
            returnType: typeID,
            parameterNames: ["a", "other"],
            valueParameterIsVararg: [false, true],
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerCompareValuesAndCompareValuesBy(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        registerCompareValues(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

        for arity in 1...3 {
            registerCompareValuesBy(
                selectorArity: arity,
                symbols: symbols,
                types: types,
                interner: interner,
                comparisonsPkg: comparisonsPkg,
                comparisonsPackageSymbol: comparisonsPackageSymbol,
                comparatorSymbol: comparatorSymbol
            )
        }

        registerCompareValuesByVararg(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
        registerCompareValuesByComparatorSelector(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
    }

    private func registerCompareValues(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("compareValues")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_compareValues"

        guard let comparatorInfo = symbols.symbol(comparatorSymbol) else {
            return
        }
        let comparatorFQName = comparatorInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else {
            return
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let nullableTParamType = types.makeNullable(tParamType)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 2 && sig.returnType == types.intType
        }) {
            symbols.setExternalLinkName(extLink, for: existing)
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let aName = interner.intern("a")
        let bName = interner.intern("b")
        let aSymbol = symbols.define(
            kind: .valueParameter,
            name: aName,
            fqName: functionFQName + [interner.intern("a_compareValues")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let bSymbol = symbols.define(
            kind: .valueParameter,
            name: bName,
            fqName: functionFQName + [interner.intern("b_compareValues")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(funcSymbol, for: aSymbol)
        symbols.setParentSymbol(funcSymbol, for: bSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [nullableTParamType, nullableTParamType],
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: [aSymbol, bSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }

    private func registerCompareValuesBy(
        selectorArity: Int,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("compareValuesBy")
        let functionFQName = comparisonsPkg + [functionName]
        let expectedParameterCount = 2 + selectorArity
        let extLink = switch selectorArity {
        case 1: "kk_compareValuesBy1"
        case 2: "kk_compareValuesBy"
        default: "kk_compareValuesBy3"
        }

        guard let comparatorInfo = symbols.symbol(comparatorSymbol) else {
            return
        }
        let comparatorFQName = comparatorInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else {
            return
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == expectedParameterCount && sig.returnType == types.intType
        }) {
            symbols.setExternalLinkName(extLink, for: existing)
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let aName = interner.intern("a")
        let bName = interner.intern("b")
        let aSymbol = symbols.define(
            kind: .valueParameter,
            name: aName,
            fqName: functionFQName + [interner.intern("a_compareValuesBy$arity\(selectorArity)")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let bSymbol = symbols.define(
            kind: .valueParameter,
            name: bName,
            fqName: functionFQName + [interner.intern("b_compareValuesBy$arity\(selectorArity)")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(funcSymbol, for: aSymbol)
        symbols.setParentSymbol(funcSymbol, for: bSymbol)

        var parameterTypes: [TypeID] = [tParamType, tParamType]
        var parameterSymbols: [SymbolID] = [aSymbol, bSymbol]
        for index in 0..<selectorArity {
            let selectorName = interner.intern("selector\(index + 1)")
            let selectorSymbol = symbols.define(
                kind: .valueParameter,
                name: selectorName,
                fqName: functionFQName + [interner.intern("selector\(index + 1)_compareValuesBy$arity\(selectorArity)")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSymbol, for: selectorSymbol)
            parameterTypes.append(selectorType)
            parameterSymbols.append(selectorSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count),
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }

    private func registerCompareValuesByVararg(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("compareValuesBy")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_compareValuesByVararg"

        guard let comparatorInfo = symbols.symbol(comparatorSymbol) else {
            return
        }
        let comparatorFQName = comparatorInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else {
            return
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let parameterTypes = [tParamType, tParamType, selectorType]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == parameterTypes &&
                sig.returnType == types.intType &&
                sig.valueParameterIsVararg == [false, false, true]
        }) {
            symbols.setExternalLinkName(extLink, for: existing)
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let parameterSymbols: [SymbolID] = ["a", "b", "selectors"].map { name in
            let internedName = interner.intern(name)
            let symbol = symbols.define(
                kind: .valueParameter,
                name: internedName,
                fqName: functionFQName + [interner.intern("\(name)_compareValuesByVararg")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSymbol, for: symbol)
            return symbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: [false, false, true],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }

    private func registerCompareValuesByComparatorSelector(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("compareValuesBy")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_compareValuesByComparator"

        let tParamSymbol = defineSyntheticTypeParameter(
            named: "T",
            fqName: functionFQName + [interner.intern("T_compareValuesByComparator")],
            symbols: symbols,
            interner: interner
        )
        let kParamSymbol = defineSyntheticTypeParameter(
            named: "K",
            fqName: functionFQName + [interner.intern("K_compareValuesByComparator")],
            symbols: symbols,
            interner: interner
        )
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let kParamType = types.make(.typeParam(TypeParamType(symbol: kParamSymbol, nullability: .nonNull)))
        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(kParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: kParamType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let parameterTypes = [tParamType, tParamType, comparatorType, selectorType]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == parameterTypes && sig.returnType == types.intType
        }) {
            symbols.setExternalLinkName(extLink, for: existing)
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let parameterSymbols: [SymbolID] = ["a", "b", "comparator", "selector"].map { name in
            let internedName = interner.intern(name)
            let symbol = symbols.define(
                kind: .valueParameter,
                name: internedName,
                fqName: functionFQName + [interner.intern("\(name)_compareValuesByComparator")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSymbol, for: symbol)
            return symbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count),
                typeParameterSymbols: [tParamSymbol, kParamSymbol],
                typeParameterUpperBoundsList: [[], []]
            ),
            for: funcSymbol
        )
    }

    private func defineSyntheticTypeParameter(
        named name: String,
        fqName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: interner.intern(name),
            fqName: fqName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
    }
}
