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
        let matchGroupCollectionSymbol = ensureClassSymbol(named: "MatchGroupCollection", in: kotlinTextPkg, symbols: symbols, interner: interner)
        let matchGroupSymbol = ensureClassSymbol(named: "MatchGroup", in: kotlinTextPkg, symbols: symbols, interner: interner)

        // --- Types ---
        let regexType = types.make(.classType(ClassType(
            classSymbol: regexSymbol, args: [], nullability: .nonNull
        )))
        let matchResultType = types.make(.classType(ClassType(
            classSymbol: matchResultSymbol, args: [], nullability: .nonNull
        )))
        let nullableMatchResultType = types.makeNullable(matchResultType)
        let matchGroupCollectionType = types.make(.classType(ClassType(
            classSymbol: matchGroupCollectionSymbol, args: [], nullability: .nonNull
        )))
        let matchGroupType = types.make(.classType(ClassType(
            classSymbol: matchGroupSymbol, args: [], nullability: .nonNull
        )))
        let nullableMatchGroupType = types.makeNullable(matchGroupType)
        let stringType = types.stringType
        let intType = types.intType
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

        // --- STDLIB-REGEX-097: Regex.groupNames: Set<String> ---
        let setStringType = makeSetType(
            symbols: symbols, types: types, interner: interner,
            elementType: stringType
        ) ?? listStringType
        registerRegexMemberProperty(
            named: "groupNames",
            externalLinkName: "kk_regex_group_names",
            ownerSymbol: regexSymbol,
            returnType: setStringType,
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

        // --- MatchResult.groups: MatchGroupCollection ---
        registerRegexMemberProperty(
            named: "groups",
            externalLinkName: "kk_match_result_groups",
            ownerSymbol: matchResultSymbol,
            returnType: matchGroupCollectionType,
            symbols: symbols,
            interner: interner
        )

        // --- MatchGroupCollection.get(name: String): MatchGroup? ---
        registerRegexMemberFunction(
            named: "get",
            externalLinkName: "kk_match_group_collection_get",
            ownerSymbol: matchGroupCollectionSymbol,
            ownerType: matchGroupCollectionType,
            parameters: [("name", stringType, false, false)],
            returnType: nullableMatchGroupType,
            symbols: symbols,
            interner: interner
        )

        // --- MatchGroup.value: String ---
        registerRegexMemberProperty(
            named: "value",
            externalLinkName: "kk_match_group_value",
            ownerSymbol: matchGroupSymbol,
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        // --- MatchGroup.range: IntRange (modeled as Int at runtime) ---
        registerRegexMemberProperty(
            named: "range",
            externalLinkName: "kk_match_group_range",
            ownerSymbol: matchGroupSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-REGEX-095: MatchResult.range ---
        registerRegexMemberProperty(
            named: "range",
            externalLinkName: "kk_match_result_range",
            ownerSymbol: matchResultSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-REGEX-095: MatchResult.component1() ---
        registerRegexMemberFunction(
            named: "component1",
            externalLinkName: "kk_match_result_component1",
            ownerSymbol: matchResultSymbol,
            ownerType: matchResultType,
            parameters: [],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-REGEX-095: MatchResult.component2() ---
        registerRegexMemberFunction(
            named: "component2",
            externalLinkName: "kk_match_result_component2",
            ownerSymbol: matchResultSymbol,
            ownerType: matchResultType,
            parameters: [],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-REGEX-095: MatchResult.next() ---
        registerRegexMemberFunction(
            named: "next",
            externalLinkName: "kk_match_result_next",
            ownerSymbol: matchResultSymbol,
            ownerType: matchResultType,
            parameters: [],
            returnType: nullableMatchResultType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-REGEX-095: MatchGroupCollection.get(index: Int) ---
        registerRegexMemberFunction(
            named: "get",
            externalLinkName: "kk_match_group_collection_get_at",
            ownerSymbol: matchGroupCollectionSymbol,
            ownerType: matchGroupCollectionType,
            parameters: [("index", intType, false, false)],
            returnType: nullableMatchGroupType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-350: Regex.matchEntire ---
        registerRegexMemberFunction(
            named: "matchEntire",
            externalLinkName: "kk_regex_matchEntire",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [("input", stringType, false, false)],
            returnType: nullableMatchResultType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-480: RegexOption enum class ---
        let regexOptionSymbol = ensureRegexOptionEnumClass(
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let regexOptionType = types.make(.classType(ClassType(
            classSymbol: regexOptionSymbol, args: [], nullability: .nonNull
        )))

        // Set property types for enum entries so that
        // resolveClassNameMemberValue can resolve e.g. RegexOption.DOT_MATCHES_ALL.
        setRegexOptionEntryTypes(
            enumSymbol: regexOptionSymbol,
            enumType: regexOptionType,
            symbols: symbols
        )

        // --- STDLIB-480: Regex(pattern, option) constructor ---
        registerRegexTopLevelFunction(
            named: "Regex",
            packageFQName: kotlinTextPkg,
            parameters: [("pattern", stringType), ("option", regexOptionType)],
            returnType: regexType,
            externalLinkName: "kk_regex_create_with_option",
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-480: Regex(pattern, options) constructor ---
        // Only register the Set<RegexOption> overload if kotlin.collections.Set
        // is available. Otherwise we would create an unintended Regex(String, Any)
        // overload that confuses overload resolution.
        if let setRegexOptionType = makeSetType(
            symbols: symbols, types: types, interner: interner,
            elementType: regexOptionType
        ) {
            registerRegexTopLevelFunction(
                named: "Regex",
                packageFQName: kotlinTextPkg,
                parameters: [("pattern", stringType), ("options", setRegexOptionType)],
                returnType: regexType,
                externalLinkName: "kk_regex_create_with_options",
                symbols: symbols,
                interner: interner
            )
        }

        // --- STDLIB-480: Regex.containsMatchIn(input) ---
        let boolType = types.make(.primitive(.boolean, .nonNull))
        registerRegexMemberFunction(
            named: "matches",
            externalLinkName: "kk_regex_matches",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [("input", stringType, false, false)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerRegexMemberFunction(
            named: "containsMatchIn",
            externalLinkName: "kk_regex_containsMatchIn",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [("input", stringType, false, false)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-351: Regex.replace(input) { lambda } ---
        let matchResultToStringLambda = types.make(.functionType(FunctionType(
            params: [matchResultType],
            returnType: stringType,
            nullability: .nonNull
        )))
        registerRegexMemberFunction(
            named: "replace",
            externalLinkName: "kk_regex_replace_lambda",
            ownerSymbol: regexSymbol,
            ownerType: regexType,
            parameters: [
                ("input", stringType, false, false),
                ("transform", matchResultToStringLambda, false, false),
            ],
            returnType: stringType,
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

    // MARK: - STDLIB-480: RegexOption enum

    private func ensureRegexOptionEnumClass(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("RegexOption")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: symbol)
        }

        // Register enum entries
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL", "LITERAL",
            "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: entrySymbol)
        }
        return symbol
    }

    /// Set propertyType on each enum entry so that resolveClassNameMemberValue
    /// (which checks `.field` + propertyType) can resolve `RegexOption.XXX`.
    private func setRegexOptionEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func makeSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID? {
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let setSymbol = symbols.lookup(fqName: setFQName), setSymbol != .invalid else {
            // Do not fall back to anyType -- that would register an unintended
            // Regex(pattern, options: Any) overload.
            return nil
        }
        return types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
