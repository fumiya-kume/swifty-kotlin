import Foundation

// Char stdlib extension stubs (STDLIB-080) for kotlin.text.

enum SyntheticCharMemberReturnKind {
    case boolean
    case string
    case int
    case double
    case nullableInt
    case nullableDouble
    case charCategory
    case charDirectionality

    func typeID(in types: TypeSystem, charCategoryType: TypeID? = nil) -> TypeID {
        switch self {
        case .boolean:
            types.booleanType
        case .string:
            types.stringType
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
            // TODO: Define CharDirectionality enum type
            types.intType // Temporarily use Int as placeholder
        }
    }
}

struct SyntheticCharMemberSpec {
    let name: String
    let externalLinkName: String
    let returnKind: SyntheticCharMemberReturnKind
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
        name: "uppercase",
        externalLinkName: "kk_char_uppercase",
        returnKind: .string
    ),
    SyntheticCharMemberSpec(
        name: "lowercase",
        externalLinkName: "kk_char_lowercase",
        returnKind: .string
    ),
    SyntheticCharMemberSpec(
        name: "titlecase",
        externalLinkName: "kk_char_titlecase",
        returnKind: .string
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

private let syntheticCharCategoryEntries: [(name: String, code: String)] = [
    ("UNASSIGNED", "Cn"),
    ("UPPERCASE_LETTER", "Lu"),
    ("LOWERCASE_LETTER", "Ll"),
    ("TITLECASE_LETTER", "Lt"),
    ("MODIFIER_LETTER", "Lm"),
    ("OTHER_LETTER", "Lo"),
    ("NON_SPACING_MARK", "Mn"),
    ("ENCLOSING_MARK", "Me"),
    ("COMBINING_SPACING_MARK", "Mc"),
    ("DECIMAL_DIGIT_NUMBER", "Nd"),
    ("LETTER_NUMBER", "Nl"),
    ("OTHER_NUMBER", "No"),
    ("SPACE_SEPARATOR", "Zs"),
    ("LINE_SEPARATOR", "Zl"),
    ("PARAGRAPH_SEPARATOR", "Zp"),
    ("CONTROL", "Cc"),
    ("FORMAT", "Cf"),
    ("PRIVATE_USE", "Co"),
    ("SURROGATE", "Cs"),
    ("DASH_PUNCTUATION", "Pd"),
    ("START_PUNCTUATION", "Ps"),
    ("END_PUNCTUATION", "Pe"),
    ("CONNECTOR_PUNCTUATION", "Pc"),
    ("OTHER_PUNCTUATION", "Po"),
    ("MATH_SYMBOL", "Sm"),
    ("CURRENCY_SYMBOL", "Sc"),
    ("MODIFIER_SYMBOL", "Sk"),
    ("OTHER_SYMBOL", "So"),
    ("INITIAL_QUOTE_PUNCTUATION", "Pi"),
    ("FINAL_QUOTE_PUNCTUATION", "Pf"),
]

func syntheticCharMemberSpec(named name: String) -> SyntheticCharMemberSpec? {
    syntheticCharMemberSpecs.first { $0.name == name }
}

func syntheticCharCategoryType(
    symbols: SymbolTable,
    types: TypeSystem,
    interner: StringInterner
) -> TypeID? {
    guard let symbol = symbols.lookup(fqName: ["kotlin", "text", "CharCategory"].map({ interner.intern($0) })) else {
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
        let charCategorySymbol = ensureSyntheticCharCategoryEnum(
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
        registerSyntheticCharCategoryMembers(
            enumSymbol: charCategorySymbol,
            receiverType: charCategoryType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        for member in syntheticCharMemberSpecs {
            registerSyntheticCharExtensionFunction(
                named: member.name,
                externalLinkName: member.externalLinkName,
                receiverType: types.charType,
                returnType: member.returnKind.typeID(in: types, charCategoryType: charCategoryType),
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }
        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int)
        registerDigitToIntRadixStub(symbols: symbols, types: types, interner: interner)
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

    private func ensureSyntheticCharCategoryEnum(
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
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        for entry in syntheticCharCategoryEntries {
            let entryName = interner.intern(entry.name)
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
            symbols.setPropertyType(enumType, for: child)
        }
    }

    private func registerSyntheticCharCategoryMembers(
        enumSymbol: SymbolID,
        receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticCharCategoryMemberFunction(
            named: "code",
            externalLinkName: "kk_char_category_code",
            enumSymbol: enumSymbol,
            receiverType: receiverType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCharCategoryMemberFunction(
            named: "contains",
            externalLinkName: "kk_char_category_contains",
            enumSymbol: enumSymbol,
            receiverType: receiverType,
            parameters: [("char", types.charType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCharCategoryMemberFunction(
        named name: String,
        externalLinkName: String,
        enumSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = enumInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
            guard let symbol = symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
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
        symbols.setParentSymbol(enumSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
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
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCharExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
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
}
