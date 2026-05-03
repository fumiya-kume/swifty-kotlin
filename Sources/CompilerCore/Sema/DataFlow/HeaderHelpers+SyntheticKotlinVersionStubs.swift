extension DataFlowSemaPhase {
    func registerSyntheticKotlinVersionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let classSymbol = ensureClassSymbol(
            named: "KotlinVersion",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        if let comparableSymbol = types.comparableInterfaceSymbol {
            addKotlinVersionComparableSupertype(
                ownerSymbol: classSymbol,
                ownerType: classType,
                comparableSymbol: comparableSymbol,
                symbols: symbols,
                types: types
            )
        }
        _ = ensureKotlinVersionCompanionSymbol(
            ownerSymbol: classSymbol,
            symbols: symbols,
            interner: interner
        )
        if let companionSymbol = symbols.companionObjectSymbol(for: classSymbol) {
            registerKotlinVersionProperty(
                named: "CURRENT",
                externalLinkName: "kk_kotlin_version_current",
                ownerSymbol: companionSymbol,
                returnType: classType,
                flags: [.synthetic, .static],
                symbols: symbols,
                interner: interner
            )
        }

        registerKotlinVersionConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [
                ("major", types.intType),
                ("minor", types.intType),
            ],
            externalLinkName: "kk_kotlin_version_new",
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [
                ("major", types.intType),
                ("minor", types.intType),
                ("patch", types.intType),
            ],
            externalLinkName: "kk_kotlin_version_new_patch",
            symbols: symbols,
            interner: interner
        )

        registerKotlinVersionProperty(
            named: "major",
            externalLinkName: "kk_kotlin_version_major",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionProperty(
            named: "minor",
            externalLinkName: "kk_kotlin_version_minor",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionProperty(
            named: "patch",
            externalLinkName: "kk_kotlin_version_patch",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionMemberFunction(
            named: "compareTo",
            externalLinkName: "kk_kotlin_version_compareTo",
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameterTypes: [classType],
            returnType: types.intType,
            flags: [.synthetic, .operatorFunction, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionMemberFunction(
            named: "isAtLeast",
            externalLinkName: "kk_kotlin_version_isAtLeast",
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameterTypes: [types.intType, types.intType],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionMemberFunction(
            named: "isAtLeast",
            externalLinkName: "kk_kotlin_version_isAtLeast_patch",
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameterTypes: [types.intType, types.intType, types.intType],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureKotlinVersionCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    private func addKotlinVersionComparableSupertype(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        comparableSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        let currentSymbolSupertypes = symbols.directSupertypes(for: ownerSymbol)
        if !currentSymbolSupertypes.contains(comparableSymbol) {
            symbols.setDirectSupertypes(currentSymbolSupertypes + [comparableSymbol], for: ownerSymbol)
        }

        let currentTypeSupertypes = types.directNominalSupertypes(for: ownerSymbol)
        if !currentTypeSupertypes.contains(comparableSymbol) {
            types.setNominalDirectSupertypes(currentTypeSupertypes + [comparableSymbol], for: ownerSymbol)
        }

        let comparableArgs: [TypeArg] = [.in(ownerType)]
        symbols.setSupertypeTypeArgs(comparableArgs, for: ownerSymbol, supertype: comparableSymbol)
        types.setNominalSupertypeTypeArgs(comparableArgs, for: ownerSymbol, supertype: comparableSymbol)
    }

    private func registerKotlinVersionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let existing = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }
        guard !existing else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: constructorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    private func registerKotlinVersionMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == ownerType && signature.parameterTypes == parameterTypes
        }) {
            symbols.insertFlags(flags, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let signature = symbols.functionSignature(for: existing),
               signature.returnType != returnType
            {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: ownerType,
                        parameterTypes: parameterTypes,
                        returnType: returnType,
                        isSuspend: signature.isSuspend,
                        canThrow: signature.canThrow,
                        valueParameterSymbols: signature.valueParameterSymbols,
                        valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: signature.valueParameterIsVararg,
                        typeParameterSymbols: signature.typeParameterSymbols,
                        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                        typeParameterUpperBounds: signature.typeParameterUpperBounds,
                        typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                        classTypeParameterCount: signature.classTypeParameterCount
                    ),
                    for: existing
                )
            }
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

        var valueParameterSymbols: [SymbolID] = []
        for (index, parameterType) in parameterTypes.enumerated() {
            let parameterName = interner.intern("p\(index)")
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameterType, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerKotlinVersionProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(returnType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.insertFlags(flags, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }
}
