import Foundation

// Char stdlib extension stubs (STDLIB-080) for kotlin.text.

enum SyntheticCharMemberReturnKind {
    case boolean
    case string
    case char
    case int
    case double
    case nullableInt
    case nullableDouble
    case charCategory
    case charDirectionality

    func typeID(
        in types: TypeSystem,
        charCategoryType: TypeID? = nil,
        charDirectionalityType: TypeID? = nil
    ) -> TypeID {
        switch self {
        case .boolean:
            types.booleanType
        case .string:
            types.stringType
        case .char:
            types.charType
        case .int:
            types.intType
        case .double:
            types.doubleType
        case .nullableInt:
            types.make(.primitive(.int, .nullable))
        case .nullableDouble:
            types.make(.primitive(.double, .nullable))
        case .charCategory:
            charCategoryType ?? types.intType
        case .charDirectionality:
            charDirectionalityType ?? types.intType
        }
    }

    func typeID(
        in types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> TypeID {
        typeID(
            in: types,
            charCategoryType: syntheticCharCategoryTypeID(
                symbols: symbols,
                types: types,
                interner: interner
            ),
            charDirectionalityType: syntheticCharDirectionalityTypeID(
                symbols: symbols,
                types: types,
                interner: interner
            )
        )
    }

    var stubTypeRef: SyntheticStubTypeRef {
        switch self {
        case .boolean:
            .boolean
        case .string:
            .string
        case .char:
            .char
        case .int:
            .int
        case .double:
            .double
        case .nullableInt:
            .nullable(.int)
        case .nullableDouble:
            .nullable(.double)
        case .charCategory:
            .namedClass(["kotlin", "text", "CharCategory"])
        case .charDirectionality:
            .namedClass(["kotlin", "text", "CharDirectionality"])
        }
    }
}

struct SyntheticCharMemberSpec {
    let name: String
    let externalLinkName: String
    let returnKind: SyntheticCharMemberReturnKind

