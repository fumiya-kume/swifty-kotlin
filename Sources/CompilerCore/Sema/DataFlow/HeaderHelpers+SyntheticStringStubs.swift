import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinRootPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let stringType = types.stringType
        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinRootPkg,
            symbols: symbols,
            interner: interner
        )
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol, args: [], nullability: .nonNull
        )))
        types.charSequenceInterfaceSymbol = charSequenceSymbol
        if let kotlinRootPkgSymbol = symbols.lookup(fqName: kotlinRootPkg) {
            symbols.setParentSymbol(kotlinRootPkgSymbol, for: charSequenceSymbol)
        }
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableBoolType = types.make(.primitive(.boolean, .nullable))
        let intType = types.intType
        let longType = types.make(.primitive(.long, .nonNull))
        let charType = types.make(.primitive(.char, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))
        let nullableDoubleType = types.make(.primitive(.double, .nullable))
        let nullableLongType = types.make(.primitive(.long, .nullable))
        let nullableFloatType = types.make(.primitive(.float, .nullable))
        let nullableCharType = types.make(.primitive(.char, .nullable))
        let floatType = types.floatType
        let doubleType = types.doubleType
        let stringProducerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: stringType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listStringType = makeListOfStringType(symbols: symbols, types: types, interner: interner)
        let listCharType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )
        let charArrayType = makeNominalType(
            symbols: symbols,
            types: types,
            fqName: [interner.intern("kotlin"), interner.intern("CharArray")]
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

        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let localeSymbol = ensureClassSymbol(
            named: "Locale",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: localeSymbol)
        }
        let localeType = types.make(.classType(ClassType(
            classSymbol: localeSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(localeType, for: localeSymbol)

        registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("identifier", stringType)],
            externalLinkName: "kk_locale_new",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "lowercase",
            externalLinkName: "kk_string_lowercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "uppercase",
            externalLinkName: "kk_string_uppercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareTo_locale",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("locale", localeType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        let normalizationFormSymbol = ensureClassSymbol(
            named: "NormalizationForm",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let normalizationFormType = types.make(.classType(ClassType(
            classSymbol: normalizationFormSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(normalizationFormType, for: normalizationFormSymbol)

        let normalizationFormsSymbol = ensureSyntheticObjectSymbol(
            named: "NormalizationForms",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let normalizationFormsType = types.make(.classType(ClassType(
            classSymbol: normalizationFormsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(normalizationFormsType, for: normalizationFormsSymbol)

        for formName in ["NFC", "NFD", "NFKC", "NFKD"] {
            registerSyntheticObjectProperty(
                ownerSymbol: normalizationFormsSymbol,
                ownerType: normalizationFormsType,
                name: formName,
                propertyType: normalizationFormType,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticStringExtensionFunction(
            named: "normalize",
            externalLinkName: "kk_string_normalize",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "isNormalized",
            externalLinkName: "kk_string_isNormalized",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: boolType,
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

        // --- STDLIB-TEXT-EDGE-001: split with limit / ignoreCase ---
        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("limit", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("ignoreCase", boolType, false, false),
                ("limit", intType, false, false),
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

        // STDLIB-420: String.toLong / toLongOrNull / toFloat / toFloatOrNull
        registerSyntheticStringExtensionFunction(
            named: "toLong",
            externalLinkName: "kk_string_toLong",
            receiverType: stringType,
            parameters: [],
            returnType: longType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toLongOrNull",
            externalLinkName: "kk_string_toLongOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableLongType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toFloat",
            externalLinkName: "kk_string_toFloat",
            receiverType: stringType,
            parameters: [],
            returnType: floatType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toFloatOrNull",
            externalLinkName: "kk_string_toFloatOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableFloatType,
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
            named: "subSequence",
            externalLinkName: "kk_string_subSequence",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: stringType,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use substring(startIndex, endIndex) instead.\"",
                        "replaceWith = ReplaceWith(\"substring(startIndex, endIndex)\")",
                    ]
                ),
            ],
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
            named: "indexOf",
            externalLinkName: "kk_string_indexOf_from",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase ---

        registerSyntheticStringExtensionFunction(
            named: "indexOf",
            externalLinkName: "kk_string_indexOf_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "lastIndexOf",
            externalLinkName: "kk_string_lastIndexOf_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
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
            returnType: charArrayType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-317: String.asIterable() — returns lazy Iterable<Char>
        let iterableCharType = makeIterableType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )
        registerSyntheticStringExtensionFunction(
            named: "asIterable",
            externalLinkName: "kk_string_asIterable",
            receiverType: stringType,
            parameters: [],
            returnType: iterableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "padStart",
            externalLinkName: "kk_string_padStart_default",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
            ],
            returnType: stringType,
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
            externalLinkName: "kk_string_padEnd_default",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
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
            receiverType: charSequenceType,
            parameters: [
                ("prefix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSuffix",
            externalLinkName: "kk_string_removeSuffix",
            receiverType: charSequenceType,
            parameters: [
                ("suffix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding",
            receiverType: charSequenceType,
            parameters: [
                ("delimiter", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding_pair",
            receiverType: charSequenceType,
            parameters: [
                ("prefix", charSequenceType, false, false),
                ("suffix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

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

        // --- STDLIB-TEXT-EDGE-004: CharSequence.ifBlank(defaultValue) ---

        registerSyntheticStringExtensionFunction(
            named: "ifBlank",
            externalLinkName: "kk_string_ifBlank",
            receiverType: charSequenceType,
            parameters: [
                ("defaultValue", stringProducerType, false, false),
            ],
            returnType: stringType,
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

        registerSyntheticStringExtensionFunction(
            named: "singleOrNull",
            externalLinkName: "kk_string_singleOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-140: String.getOrNull(Int): Char? ---

        registerSyntheticStringExtensionFunction(
            named: "getOrNull",
            externalLinkName: "kk_string_getOrNull",
            receiverType: stringType,
            parameters: [
                ("index", intType, false, false),
            ],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-191: prependIndent / replaceIndent ---

        registerSyntheticStringExtensionFunction(
            named: "prependIndent",
            externalLinkName: "kk_string_prependIndent_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "prependIndent",
            externalLinkName: "kk_string_prependIndent",
            receiverType: stringType,
            parameters: [
                ("indent", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "replaceIndent",
            externalLinkName: "kk_string_replaceIndent_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "replaceIndent",
            externalLinkName: "kk_string_replaceIndent",
            receiverType: stringType,
            parameters: [
                ("newIndent", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-192: equals(other, ignoreCase) ---

        let nullableStringType = types.make(.primitive(.string, .nullable))

        registerSyntheticStringExtensionFunction(
            named: "equals",
            externalLinkName: "kk_string_equals",
            receiverType: stringType,
            parameters: [
                ("other", nullableStringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "equals",
            externalLinkName: "kk_string_equalsIgnoreCase",
            receiverType: stringType,
            parameters: [
                ("other", nullableStringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-188: replaceFirst / replaceRange ---

        registerSyntheticStringExtensionFunction(
            named: "replaceFirst",
            externalLinkName: "kk_string_replaceFirst",
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
            named: "replaceRange",
            externalLinkName: "kk_string_replaceRange",
            receiverType: stringType,
            parameters: [
                ("range", intType, false, false),
                ("replacement", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-008: removeRange ---

        registerSyntheticStringExtensionFunction(
            named: "removeRange",
            externalLinkName: "kk_string_removeRange",
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
            named: "removeRange",
            externalLinkName: "kk_string_removeRange_range",
            receiverType: stringType,
            parameters: [
                ("range", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-189: String HOF (filter, map, count, any, all, none) ---
        let charToBoolType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: boolType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToCharType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: charType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToAnyType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToNullableAnyType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let intCharToAnyType = types.make(.functionType(FunctionType(
            params: [intType, charType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let intCharToBoolType = types.make(.functionType(FunctionType(
            params: [intType, charType],
            returnType: boolType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listAnyType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: types.anyType
        )
        let sequenceStringType = makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: stringType
        )
        registerSyntheticStringExtensionFunction(
            named: "filter",
            externalLinkName: "kk_string_filter",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // String.map returns List<R> in Kotlin; use (Char) -> Any transform
        // and Any return type to allow arbitrary mapping.
        registerSyntheticStringExtensionFunction(
            named: "map",
            externalLinkName: "kk_string_map",
            receiverType: stringType,
            parameters: [("transform", charToAnyType, false, false)],
            returnType: types.anyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "count",
            externalLinkName: "kk_string_count",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "any",
            externalLinkName: "kk_string_any",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "all",
            externalLinkName: "kk_string_all",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "none",
            externalLinkName: "kk_string_none",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "mapIndexed",
            externalLinkName: "kk_string_mapIndexed",
            receiverType: stringType,
            parameters: [("transform", intCharToAnyType, false, false)],
            returnType: listAnyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "mapNotNull",
            externalLinkName: "kk_string_mapNotNull",
            receiverType: stringType,
            parameters: [("transform", charToNullableAnyType, false, false)],
            returnType: listAnyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "filterIndexed",
            externalLinkName: "kk_string_filterIndexed",
            receiverType: stringType,
            parameters: [("predicate", intCharToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "filterNot",
            externalLinkName: "kk_string_filterNot",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "takeWhile",
            externalLinkName: "kk_string_takeWhile",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "dropWhile",
            externalLinkName: "kk_string_dropWhile",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "find",
            externalLinkName: "kk_string_find",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "findLast",
            externalLinkName: "kk_string_findLast",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "splitToSequence",
            externalLinkName: "kk_string_splitToSequence",
            receiverType: stringType,
            parameters: [("delimiter", stringType, false, false)],
            returnType: sequenceStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.indexOfFirst / indexOfLast ---
        registerSyntheticStringExtensionFunction(
            named: "indexOfFirst",
            externalLinkName: "kk_string_indexOfFirst",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "indexOfLast",
            externalLinkName: "kk_string_indexOfLast",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-315: String.replaceFirstChar ---
        registerSyntheticStringExtensionFunction(
            named: "replaceFirstChar",
            externalLinkName: "kk_string_replaceFirstChar",
            receiverType: stringType,
            parameters: [("transform", charToCharType, false, false)],
            returnType: stringType,
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

        registerSyntheticStringExtensionFunction(
            named: "toBooleanStrictOrNull",
            externalLinkName: "kk_string_toBooleanStrictOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableBoolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toShort",
            externalLinkName: "kk_string_toShort",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toShortOrNull",
            externalLinkName: "kk_string_toShortOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toByte",
            externalLinkName: "kk_string_toByte",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toByteOrNull",
            externalLinkName: "kk_string_toByteOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
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

        // --- STDLIB-666: String.lineSequence ---

        registerSyntheticStringExtensionFunction(
            named: "lineSequence",
            externalLinkName: "kk_string_lineSequence",
            receiverType: stringType,
            parameters: [],
            returnType: sequenceStringType,
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

        // STDLIB-581: String.toByteArray(charset: Charset)
        let charsetSymbol = ensureClassSymbol(
            named: "Charset", in: kotlinTextPkg,
            symbols: symbols, interner: interner
        )
        let charsetType = types.make(.classType(ClassType(
            classSymbol: charsetSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(charsetType, for: charsetSymbol)

        // Register Charsets singleton object with charset constants
        let charsetsSymbol = ensureSyntheticObjectSymbol(
            named: "Charsets",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let charsetsType = types.make(.classType(ClassType(
            classSymbol: charsetsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(charsetsType, for: charsetsSymbol)

        for charsetName in [
            "UTF_8", "ISO_8859_1", "US_ASCII",
            "UTF_16", "UTF_16BE", "UTF_16LE",
            "UTF_32", "UTF_32BE", "UTF_32LE",
        ] {
            registerSyntheticObjectProperty(
                ownerSymbol: charsetsSymbol,
                ownerType: charsetsType,
                name: charsetName,
                propertyType: charsetType,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticStringExtensionFunction(
            named: "toByteArray",
            externalLinkName: "kk_string_toByteArray_charset",
            receiverType: stringType,
            parameters: [
                ("charset", charsetType, false, false),
            ],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-573: String.encodeToByteArray()
        registerSyntheticStringExtensionFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_string_encodeToByteArray",
            receiverType: stringType,
            parameters: [],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
        for functionName in ["encodeToByteArray", "toByteArray"] {
            registerSyntheticStringExtensionFunction(
                named: functionName,
                externalLinkName: "kk_string_encodeToByteArray_range",
                receiverType: stringType,
                parameters: [
                    ("startIndex", intType, false, false),
                    ("endIndex", intType, false, false),
                ],
                returnType: listIntType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-573: String.encodeToByteArray(charset) — charset-aware overload
        registerSyntheticStringExtensionFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_string_encodeToByteArray_charset",
            receiverType: stringType,
            parameters: [
                ("charset", charsetType, false, false),
            ],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        let javaMathPkg = ensurePackage(
            path: ["java", "math"],
            symbols: symbols,
            interner: interner
        )
        let javaMathPkgSymbol = symbols.lookup(fqName: javaMathPkg)
        let bigDecimalSymbol = ensureClassSymbol(
            named: "BigDecimal",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        let bigIntegerSymbol = ensureClassSymbol(
            named: "BigInteger",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaMathPkgSymbol {
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigDecimalSymbol)
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigIntegerSymbol)
        }
        let bigDecimalType = types.make(.classType(ClassType(
            classSymbol: bigDecimalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigDecimalType, for: bigDecimalSymbol)
        let bigIntegerType = types.make(.classType(ClassType(
            classSymbol: bigIntegerSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigIntegerType, for: bigIntegerSymbol)

        registerSyntheticStringExtensionFunction(
            named: "toBigDecimal",
            externalLinkName: "kk_string_toBigDecimal",
            receiverType: stringType,
            parameters: [],
            returnType: bigDecimalType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toBigInteger",
            externalLinkName: "kk_string_toBigInteger",
            receiverType: stringType,
            parameters: [],
            returnType: bigIntegerType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticBigNumberMemberFunction(
            ownerSymbol: bigDecimalSymbol,
            ownerType: bigDecimalType,
            name: "toString",
            returnType: stringType,
            externalLinkName: "kk_bignum_toString",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticBigNumberMemberFunction(
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            name: "toString",
            returnType: stringType,
            externalLinkName: "kk_bignum_toString",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-574: ByteArray.decodeToString()
        let byteArrayType = makeNominalType(
            symbols: symbols,
            types: types,
            fqName: [interner.intern("kotlin"), interner.intern("ByteArray")]
        )

        // Register on both List<Int> (internal representation) and ByteArray (user-facing type)
        for receiverType in [listIntType, byteArrayType] {
            registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString",
                receiverType: receiverType,
                parameters: [],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        for charsetPropName in ["UTF_8", "US_ASCII", "ISO_8859_1"] {
            let propName = interner.intern(charsetPropName)
            let propFQName = [interner.intern("kotlin"), interner.intern("text"), interner.intern("Charsets"), propName]
            guard symbols.lookup(fqName: propFQName) == nil else { continue }
            let propSymbol = symbols.define(
                kind: .property,
                name: propName,
                fqName: propFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(charsetsSymbol, for: propSymbol)
            symbols.setPropertyType(charsetType, for: propSymbol)
        }

        // STDLIB-574: ByteArray.decodeToString(charset: Charset) overload
        for receiverType in [listIntType, byteArrayType] {
            registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString_charset",
                receiverType: receiverType,
                parameters: [
                    ("charset", charsetType, false, false),
                ],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-STR-125: String(ByteArray, Charset) constructor
        // Allows decoding a byte array with an explicit charset: String(bytes, Charsets.UTF_8)
        // Register on both List<Int> (internal representation) and ByteArray (user-facing type)
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let stringClassSymbol = ensureClassSymbol(
            named: "String",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: stringClassSymbol)
        }
        symbols.setDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        types.setNominalDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        for bytesType in [listIntType, byteArrayType] {
            registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType), ("charset", charsetType)],
                externalLinkName: "kk_bytearray_decodeToString_charset",
                symbols: symbols,
                interner: interner
            )
            // String(ByteArray) — default UTF-8 decoding
            registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType)],
                externalLinkName: "kk_bytearray_decodeToString",
                symbols: symbols,
                interner: interner
            )
        }

        // --- STDLIB-I18N-COMMON-001: String.format companion method ---
        // Kotlin: String.format(format: String, vararg args: Any?) -> String
        // This is a companion (static) method on the String class, not an extension.
        let stringCompanionFQName = ensureStringCompanionSymbol(
            ownerSymbol: stringClassSymbol,
            symbols: symbols,
            interner: interner
        )
        registerStringCompanionMethod(
            named: "format",
            externalLinkName: "kk_string_format",
            returnType: stringType,
            parameters: [
                (name: "format", type: stringType),
                (name: "args", type: types.nullableAnyType),
            ],
            isVararg: [false, true],
            companionFQName: stringCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-316: String.chunked / String.windowed ---

        registerSyntheticStringExtensionFunction(
            named: "chunked",
            externalLinkName: "kk_string_chunked",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed_default",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
                ("step", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed_partial",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
                ("step", intType, false, false),
                ("partialWindows", boolType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-318: String.commonPrefixWith / commonSuffixWith ---

        registerSyntheticStringExtensionFunction(
            named: "commonPrefixWith",
            externalLinkName: "kk_string_commonPrefixWith",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "commonSuffixWith",
            externalLinkName: "kk_string_commonSuffixWith",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads) ---

        registerSyntheticStringExtensionFunction(
            named: "commonPrefixWith",
            externalLinkName: "kk_string_commonPrefixWith_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "commonSuffixWith",
            externalLinkName: "kk_string_commonSuffixWith_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-316: String/CharSequence.zipWithNext ---

        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        let pairCharCharType: TypeID
        if let pairSymbol = symbols.lookup(fqName: pairFQName) {
            pairCharCharType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(charType), .out(charType)],
                nullability: .nonNull
            )))
        } else {
            pairCharCharType = types.anyType
        }
        let listPairCharCharType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: pairCharCharType
        )

        registerSyntheticStringExtensionFunction(
            named: "zipWithNext",
            externalLinkName: "kk_string_zipWithNext",
            receiverType: stringType,
            parameters: [],
            returnType: listPairCharCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "zipWithNext",
            externalLinkName: "kk_string_zipWithNext",
            receiverType: charSequenceType,
            parameters: [],
            returnType: listPairCharCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // String/CharSequence.zipWithNext(transform: (Char, Char) -> R)
        let zipWithNextTransformFQName = kotlinTextPkg + [interner.intern("zipWithNext")]
        func registerZipWithNextTransform(receiverType: TypeID) {
            let existingZipWithNextTransform = symbols.lookupAll(fqName: zipWithNextTransformFQName).first { symID in
                guard let sig = symbols.functionSignature(for: symID) else {
                    return false
                }
                return sig.receiverType == receiverType && sig.parameterTypes.count == 1
            }
            if let existingZipWithNextTransform {
                symbols.setExternalLinkName("kk_string_zipWithNextTransform", for: existingZipWithNextTransform)
                return
            }

            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: zipWithNextTransformFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformFnType = types.make(.functionType(FunctionType(
                params: [charType, charType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformResultType = makeListType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: rType
            )
            let transformMemberSymbol = symbols.define(
                kind: .function,
                name: interner.intern("zipWithNext"),
                fqName: zipWithNextTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(packageSymbol, for: transformMemberSymbol)
            }
            symbols.setExternalLinkName("kk_string_zipWithNextTransform", for: transformMemberSymbol)
            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: zipWithNextTransformFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(transformMemberSymbol, for: transformParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformFnType],
                    returnType: transformResultType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [rSymbol],
                    classTypeParameterCount: 0
                ),
                for: transformMemberSymbol
            )
        }
        registerZipWithNextTransform(receiverType: stringType)
        registerZipWithNextTransform(receiverType: charSequenceType)

        // --- String.partition ---
        let pairStringStringType: TypeID
        if let pairSymbol = symbols.lookup(fqName: pairFQName) {
            pairStringStringType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(stringType), .out(stringType)],
                nullability: .nonNull
            )))
        } else {
            pairStringStringType = types.anyType
        }
        registerSyntheticStringExtensionFunction(
            named: "partition",
            externalLinkName: "kk_string_partition",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: pairStringStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-317: String.asSequence / asIterable ---

        let sequenceCharType = makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )

        registerSyntheticStringExtensionFunction(
            named: "asSequence",
            externalLinkName: "kk_string_asSequence",
            receiverType: stringType,
            parameters: [],
            returnType: sequenceCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "asIterable",
            externalLinkName: "kk_string_asIterable",
            receiverType: stringType,
            parameters: [],
            returnType: iterableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-534: String?.orEmpty() ---

        registerSyntheticStringExtensionFunction(
            named: "orEmpty",
            externalLinkName: "kk_string_orEmpty",
            receiverType: nullableStringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-009: CharSequence?.contentEquals ---

        registerSyntheticStringExtensionFunction(
            named: "contentEquals",
            externalLinkName: "kk_string_contentEquals",
            receiverType: nullableStringType,
            parameters: [
                ("other", nullableStringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "contentEquals",
            externalLinkName: "kk_string_contentEquals_ignoreCase",
            receiverType: nullableStringType,
            parameters: [
                ("other", nullableStringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: boolType,
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
        let listSymbol = ensureListSymbol(symbols: symbols, types: types, interner: interner)
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceSymbol = ensureSequenceSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func ensureSequenceSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            sequenceName,
        ]
        if let existing = symbols.lookup(fqName: sequenceFQName) {
            return existing
        }
        // Ensure the kotlin.sequences package exists
        let sequencesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
        ]
        if symbols.lookup(fqName: sequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: sequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: sequenceName,
            fqName: sequenceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Sequence<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    private func makeIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableSymbol = ensureIterableSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func ensureIterableSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let iterableName = interner.intern("Iterable")
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            iterableName,
        ]
        if let existing = symbols.lookup(fqName: iterableFQName) {
            return existing
        }
        // Ensure the kotlin.collections package exists
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: iterableName,
            fqName: iterableFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Iterable<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = iterableFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    private func makeListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        makeListType(symbols: symbols, types: types, interner: interner, elementType: types.stringType)
    }

    private func makeNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        fqName: [InternedString]
    ) -> TypeID {
        if let symbol = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
        }

        guard let name = fqName.last else {
            return types.anyType
        }

        var packagePath: [InternedString] = []
        for packageName in fqName.dropLast() {
            packagePath.append(packageName)
            if symbols.lookup(fqName: packagePath) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: packageName,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }

        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func ensureListSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let listName = interner.intern("List")
        let listFQName = collectionsPkg + [listName]
        if let existing = symbols.lookup(fqName: listFQName) {
            return existing
        }
        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParamName = interner.intern("E")
        let typeParamFQName = listFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        return interfaceSymbol
    }

    private func registerSyntheticStringExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
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
            if !annotations.isEmpty {
                symbols.setAnnotations(annotations, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: functionSymbol)
        }

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

    private func ensureSyntheticObjectSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .object,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
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
    }

    private func registerSyntheticBigNumberMemberFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).isEmpty else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    private func registerStringConstructorFromBytes(
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

    // MARK: - String Companion Helpers

    private func ensureStringCompanionSymbol(
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

    private func registerStringCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        isVararg: [Bool],
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
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

        let hasDefaults = Array(repeating: false, count: parameters.count)
        let varargFlags = isVararg.count == parameters.count
            ? isVararg
            : Array(repeating: false, count: parameters.count)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: hasDefaults,
                valueParameterIsVararg: varargFlags
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticLocaleConstructor(
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
}
