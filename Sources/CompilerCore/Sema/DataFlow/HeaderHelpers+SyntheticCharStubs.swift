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

    func typeID(in types: TypeSystem) -> TypeID {
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
            // TODO: Define CharCategory enum type
            types.intType // Temporarily use Int as placeholder
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

func syntheticCharMemberSpec(named name: String) -> SyntheticCharMemberSpec? {
    syntheticCharMemberSpecs.first { $0.name == name }
}

extension DataFlowSemaPhase {
    func registerSyntheticCharStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackageForCharStubs(symbols: symbols, interner: interner)
        for member in syntheticCharMemberSpecs {
            registerSyntheticCharExtensionFunction(
                named: member.name,
                externalLinkName: member.externalLinkName,
                receiverType: types.charType,
                returnType: member.returnKind.typeID(in: types),
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }
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
}
