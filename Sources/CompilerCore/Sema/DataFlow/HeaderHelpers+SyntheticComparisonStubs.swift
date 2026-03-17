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
}
