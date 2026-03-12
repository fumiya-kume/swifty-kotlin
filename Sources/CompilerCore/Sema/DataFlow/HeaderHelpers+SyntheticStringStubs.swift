import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let stringType = types.stringType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let intType = types.intType
        let longType = types.make(.primitive(.long, .nonNull))
        let charType = types.make(.primitive(.char, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))
        let nullableDoubleType = types.make(.primitive(.double, .nullable))
        let nullableCharType = types.make(.primitive(.char, .nullable))
        let doubleType = types.doubleType
        let listStringType = makeListOfStringType(symbols: symbols, types: types, interner: interner)
        let listCharType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )

        registerSyntheticStringExtensionFunction(
            named: "length",
            externalLinkName: "kk_string_length",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "trim",
            externalLinkName: "kk_string_trim",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "lowercase",
            externalLinkName: "kk_string_lowercase",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "uppercase",
            externalLinkName: "kk_string_uppercase",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "replace",
            externalLinkName: "kk_string_replace",
            receiverType: stringType,
            parameters: [
                ("oldValue", stringType, false, false),
                ("newValue", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "startsWith",
            externalLinkName: "kk_string_startsWith",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "endsWith",
            externalLinkName: "kk_string_endsWith",
            receiverType: stringType,
            parameters: [
                ("suffix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "contains",
            externalLinkName: "kk_string_contains_str",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: boolType,
            flags: [.synthetic, .operatorFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toInt",
            externalLinkName: "kk_string_toInt",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // String.toInt(radix: Int) (STDLIB-152)
        registerSyntheticStringExtensionFunction(
            named: "toInt",
            externalLinkName: "kk_string_toInt_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toIntOrNull",
            externalLinkName: "kk_string_toIntOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toDouble",
            externalLinkName: "kk_string_toDouble",
            receiverType: stringType,
            parameters: [],
            returnType: doubleType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toDoubleOrNull",
            externalLinkName: "kk_string_toDoubleOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableDoubleType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "substring",
            externalLinkName: "kk_string_substring",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "substring",
            externalLinkName: "kk_string_substring",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "format",
            externalLinkName: "kk_string_format",
            receiverType: stringType,
            parameters: [
                ("args", types.nullableAnyType, false, true),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // Int.toString(radix: Int) / Long.toString(radix: Int) (STDLIB-152)
        registerSyntheticStringExtensionFunction(
            named: "toString",
            externalLinkName: "kk_int_toString_radix",
            receiverType: intType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "toString",
            externalLinkName: "kk_int_toString_radix",
            receiverType: longType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "trimIndent",
            externalLinkName: "kk_string_trimIndent",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "trimMargin",
            externalLinkName: "kk_string_trimMargin_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "trimMargin",
            externalLinkName: "kk_string_trimMargin",
            receiverType: stringType,
            parameters: [
                ("marginPrefix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "indexOf",
            externalLinkName: "kk_string_indexOf",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "lastIndexOf",
            externalLinkName: "kk_string_lastIndexOf",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "repeat",
            externalLinkName: "kk_string_repeat",
            receiverType: stringType,
            parameters: [
                ("count", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "reversed",
            externalLinkName: "kk_string_reversed",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toList",
            externalLinkName: "kk_string_toList",
            receiverType: stringType,
            parameters: [],
            returnType: listCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toCharArray",
            externalLinkName: "kk_string_toCharArray",
            receiverType: stringType,
            parameters: [],
            returnType: listCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "padStart",
            externalLinkName: "kk_string_padStart",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
                ("padChar", charType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "padEnd",
            externalLinkName: "kk_string_padEnd",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
                ("padChar", charType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "drop",
            externalLinkName: "kk_string_drop",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "take",
            externalLinkName: "kk_string_take",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "dropLast",
            externalLinkName: "kk_string_dropLast",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "takeLast",
            externalLinkName: "kk_string_takeLast",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-185: removePrefix / removeSuffix / removeSurrounding ---

        registerSyntheticStringExtensionFunction(
            named: "removePrefix",
            externalLinkName: "kk_string_removePrefix",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSuffix",
            externalLinkName: "kk_string_removeSuffix",
            receiverType: stringType,
            parameters: [
                ("suffix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding_pair",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
                ("suffix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-186: substringBefore / substringAfter / substringBeforeLast / substringAfterLast ---

        registerSyntheticStringExtensionFunction(
            named: "substringBefore",
            externalLinkName: "kk_string_substringBefore",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "substringAfter",
            externalLinkName: "kk_string_substringAfter",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "substringBeforeLast",
            externalLinkName: "kk_string_substringBeforeLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "substringAfterLast",
            externalLinkName: "kk_string_substringAfterLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-100/102/103: Regex-related String extensions ---

        let regexSymbol = ensureClassSymbol(
            named: "Regex", in: kotlinTextPkg,
            symbols: symbols, interner: interner
        )
        let regexType = types.make(.classType(ClassType(
            classSymbol: regexSymbol, args: [], nullability: .nonNull
        )))

        registerSyntheticStringExtensionFunction(
            named: "matches",
            externalLinkName: "kk_string_matches_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "contains",
            externalLinkName: "kk_string_contains_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "replace",
            externalLinkName: "kk_string_replace_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
                ("replacement", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toRegex",
            externalLinkName: "kk_string_toRegex",
            receiverType: stringType,
            parameters: [],
            returnType: regexType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-140: String.get(Int): Char ---

        registerSyntheticStringExtensionFunction(
            named: "get",
            externalLinkName: "kk_string_get",
            receiverType: stringType,
            parameters: [
                ("index", intType, false, false),
            ],
            returnType: charType,
            flags: [.synthetic, .operatorFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-141: String.compareTo ---

        registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareTo_member",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareToIgnoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-187: isEmpty / isNotEmpty / isBlank / isNotBlank ---

        registerSyntheticStringExtensionFunction(
            named: "isEmpty",
            externalLinkName: "kk_string_isEmpty",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "isNotEmpty",
            externalLinkName: "kk_string_isNotEmpty",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "isBlank",
            externalLinkName: "kk_string_isBlank",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "isNotBlank",
            externalLinkName: "kk_string_isNotBlank",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-190: first / last / single / firstOrNull / lastOrNull ---

        registerSyntheticStringExtensionFunction(
            named: "first",
            externalLinkName: "kk_string_first",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "last",
            externalLinkName: "kk_string_last",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "single",
            externalLinkName: "kk_string_single",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "firstOrNull",
            externalLinkName: "kk_string_firstOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "lastOrNull",
            externalLinkName: "kk_string_lastOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-142: String.toBoolean / toBooleanStrict ---

        registerSyntheticStringExtensionFunction(
            named: "toBoolean",
            externalLinkName: "kk_string_toBoolean",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toBooleanStrict",
            externalLinkName: "kk_string_toBooleanStrict",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-143: String.lines ---

        registerSyntheticStringExtensionFunction(
            named: "lines",
            externalLinkName: "kk_string_lines",
            receiverType: stringType,
            parameters: [],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-144: String.trimStart / trimEnd ---

        registerSyntheticStringExtensionFunction(
            named: "trimStart",
            externalLinkName: "kk_string_trimStart",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "trimEnd",
            externalLinkName: "kk_string_trimEnd",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-145: String.toByteArray / encodeToByteArray ---

        let listIntType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: intType
        )

        registerSyntheticStringExtensionFunction(
            named: "toByteArray",
            externalLinkName: "kk_string_toByteArray",
            receiverType: stringType,
            parameters: [],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_string_toByteArray",
            receiverType: stringType,
            parameters: [],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
    }

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

    private func registerSyntheticStringExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
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
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []
        parameterTypes.reserveCapacity(parameters.count)
        parameterSymbols.reserveCapacity(parameters.count)
        parameterDefaults.reserveCapacity(parameters.count)
        parameterVarargs.reserveCapacity(parameters.count)

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
                receiverType: receiverType,
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
}
