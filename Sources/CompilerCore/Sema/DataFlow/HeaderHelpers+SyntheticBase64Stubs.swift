import Foundation

/// Synthetic stubs for kotlin.io.encoding.Base64 (STDLIB-031-ABI-001).
///
/// Wires the Kotlin Base64 variants (Default / UrlSafe / Mime / Pem)
/// and their PaddingOption enum to the `kk_base64_*` ABI entry points in RuntimeBase64.swift.
extension DataFlowSemaPhase {
    func registerSyntheticBase64Stubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // ── Package: kotlin.io.encoding ──────────────────────────────────────────
        let ioEncodingPkg = ensureBase64Package(symbols: symbols, interner: interner)

        // ── Types ────────────────────────────────────────────────────────────────
        let base64Symbol = ensureClassSymbol(
            named: "Base64",
            in: ioEncodingPkg,
            symbols: symbols,
            interner: interner
        )
        if let ioEncodingPkgSymbol = symbols.lookup(fqName: ioEncodingPkg) {
            symbols.setParentSymbol(ioEncodingPkgSymbol, for: base64Symbol)
        }
        let stringType = types.stringType
        let intType = types.intType
        let byteArrayType = makeBase64ByteArrayType(symbols: symbols, types: types, interner: interner)
        let base64Type = types.make(.classType(ClassType(
            classSymbol: base64Symbol,
            args: [],
            nullability: .nonNull
        )))
        let paddingOptionSymbol = ensureBase64PaddingOptionEnum(
            base64Symbol: base64Symbol,
            symbols: symbols,
            interner: interner
        )
        let paddingOptionType = types.make(.classType(ClassType(
            classSymbol: paddingOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        setBase64PaddingOptionEntryTypes(
            enumSymbol: paddingOptionSymbol,
            enumType: paddingOptionType,
            symbols: symbols
        )

        registerBase64VariantObjects(
            base64Symbol: base64Symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerBase64MemberFunction(
            named: "encode",
            externalLinkName: "kk_base64_encode_default",
            ownerSymbol: base64Symbol,
            receiverType: base64Type,
            parameters: [
                ("source", byteArrayType),
            ],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        registerBase64MemberFunction(
            named: "decode",
            externalLinkName: "kk_base64_decode_default",
            ownerSymbol: base64Symbol,
            receiverType: base64Type,
            parameters: [
                ("source", stringType),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        registerBase64MemberFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_base64_encodeToByteArray_default",
            ownerSymbol: base64Symbol,
            receiverType: base64Type,
            parameters: [
                ("source", byteArrayType),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        registerBase64MemberFunction(
            named: "decodeFromByteArray",
            externalLinkName: "kk_base64_decodeFromByteArray_default",
            ownerSymbol: base64Symbol,
            receiverType: base64Type,
            parameters: [
                ("source", byteArrayType),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        registerBase64MemberFunction(
            named: "withPadding",
            externalLinkName: "kk_base64_withPadding_instance",
            ownerSymbol: base64Symbol,
            receiverType: base64Type,
            parameters: [
                ("option", paddingOptionType),
            ],
            returnType: base64Type,
            symbols: symbols,
            interner: interner
        )

        // PaddingOption is passed as a raw Int (enum ordinal) across the ABI.
        // We model it as Int in function signatures to keep the ABI simple.
        let rawPaddingOptionType = intType

        // ── Base64.PaddingOption enum constants ──────────────────────────────────
        registerBase64PaddingOptionConstants(
            pkg: ioEncodingPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── encode / decode: Default ─────────────────────────────────────────────
        registerBase64TopLevelFunction(
            named: "kk_base64_encode_default_fn",
            externalLinkName: "kk_base64_encode_default",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("bytes", byteArrayType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerBase64ThrowingTopLevelFunction(
            named: "kk_base64_decode_default_fn",
            externalLinkName: "kk_base64_decode_default",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("string", stringType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── encode / decode: UrlSafe ─────────────────────────────────────────────
        registerBase64TopLevelFunction(
            named: "kk_base64_encode_urlsafe_fn",
            externalLinkName: "kk_base64_encode_urlsafe",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("bytes", byteArrayType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerBase64ThrowingTopLevelFunction(
            named: "kk_base64_decode_urlsafe_fn",
            externalLinkName: "kk_base64_decode_urlsafe",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("string", stringType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── encode / decode: Mime ────────────────────────────────────────────────
        registerBase64TopLevelFunction(
            named: "kk_base64_encode_mime_fn",
            externalLinkName: "kk_base64_encode_mime",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("bytes", byteArrayType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerBase64ThrowingTopLevelFunction(
            named: "kk_base64_decode_mime_fn",
            externalLinkName: "kk_base64_decode_mime",
            packageFQName: ioEncodingPkg,
            parameters: [
                ("string", stringType, false),
                ("padding", rawPaddingOptionType, false),
            ],
            returnType: byteArrayType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── encodeToByteArray variants ───────────────────────────────────────────
        for (name, link) in [
            ("kk_base64_encodeToByteArray_default_fn", "kk_base64_encodeToByteArray_default"),
            ("kk_base64_encodeToByteArray_urlsafe_fn", "kk_base64_encodeToByteArray_urlsafe"),
            ("kk_base64_encodeToByteArray_mime_fn", "kk_base64_encodeToByteArray_mime"),
        ] {
            registerBase64TopLevelFunction(
                named: name,
                externalLinkName: link,
                packageFQName: ioEncodingPkg,
                parameters: [
                    ("bytes", byteArrayType, false),
                    ("padding", rawPaddingOptionType, false),
                ],
                returnType: byteArrayType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    // MARK: - Package helpers

    private func registerBase64VariantObjects(
        base64Symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for variant in ["Default", "UrlSafe", "Mime", "Pem"] {
            let objectSymbol = ensureBase64VariantObject(
                named: variant,
                base64Symbol: base64Symbol,
                symbols: symbols,
                interner: interner
            )
            symbols.setDirectSupertypes([base64Symbol], for: objectSymbol)
            types.setNominalDirectSupertypes([base64Symbol], for: objectSymbol)
        }
    }

    private func ensureBase64VariantObject(
        named name: String,
        base64Symbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        guard let base64Info = symbols.symbol(base64Symbol) else {
            return base64Symbol
        }
        let objectName = interner.intern(name)
        let objectFQName = base64Info.fqName + [objectName]
        if let existing = symbols.lookup(fqName: objectFQName) {
            return existing
        }
        let objectSymbol = symbols.define(
            kind: .object,
            name: objectName,
            fqName: objectFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(base64Symbol, for: objectSymbol)
        return objectSymbol
    }

    private func ensureBase64PaddingOptionEnum(
        base64Symbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        guard let base64Info = symbols.symbol(base64Symbol) else {
            return base64Symbol
        }
        let name = interner.intern("PaddingOption")
        let fqName = base64Info.fqName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(base64Symbol, for: enumSymbol)

        for entry in ["PRESENT", "ABSENT", "PRESENT_OPTIONAL", "ABSENT_OPTIONAL"] {
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
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }
        return enumSymbol
    }

    private func setBase64PaddingOptionEntryTypes(
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

    private func ensureBase64Package(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let ioName = interner.intern("io")
        let encodingName = interner.intern("encoding")

        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let ioFQ: [InternedString] = [kotlinName, ioName]
        if symbols.lookup(fqName: ioFQ) == nil {
            _ = symbols.define(
                kind: .package, name: ioName, fqName: ioFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let encodingFQ: [InternedString] = [kotlinName, ioName, encodingName]
        if symbols.lookup(fqName: encodingFQ) == nil {
            _ = symbols.define(
                kind: .package, name: encodingName, fqName: encodingFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return encodingFQ
    }

    private func makeBase64ByteArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let fqName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        if let sym = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(classSymbol: sym, args: [], nullability: .nonNull)))
        }
        return types.anyType
    }

    // MARK: - PaddingOption enum ordinal constants

    /// Registers `Base64.PaddingOption.PRESENT / ABSENT / PRESENT_OPTIONAL / ABSENT_OPTIONAL`
    /// as simple Int-valued synthetic properties in the `kotlin.io.encoding` package.
    /// The raw value must match `Base64PaddingOption` in RuntimeBase64.swift.
    private func registerBase64PaddingOptionConstants(
        pkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let intType = types.intType
        let entries: [(name: String, externalLinkName: String)] = [
            ("Base64PaddingOptionPresent", "kk_base64_padding_present"),
            ("Base64PaddingOptionAbsent", "kk_base64_padding_absent"),
            ("Base64PaddingOptionPresentOptional", "kk_base64_padding_present_optional"),
            ("Base64PaddingOptionAbsentOptional", "kk_base64_padding_absent_optional"),
        ]
        for entry in entries {
            let name = interner.intern(entry.name)
            let fqName = pkg + [name]
            if symbols.lookup(fqName: fqName) != nil { continue }
            let sym = symbols.define(
                kind: .property, name: name, fqName: fqName,
                declSite: nil, visibility: .public, flags: [.synthetic, .static]
            )
            if let pkgSym = symbols.lookup(fqName: pkg) {
                symbols.setParentSymbol(pkgSym, for: sym)
            }
            symbols.setPropertyType(intType, for: sym)
            symbols.setExternalLinkName(entry.externalLinkName, for: sym)
        }
    }

    // MARK: - Function registration helpers

    private func registerBase64MemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let funcName = interner.intern(name)
        let fqName = ownerInfo.fqName + [funcName]
        if symbols.lookupAll(fqName: fqName).contains(where: { candidate in
            guard let symbol = symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map { $0.type }
                && signature.returnType == returnType
        }) {
            return
        }

        let funcSym = symbols.define(
            kind: .function,
            name: funcName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSym)
        symbols.setExternalLinkName(externalLinkName, for: funcSym)

        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in parameters {
            let pName = interner.intern(param.name)
            let pSym = symbols.define(
                kind: .valueParameter,
                name: pName,
                fqName: fqName + [pName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSym, for: pSym)
            paramTypes.append(param.type)
            paramSymbols.append(pSym)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: paramTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: funcSym
        )
    }

    private func registerBase64TopLevelFunction(
        named name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        types _: TypeSystem,
        interner: StringInterner
    ) {
        let funcName = interner.intern(name)
        let fqName = packageFQName + [funcName]
        if symbols.lookup(fqName: fqName) != nil { return }

        let funcSym = symbols.define(
            kind: .function, name: funcName, fqName: fqName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        if let pkgSym = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSym, for: funcSym)
        }
        symbols.setExternalLinkName(externalLinkName, for: funcSym)

        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in parameters {
            let pName = interner.intern(param.name)
            let pSym = symbols.define(
                kind: .valueParameter, name: pName, fqName: fqName + [pName],
                declSite: nil, visibility: .private, flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSym, for: pSym)
            paramTypes.append(param.type)
            paramSymbols.append(pSym)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: paramTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: funcSym
        )
    }

    private func registerBase64ThrowingTopLevelFunction(
        named name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Throwing functions use the same ABI (outThrown pointer is handled by codegen).
        registerBase64TopLevelFunction(
            named: name,
            externalLinkName: externalLinkName,
            packageFQName: packageFQName,
            parameters: parameters,
            returnType: returnType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
