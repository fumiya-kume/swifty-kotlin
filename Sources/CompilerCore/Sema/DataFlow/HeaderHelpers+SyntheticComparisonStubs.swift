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

        let comparatorFQName = kotlinPkg + [interner.intern("Comparator")]
        guard let comparatorSymbol = symbols.lookup(fqName: comparatorFQName) else {
            return
        }

        registerCompareValuesAndCompareValuesBy(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
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

    private func registerSyntheticComparisonFunction(
        named name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        parameterNames: [String],
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
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
                valueParameterIsVararg: Array(repeating: false, count: parameterNames.count)
            ),
            for: functionSymbol
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
}
