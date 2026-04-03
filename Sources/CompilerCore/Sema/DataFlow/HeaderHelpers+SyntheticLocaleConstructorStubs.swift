extension DataFlowSemaPhase {
    func registerSyntheticLocaleConstructorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let localeSymbol = ensureClassSymbol(named: "Locale", in: javaUtilPkg, symbols: symbols, interner: interner)
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: localeSymbol)
        }

        let localeType = types.make(.classType(ClassType(
            classSymbol: localeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(localeType, for: localeSymbol)

        let arrayType = makeSyntheticLocaleArrayType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: localeType
        )

        registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("identifier", types.stringType)],
            externalLinkName: "kk_locale_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("language", types.stringType), ("country", types.stringType)],
            externalLinkName: "kk_locale_new_language_country",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticLocaleProperty(
            ownerSymbol: localeSymbol,
            name: "language",
            propertyType: types.stringType,
            externalLinkName: "kk_locale_language",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleProperty(
            ownerSymbol: localeSymbol,
            name: "country",
            propertyType: types.stringType,
            externalLinkName: "kk_locale_country",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleProperty(
            ownerSymbol: localeSymbol,
            name: "variant",
            propertyType: types.stringType,
            externalLinkName: "kk_locale_variant",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleProperty(
            ownerSymbol: localeSymbol,
            name: "displayLanguage",
            propertyType: types.stringType,
            externalLinkName: "kk_locale_displayLanguage",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleMethod(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            name: "hashCode",
            parameterTypes: [],
            returnType: types.intType,
            externalLinkName: "kk_locale_hashCode",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleMethod(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            name: "equals",
            parameterTypes: [types.nullableAnyType],
            returnType: types.booleanType,
            externalLinkName: "kk_locale_equals",
            symbols: symbols,
            interner: interner
        )

        let companionFQName = ensureSyntheticLocaleCompanionSymbol(
            ownerSymbol: localeSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleCompanionMethod(
            named: "getDefault",
            externalLinkName: "kk_locale_getDefault",
            returnType: localeType,
            parameters: [],
            companionFQName: companionFQName,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleCompanionMethod(
            named: "setDefault",
            externalLinkName: "kk_locale_setDefault",
            returnType: types.unitType,
            parameters: [("locale", localeType)],
            companionFQName: companionFQName,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleCompanionMethod(
            named: "getAvailableLocales",
            externalLinkName: "kk_locale_getAvailableLocales",
            returnType: arrayType,
            parameters: [],
            companionFQName: companionFQName,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func makeSyntheticLocaleArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func ensureSyntheticLocaleCompanionSymbol(
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

    private func registerSyntheticLocaleConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else { return }

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

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticLocaleProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
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

    private func registerSyntheticLocaleCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        companionFQName: [InternedString],
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type) &&
                signature.returnType == returnType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }

        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: companionType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticLocaleMethod(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType &&
                signature.parameterTypes == parameterTypes &&
                signature.returnType == returnType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for index in parameterTypes.indices {
            let parameterName = interner.intern(index == 0 ? "other" : "arg\(index)")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
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
}
