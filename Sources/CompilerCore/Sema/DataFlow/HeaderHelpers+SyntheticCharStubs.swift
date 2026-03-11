import Foundation

// Char stdlib extension stubs (STDLIB-080) for kotlin.text.

extension DataFlowSemaPhase {
    func registerSyntheticCharStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackageForCharStubs(symbols: symbols, interner: interner)
        let members: [(name: String, externalLinkName: String)] = [
            ("isDigit", "kk_char_isDigit"),
            ("isLetter", "kk_char_isLetter"),
            ("isLetterOrDigit", "kk_char_isLetterOrDigit"),
            ("isWhitespace", "kk_char_isWhitespace"),
        ]

        for member in members {
            registerSyntheticCharExtensionFunction(
                named: member.name,
                externalLinkName: member.externalLinkName,
                receiverType: types.charType,
                returnType: types.booleanType,
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
