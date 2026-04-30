import Foundation

/// Synthetic stubs for kotlin.text.HexFormat class, companion, and extension functions.
extension DataFlowSemaPhase {
    func registerSyntheticHexFormatStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureHexFormatKotlinTextPackage(symbols: symbols, interner: interner)

        // --- HexFormat class symbol ---
        let hexFormatSymbol = ensureClassSymbol(
            named: "HexFormat",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let hexFormatType = types.make(.classType(ClassType(
            classSymbol: hexFormatSymbol,
            args: [],
            nullability: .nonNull
        )))

        let stringType = types.stringType
        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let byteArrayType = makeHexFormatByteArrayType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let uByteArrayType = makeHexFormatUByteArrayType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let listIntType = makeHexFormatListIntType(
            symbols: symbols,
            types: types,
            interner: interner
        )

        // --- HexFormat.Default companion property ---
        _ = ensureHexFormatCompanionSymbol(
            ownerSymbol: hexFormatSymbol,
            hexFormatType: hexFormatType,
            symbols: symbols,
            interner: interner
        )

        // --- HexFormat.upperCase property ---
        registerHexFormatMemberProperty(
            named: "upperCase",
            externalLinkName: "kk_hexformat_upperCase",
            ownerSymbol: hexFormatSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // --- HexFormat.bytes property (returns HexFormat itself for chaining) ---
        // In Kotlin, HexFormat.bytes returns a BytesHexFormat but we simplify to HexFormat.
        registerHexFormatMemberProperty(
            named: "bytes",
            externalLinkName: "kk_hexformat_bytes",
            ownerSymbol: hexFormatSymbol,
            returnType: hexFormatType,
            symbols: symbols,
            interner: interner
        )

        // --- HexFormat builder DSL: HexFormat { } top-level function ---
        let builderLambdaType = types.make(.functionType(FunctionType(
            receiver: hexFormatType,
            params: [],
            returnType: types.unitType,
            nullability: .nonNull
        )))
        registerHexFormatTopLevelFunction(
            named: "HexFormat",
            packageFQName: kotlinTextPkg,
            parameters: [("builderAction", builderLambdaType)],
            returnType: hexFormatType,
            externalLinkName: "kk_hexformat_create",
            symbols: symbols,
            interner: interner
        )

        // --- Int.toHexString(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "toHexString",
            externalLinkName: "kk_int_toHexString",
            receiverType: intType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- Long.toHexString(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "toHexString",
            externalLinkName: "kk_long_toHexString",
            receiverType: longType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- ByteArray.toHexString(format: HexFormat) ---
        // Register on both List<Int> (internal representation) and ByteArray (user-facing type)
        for receiverType in [listIntType, byteArrayType] {
            registerHexFormatExtensionFunction(
                named: "toHexString",
                externalLinkName: "kk_bytearray_toHexString",
                receiverType: receiverType,
                parameters: [("format", hexFormatType, true, false)],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // --- String.hexToInt(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToInt",
            externalLinkName: "kk_string_hexToInt",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToShort(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToShort",
            externalLinkName: "kk_string_hexToShort",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToUByte(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToUByte",
            externalLinkName: "kk_string_hexToUByte",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: types.ubyteType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToUShort(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToUShort",
            externalLinkName: "kk_string_hexToUShort",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: types.ushortType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToUInt(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToUInt",
            externalLinkName: "kk_string_hexToUInt",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: types.uintType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToULong(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToULong",
            externalLinkName: "kk_string_hexToULong",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: types.ulongType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToLong(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToLong",
            externalLinkName: "kk_string_hexToLong",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: longType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToByteArray(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToByteArray",
            externalLinkName: "kk_string_hexToByteArray",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.hexToUByteArray(format: HexFormat) ---
        registerHexFormatExtensionFunction(
            named: "hexToUByteArray",
            externalLinkName: "kk_string_hexToUByteArray",
            receiverType: stringType,
            parameters: [("format", hexFormatType, true, false)],
            returnType: uByteArrayType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - HexFormat Helpers

    private func ensureHexFormatKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let textName = interner.intern("text")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinTextPkg: [InternedString] = [kotlinName, textName]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package, name: textName, fqName: kotlinTextPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }

    private func ensureHexFormatCompanionSymbol(
        ownerSymbol: SymbolID,
        hexFormatType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }

        // Check if companion already exists
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            // Ensure Default field exists
            ensureHexFormatDefaultField(
                companionSymbol: existingCompanion,
                companionFQName: companionInfo.fqName,
                hexFormatType: hexFormatType,
                symbols: symbols,
                interner: interner
            )
            return companionInfo.fqName
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

        ensureHexFormatDefaultField(
            companionSymbol: companionSymbol,
            companionFQName: companionFQName,
            hexFormatType: hexFormatType,
            symbols: symbols,
            interner: interner
        )

        return companionFQName
    }

    private func ensureHexFormatDefaultField(
        companionSymbol: SymbolID,
        companionFQName: [InternedString],
        hexFormatType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let defaultName = interner.intern("Default")
        let defaultFQName = companionFQName + [defaultName]
        if symbols.lookup(fqName: defaultFQName) != nil {
            return
        }
        let defaultSymbol = symbols.define(
            kind: .property,
            name: defaultName,
            fqName: defaultFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(companionSymbol, for: defaultSymbol)
        symbols.setPropertyType(hexFormatType, for: defaultSymbol)
        symbols.setExternalLinkName("kk_hexformat_default", for: defaultSymbol)
        attachExperimentalStdlibApiAnnotation(to: defaultSymbol, symbols: symbols)
    }

    private func makeHexFormatByteArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let fqName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        if let symbol = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(
                classSymbol: symbol, args: [], nullability: .nonNull
            )))
        }
        return types.anyType
    }

    private func makeHexFormatUByteArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let fqName: [InternedString] = [interner.intern("kotlin"), interner.intern("UByteArray")]
        if let symbol = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(
                classSymbol: symbol, args: [], nullability: .nonNull
            )))
        }
        return types.anyType
    }

    private func makeHexFormatListIntType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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
            args: [.out(types.intType)],
            nullability: .nonNull
        )))
    }

    private func registerHexFormatMemberProperty(
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
        attachExperimentalStdlibApiAnnotation(to: propertySymbol, symbols: symbols)
    }

    private func registerHexFormatTopLevelFunction(
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
        attachExperimentalStdlibApiAnnotation(to: functionSymbol, symbols: symbols)

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

    private func registerHexFormatExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
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
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        attachExperimentalStdlibApiAnnotation(to: functionSymbol, symbols: symbols)

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

    private func attachExperimentalStdlibApiAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi")
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(record) {
            annotations.append(record)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