    var functionSpec: SyntheticFunctionStubSpec {
        SyntheticFunctionStubSpec(
            name: name,
            externalLinkName: externalLinkName,
            receiverType: .char,
            returnType: returnKind.stubTypeRef
        )
    }
}

private let syntheticCharMemberSpecs: [SyntheticCharMemberSpec] = [
    // KSP-661: isDigit/isLetter/isLetterOrDigit/isWhitespace/isUpperCase/
    // isLowerCase/isDefined は bundled Kotlin (kotlin.text.CharPredicates) へ移行済み。
    // KSP-662: uppercase(Char)/lowercase(Char)/titlecase(Char)/digitToInt(OrNull)/
    // digitToChar now live in bundled Kotlin (kotlin.text.CharConversions).
    // New numeric conversion functions
    SyntheticCharMemberSpec(
        name: "toInt",
        externalLinkName: "kk_char_toInt",
        returnKind: .int
    ),
    SyntheticCharMemberSpec(
        name: "toDouble",
        externalLinkName: "kk_char_toDouble",
        returnKind: .double
    ),
    SyntheticCharMemberSpec(
        name: "toIntOrNull",
        externalLinkName: "kk_char_toIntOrNull",
        returnKind: .nullableInt
    ),
    SyntheticCharMemberSpec(
        name: "toDoubleOrNull",
        externalLinkName: "kk_char_toDoubleOrNull",
        returnKind: .nullableDouble
    ),
    // KSP-663: isSurrogate/isHighSurrogate/isLowSurrogate are now bundled Kotlin.
    // Control character predicates
    SyntheticCharMemberSpec(
        name: "isISOControl",
        externalLinkName: "kk_char_isISOControl",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isTitleCase",
        externalLinkName: "kk_char_isTitleCase",
        returnKind: .boolean
    ),
    // STDLIB-TEXT-PROP-009: isJavaIdentifierPart
    SyntheticCharMemberSpec(
        name: "isJavaIdentifierPart",
        externalLinkName: "kk_char_isJavaIdentifierPart",
        returnKind: .boolean
    ),
    // STDLIB-TEXT-PROP-008: isIdentifierIgnorable
    SyntheticCharMemberSpec(
        name: "isIdentifierIgnorable",
        externalLinkName: "kk_char_isIdentifierIgnorable",
        returnKind: .boolean
    ),
    // STDLIB-TEXT-PROP-017: Char.isUnicodeIdentifierPart
    SyntheticCharMemberSpec(
        name: "isUnicodeIdentifierPart",
        externalLinkName: "kk_char_isUnicodeIdentifierPart",
        returnKind: .boolean
    ),
    // STDLIB-TEXT-PROP-010: Char.isJavaIdentifierStart
    SyntheticCharMemberSpec(
        name: "isJavaIdentifierStart",
        externalLinkName: "kk_char_isJavaIdentifierStart",
        returnKind: .boolean
    ),
    // Code point and Unicode properties
    SyntheticCharMemberSpec(
        name: "code",
        externalLinkName: "kk_char_code",
        returnKind: .int
    ),
    SyntheticCharMemberSpec(
        name: "category",
        externalLinkName: "kk_char_category",
        returnKind: .charCategory
    ),
    SyntheticCharMemberSpec(
        name: "directionality",
        externalLinkName: "kk_char_directionality",
        returnKind: .charDirectionality
    ),
]

private let syntheticCharCategoryEntries = [
    "UNASSIGNED",
    "UPPERCASE_LETTER",
    "LOWERCASE_LETTER",
    "TITLECASE_LETTER",
    "MODIFIER_LETTER",
    "OTHER_LETTER",
    "NON_SPACING_MARK",
    "ENCLOSING_MARK",
    "COMBINING_SPACING_MARK",
    "DECIMAL_DIGIT_NUMBER",
    "LETTER_NUMBER",
    "OTHER_NUMBER",
    "SPACE_SEPARATOR",
    "LINE_SEPARATOR",
    "PARAGRAPH_SEPARATOR",
    "CONTROL",
    "FORMAT",
    "PRIVATE_USE",
    "SURROGATE",
    "DASH_PUNCTUATION",
    "START_PUNCTUATION",
    "END_PUNCTUATION",
    "CONNECTOR_PUNCTUATION",
    "OTHER_PUNCTUATION",
    "MATH_SYMBOL",
    "CURRENCY_SYMBOL",
    "MODIFIER_SYMBOL",
    "OTHER_SYMBOL",
    "INITIAL_QUOTE_PUNCTUATION",
    "FINAL_QUOTE_PUNCTUATION",
]

func syntheticCharMemberSpec(named name: String) -> SyntheticCharMemberSpec? {
    syntheticCharMemberSpecs.first { $0.name == name }
}

func syntheticCharCategoryTypeID(
    symbols: SymbolTable,
    types: TypeSystem,
    interner: StringInterner
) -> TypeID? {
    guard let symbol = symbols.lookup(fqName: [
        interner.intern("kotlin"),
        interner.intern("text"),
        interner.intern("CharCategory"),
    ]) else {
        return nil
    }
    return types.make(.classType(ClassType(
        classSymbol: symbol,
        args: [],
        nullability: .nonNull
    )))
}

func syntheticCharDirectionalityTypeID(
    symbols: SymbolTable,
    types: TypeSystem,
    interner: StringInterner
) -> TypeID? {
    guard let symbol = symbols.lookup(fqName: [
        interner.intern("kotlin"),
        interner.intern("text"),
        interner.intern("CharDirectionality"),
    ]) else {
        return nil
    }
    return types.make(.classType(ClassType(
        classSymbol: symbol,
        args: [],
        nullability: .nonNull
    )))
}

extension DataFlowSemaPhase {
    func registerSyntheticCharStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackageForCharStubs(symbols: symbols, interner: interner)
        let charCategoryFQName = kotlinTextPkg + [interner.intern("CharCategory")]
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let hasBundledCharCategory = bundledIndex.containsNominal(fqName: charCategoryFQName)
        let charCategorySymbol = ensureSyntheticCharCategoryEnumClass(
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner,
            includeEntries: !hasBundledCharCategory
        )
        if !hasBundledCharCategory {
            // KSP-1416: Keep CharCategory's public Companion nominal available
            // while its enum entries and members remain synthetic until KSP-1417.
            _ = ensureSyntheticCharCompanionSymbol(
                ownerSymbol: charCategorySymbol,
                symbols: symbols,
                interner: interner
            )
        }
        let charCategoryType = types.make(.classType(ClassType(
            classSymbol: charCategorySymbol,
            args: [],
            nullability: .nonNull
        )))
        if !hasBundledCharCategory {
            setSyntheticCharCategoryEntryTypes(
                enumSymbol: charCategorySymbol,
                enumType: charCategoryType,
                symbols: symbols,
                interner: interner
            )
        }
        let charDirectionalityType = ensureSyntheticCharDirectionalityEnum(
            in: kotlinTextPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        _ = (charCategoryType, charDirectionalityType)
        let kotlinTextContext = SyntheticStubRegistrationContext(
            ownerFQName: kotlinTextPkg,
            parentSymbol: symbols.lookup(fqName: kotlinTextPkg)
        )
        registerSyntheticFunctionStubs(
            syntheticCharMemberSpecs.map(\.functionSpec),
            context: kotlinTextContext,
            symbols: symbols,
            types: types,
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
            classSymbol: localeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(localeType, for: localeSymbol)

        registerSyntheticFunctionStubs(
            [
                // PARITY-CODEGEN-005: Char.compareTo(Char)
                SyntheticFunctionStubSpec(
                    name: "compareTo",
                    externalLinkName: "kk_char_compareTo",
                    receiverType: .char,
                    parameters: [
                        SyntheticStubParameterSpec(name: "other", type: .char),
                    ],
                    returnType: .int
                ),
            ],
            context: kotlinTextContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeCharCompanionHelpers(symbols: symbols, types: types, interner: interner)
    }

    private func ensureKotlinTextPackageForCharStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinPackageSymbol: SymbolID = if let existing = symbols.lookup(fqName: kotlinPkg) {
            existing
        } else {
            symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let kotlinTextPkg = kotlinPkg + [interner.intern("text")]
        if let existing = symbols.lookup(fqName: kotlinTextPkg) {
            if symbols.parentSymbol(for: existing) == nil {
                symbols.setParentSymbol(kotlinPackageSymbol, for: existing)
            }
        } else {
            let kotlinTextSymbol = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kotlinPackageSymbol, for: kotlinTextSymbol)
        }
        return kotlinTextPkg
    }

    private func ensureSyntheticCharCategoryEnumClass(
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        includeEntries: Bool
    ) -> SymbolID {
        let enumName = interner.intern("CharCategory")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        guard includeEntries else {
            return enumSymbol
        }

        for entry in syntheticCharCategoryEntries {
            let entryName = interner.intern(entry)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setSyntheticCharCategoryEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let enumFQName = enumInfo.fqName
        for (ordinal, entry) in syntheticCharCategoryEntries.enumerated() {
            let entryName = interner.intern(entry)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            }
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
            symbols.insertFlags([.constValue], for: entrySymbol)
            symbols.setConstValueExprKind(.intLiteral(Int64(ordinal)), for: entrySymbol)
        }
    }

    private func ensureSyntheticCharDirectionalityEnum(
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let enumName = interner.intern("CharDirectionality")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let entries = [
            "UNDEFINED",
            "LEFT_TO_RIGHT",
            "RIGHT_TO_LEFT",
            "RIGHT_TO_LEFT_ARABIC",
            "EUROPEAN_NUMBER",
            "EUROPEAN_NUMBER_SEPARATOR",
            "EUROPEAN_NUMBER_TERMINATOR",
            "ARABIC_NUMBER",
            "COMMON_NUMBER_SEPARATOR",
            "NONSPACING_MARK",
            "BOUNDARY_NEUTRAL",
            "PARAGRAPH_SEPARATOR",
            "SEGMENT_SEPARATOR",
            "WHITESPACE",
            "OTHER_NEUTRALS",
            "LEFT_TO_RIGHT_EMBEDDING",
            "LEFT_TO_RIGHT_OVERRIDE",
            "RIGHT_TO_LEFT_EMBEDDING",
            "RIGHT_TO_LEFT_OVERRIDE",
            "POP_DIRECTIONAL_FORMAT",
        ]
        for (ordinal, entry) in entries.enumerated() {
            let entryName = interner.intern(entry)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            symbols.setPropertyType(enumType, for: entrySymbol)
            symbols.insertFlags([.constValue], for: entrySymbol)
            symbols.setConstValueExprKind(.intLiteral(Int64(ordinal)), for: entrySymbol)
        }
        return enumType
    }

    private func registerNativeCharCompanionHelpers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // KSP-663: Char.Companion surrogate helpers are now bundled Kotlin.
        // Keep the Char class / companion object symbols so source extensions
        // on Char.Companion resolve correctly.
        let kotlinPkg = [interner.intern("kotlin")]
        let charSymbol = ensureClassSymbol(
            named: "Char",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.charClassSymbol = charSymbol
        if let kotlinSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinSymbol, for: charSymbol)
        }

        _ = ensureSyntheticCharCompanionSymbol(
            ownerSymbol: charSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticCharCompanionSymbol(
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

}
