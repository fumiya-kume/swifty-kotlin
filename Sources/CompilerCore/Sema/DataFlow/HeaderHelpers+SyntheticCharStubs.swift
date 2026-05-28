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
}

struct SyntheticCharMemberSpec {
    let name: String
    let externalLinkName: String
    let returnKind: SyntheticCharMemberReturnKind
}

private struct SyntheticCharCompanionFunctionSpec {
    let name: String
    let externalLinkName: String
    let parameters: [(name: String, type: TypeID)]
    let returnType: TypeID
}

private let syntheticCharMemberSpecs: [SyntheticCharMemberSpec] = [
    SyntheticCharMemberSpec(
        name: "isDigit",
        externalLinkName: "kk_char_isDigit",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isLetter",
        externalLinkName: "kk_char_isLetter",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isLetterOrDigit",
        externalLinkName: "kk_char_isLetterOrDigit",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isUpperCase",
        externalLinkName: "kk_char_isUpperCase",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isLowerCase",
        externalLinkName: "kk_char_isLowerCase",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isWhitespace",
        externalLinkName: "kk_char_isWhitespace",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isDefined",
        externalLinkName: "kk_char_isDefined",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isIdentifierIgnorable",
        externalLinkName: "kk_char_isIdentifierIgnorable",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isJavaIdentifierPart",
        externalLinkName: "kk_char_isJavaIdentifierPart",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isJavaIdentifierStart",
        externalLinkName: "kk_char_isJavaIdentifierStart",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isUnicodeIdentifierPart",
        externalLinkName: "kk_char_isUnicodeIdentifierPart",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "uppercase",
        externalLinkName: "kk_char_uppercase",
        returnKind: .string
    ),
    SyntheticCharMemberSpec(
        name: "uppercaseChar",
        externalLinkName: "kk_char_uppercaseChar",
        returnKind: .char
    ),
    SyntheticCharMemberSpec(
        name: "lowercase",
        externalLinkName: "kk_char_lowercase",
        returnKind: .string
    ),
    SyntheticCharMemberSpec(
        name: "lowercaseChar",
        externalLinkName: "kk_char_lowercaseChar",
        returnKind: .char
    ),
    SyntheticCharMemberSpec(
        name: "titlecase",
        externalLinkName: "kk_char_titlecase",
        returnKind: .string
    ),
    SyntheticCharMemberSpec(
        name: "titlecaseChar",
        externalLinkName: "kk_char_titlecaseChar",
        returnKind: .char
    ),
    SyntheticCharMemberSpec(
        name: "digitToInt",
        externalLinkName: "kk_char_digitToInt",
        returnKind: .int
    ),
    SyntheticCharMemberSpec(
        name: "digitToIntOrNull",
        externalLinkName: "kk_char_digitToIntOrNull",
        returnKind: .nullableInt
    ),
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
    // Surrogate and control character predicates
    SyntheticCharMemberSpec(
        name: "isSurrogate",
        externalLinkName: "kk_char_isSurrogate",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isHighSurrogate",
        externalLinkName: "kk_char_isHighSurrogate",
        returnKind: .boolean
    ),
    SyntheticCharMemberSpec(
        name: "isLowSurrogate",
        externalLinkName: "kk_char_isLowSurrogate",
        returnKind: .boolean
    ),
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
        let charCategorySymbol = ensureSyntheticCharCategoryEnumClass(
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let charCategoryType = types.make(.classType(ClassType(
            classSymbol: charCategorySymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticCharCategoryEntryTypes(
            enumSymbol: charCategorySymbol,
            enumType: charCategoryType,
            symbols: symbols
        )
        let charDirectionalityType = ensureSyntheticCharDirectionalityEnum(
            in: kotlinTextPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        for member in syntheticCharMemberSpecs {
            registerSyntheticCharExtensionFunction(
                named: member.name,
                externalLinkName: member.externalLinkName,
                receiverType: types.charType,
                returnType: member.returnKind.typeID(
                    in: types,
                    charCategoryType: charCategoryType,
                    charDirectionalityType: charDirectionalityType
                ),
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }
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

        registerSyntheticCharExtensionFunction(
            named: "lowercase",
            externalLinkName: "kk_char_lowercase_locale",
            receiverType: types.charType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: types.stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCharExtensionFunction(
            named: "uppercase",
            externalLinkName: "kk_char_uppercase_locale",
            receiverType: types.charType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: types.stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int)
        registerDigitToIntRadixStub(symbols: symbols, types: types, interner: interner)
        // STDLIB-TEXT-FN-038: Char.minus(Char): Int and Char.minus(Int): Char
        registerCharMinusStubs(symbols: symbols, types: types, interner: interner)
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
        interner: StringInterner
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
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func registerSyntheticCharExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)] = [],
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
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
            valueParameterSymbols.append(parameterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: parameters.map(\.isVararg)
            ),
            for: functionSymbol
        )
    }

    // MARK: - STDLIB-003-ABI-001/002/003 registration helpers

    /// Register `fun Char.digitToInt(radix: Int): Int` synthetic stub.
    func registerDigitToIntRadixStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackageForCharStubs(symbols: symbols, interner: interner)
        let functionName = interner.intern("digitToInt")
        let functionFQName = kotlinTextPkg + [functionName]
        let intType = types.intType

        let alreadyExists = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == types.charType
                && signature.parameterTypes == [intType]
                && signature.returnType == intType
        }
        guard !alreadyExists else { return }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSym = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(pkgSym, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_char_digitToInt_radix", for: functionSymbol)

        let radixParamName = interner.intern("radix")
        let radixParamSym = symbols.define(
            kind: .valueParameter,
            name: radixParamName,
            fqName: functionFQName + [radixParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: radixParamSym)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.charType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [radixParamSym],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
        )
    }

    // MARK: - STDLIB-TEXT-FN-038: Char.minus operator stubs

    /// Register `operator fun Char.minus(other: Char): Int` and
    /// `operator fun Char.minus(n: Int): Char` synthetic stubs.
    func registerCharMinusStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackageForCharStubs(symbols: symbols, interner: interner)
        let functionName = interner.intern("minus")
        let functionFQName = kotlinTextPkg + [functionName]
        let charType = types.charType
        let intType = types.intType

        // --- Char.minus(other: Char): Int ---
        let charMinusCharExists = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == charType
                && signature.parameterTypes == [charType]
                && signature.returnType == intType
        }
        if !charMinusCharExists {
            let functionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            if let pkgSym = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(pkgSym, for: functionSymbol)
            }
            symbols.setExternalLinkName("kk_char_minus", for: functionSymbol)
            let otherParamName = interner.intern("other")
            let otherParamSym = symbols.define(
                kind: .valueParameter,
                name: otherParamName,
                fqName: functionFQName + [otherParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: otherParamSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: charType,
                    parameterTypes: [charType],
                    returnType: intType,
                    valueParameterSymbols: [otherParamSym],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: functionSymbol
            )
        }

        // --- Char.minus(n: Int): Char ---
        let charMinusIntExists = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == charType
                && signature.parameterTypes == [intType]
                && signature.returnType == charType
        }
        if !charMinusIntExists {
            let functionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            if let pkgSym = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(pkgSym, for: functionSymbol)
            }
            symbols.setExternalLinkName("kk_char_minus_int", for: functionSymbol)
            let nParamName = interner.intern("n")
            let nParamSym = symbols.define(
                kind: .valueParameter,
                name: nParamName,
                fqName: functionFQName + [nParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: nParamSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: charType,
                    parameterTypes: [intType],
                    returnType: charType,
                    valueParameterSymbols: [nParamSym],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: functionSymbol
            )
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
        for entry in entries {
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
        }
        return enumType
    }

    // MARK: - Native Char.Companion helpers

    private func registerNativeCharCompanionHelpers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = [interner.intern("kotlin")]
        let charSymbol = ensureClassSymbol(
            named: "Char",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinSymbol, for: charSymbol)
        }

        let companionFQName = ensureSyntheticCharCompanionSymbol(
            ownerSymbol: charSymbol,
            symbols: symbols,
            interner: interner
        )
        let charArraySymbol = ensureClassSymbol(
            named: "CharArray",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinSymbol, for: charArraySymbol)
        }
        let charArrayType = types.make(.classType(ClassType(
            classSymbol: charArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativeMarkerFQName = ensureSyntheticCharExperimentalNativeApiAnnotation(
            symbols: symbols,
            interner: interner
        )

        let specs = [
            SyntheticCharCompanionFunctionSpec(
                name: "isSupplementaryCodePoint",
                externalLinkName: "kk_char_isSupplementaryCodePoint",
                parameters: [(name: "codepoint", type: types.intType)],
                returnType: types.booleanType
            ),
            SyntheticCharCompanionFunctionSpec(
                name: "isSurrogatePair",
                externalLinkName: "kk_char_isSurrogatePair",
                parameters: [
                    (name: "high", type: types.charType),
                    (name: "low", type: types.charType),
                ],
                returnType: types.booleanType
            ),
            SyntheticCharCompanionFunctionSpec(
                name: "toChars",
                externalLinkName: "kk_char_toChars",
                parameters: [(name: "codePoint", type: types.intType)],
                returnType: charArrayType
            ),
            SyntheticCharCompanionFunctionSpec(
                name: "toCodePoint",
                externalLinkName: "kk_char_toCodePoint",
                parameters: [
                    (name: "high", type: types.charType),
                    (name: "low", type: types.charType),
                ],
                returnType: types.intType
            ),
        ]

        for spec in specs {
            registerSyntheticCharCompanionFunction(
                spec,
                companionFQName: companionFQName,
                experimentalNativeApiFQName: nativeMarkerFQName,
                symbols: symbols,
                interner: interner
            )
        }
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

    private func ensureSyntheticCharExperimentalNativeApiAnnotation(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        let experimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let markerSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalNativeApi",
            in: experimentalPkg,
            symbols: symbols,
            interner: interner
        )
        if let experimentalPkgSymbol = symbols.lookup(fqName: experimentalPkg) {
            symbols.setParentSymbol(experimentalPkgSymbol, for: markerSymbol)
        }
        return "kotlin.experimental.ExperimentalNativeApi"
    }

    private func registerSyntheticCharCompanionFunction(
        _ spec: SyntheticCharCompanionFunctionSpec,
        companionFQName: [InternedString],
        experimentalNativeApiFQName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }

        let functionName = interner.intern(spec.name)
        let functionFQName = companionFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == spec.parameters.map(\.type)
                && signature.returnType == spec.returnType
        }) {
            symbols.setExternalLinkName(spec.externalLinkName, for: existing)
            attachSyntheticCharExperimentalNativeApi(
                to: existing,
                markerFQName: experimentalNativeApiFQName,
                symbols: symbols
            )
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
        symbols.setParentSymbol(companionSymbol, for: functionSymbol)
        symbols.setExternalLinkName(spec.externalLinkName, for: functionSymbol)
        attachSyntheticCharExperimentalNativeApi(
            to: functionSymbol,
            markerFQName: experimentalNativeApiFQName,
            symbols: symbols
        )

        var valueParameterSymbols: [SymbolID] = []
        for parameter in spec.parameters {
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
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: spec.parameters.map(\.type),
                returnType: spec.returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func attachSyntheticCharExperimentalNativeApi(
        to symbol: SymbolID,
        markerFQName: String,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: markerFQName)
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }
}
