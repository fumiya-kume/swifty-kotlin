import Foundation

/// Synthetic stubs for Regex, MatchResult, and related methods (STDLIB-100/101/103).
extension DataFlowSemaPhase {
    func registerSyntheticRegexStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)

        // --- Class symbols ---
        let regexSymbol = ensureClassSymbol(named: "Regex", in: kotlinTextPkg, symbols: symbols, interner: interner)
        let matchResultSymbol = ensureClassSymbol(named: "MatchResult", in: kotlinTextPkg, symbols: symbols, interner: interner)

        // --- Types ---
        let regexType = types.make(.classType(ClassType(
            classSymbol: regexSymbol, args: [], nullability: .nonNull
        )))
        let matchResultType = types.make(.classType(ClassType(
            classSymbol: matchResultSymbol, args: [], nullability: .nonNull
        )))
        let nullableMatchResultType = types.makeNullable(matchResultType)
        let stringType = types.stringType
        let listStringType = makeListOfStringType(symbols: symbols, types: types, interner: interner)
        let listMatchResultType = makeListType(
            symbols: symbols, types: types, interner: interner,
            elementType: matchResultType
        )

        // --- STDLIB-100: Regex(pattern) constructor (top-level function) ---
        registerRegexTopLevelFunction(
            named: "Regex",
            packageFQName: kotlinTextPkg,
            parameters: [("pattern", stringType)],
            returnType: regexType,
            externalLinkName: "kk_regex_create",
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-101: Regex.find / Regex.findAll ---
        registerRegexMemberFunction(
            named: "find",
            externalLinkName: "kk_regex_find",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [("input", stringType, false, false)],
            returnType: nullableMatchResultType,
            symbols: symbols,
            interner: interner
        )

        registerRegexMemberFunction(
            named: "findAll",
            externalLinkName: "kk_regex_findAll",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [("input", stringType, false, false)],
            returnType: listMatchResultType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-103: Regex.pattern ---
        registerRegexMemberProperty(
            named: "pattern",
            externalLinkName: "kk_regex_pattern",
            ownerSymbol: regexSymbol,
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-101: MatchResult.value / MatchResult.groupValues ---
        registerRegexMemberProperty(
            named: "value",
            externalLinkName: "kk_match_result_value",
            ownerSymbol: matchResultSymbol,
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        registerRegexMemberProperty(
            named: "groupValues",
            externalLinkName: "kk_match_result_groupValues",
            ownerSymbol: matchResultSymbol,
            returnType: listStringType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    private func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }

    private func makeListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        makeListType(symbols: symbols, types: types, interner: interner, elementType: types.stringType)
    }

    private func registerRegexTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerRegexMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    private func registerRegexMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
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
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
