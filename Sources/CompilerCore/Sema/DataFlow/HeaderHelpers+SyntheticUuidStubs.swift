import Foundation

/// Synthetic stdlib stubs for kotlin.uuid.Uuid.
/// Registers the Uuid class, companion factory methods (random, parse),
/// and instance methods (toString, toHexString, toLongs, toByteArray).
extension DataFlowSemaPhase {
    func registerSyntheticUuidStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure kotlin.uuid package hierarchy
        let kotlinUuidPkg = ensureUuidPackageHierarchy(
            symbols: symbols,
            interner: interner
        )

        // --- Uuid class symbol ---
        let uuidSymbol = ensureClassSymbol(
            named: "Uuid",
            in: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )

        let uuidType = types.make(.classType(ClassType(
            classSymbol: uuidSymbol,
            args: [],
            nullability: .nonNull
        )))

        let stringType = types.stringType
        let longType = types.longType

        // --- Companion object for factory methods ---
        let companionFQName = ensureUuidCompanionSymbol(
            ownerSymbol: uuidSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Uuid.random() companion factory ---
        registerUuidCompanionMethod(
            named: "random",
            externalLinkName: "kk_uuid_random",
            returnType: uuidType,
            parameters: [],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Uuid.parse(string: String) companion factory ---
        registerUuidCompanionMethod(
            named: "parse",
            externalLinkName: "kk_uuid_parse",
            returnType: uuidType,
            parameters: [(name: "uuidString", type: stringType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Instance methods ---

        // toString() -> String
        registerUuidInstanceMethod(
            named: "toString",
            externalLinkName: "kk_uuid_toString",
            returnType: stringType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        // toHexString() -> String
        registerUuidInstanceMethod(
            named: "toHexString",
            externalLinkName: "kk_uuid_toHexString",
            returnType: stringType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        // toLongs() -> Pair<Long, Long>
        // Return type is Pair (erased), resolved at call site to Pair<Long, Long>
        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairSymbol = symbols.lookup(fqName: pairFQName) ?? symbols.lookupByShortName(interner.intern("Pair")).first
        let pairReturnType: TypeID
        if let pairSym = pairSymbol {
            pairReturnType = types.make(.classType(ClassType(
                classSymbol: pairSym,
                args: [.invariant(longType), .invariant(longType)],
                nullability: .nonNull
            )))
        } else {
            // Fallback: use Any if Pair is not yet registered
            pairReturnType = types.anyType
        }

        registerUuidInstanceMethod(
            named: "toLongs",
            externalLinkName: "kk_uuid_toLongs",
            returnType: pairReturnType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        // toByteArray() -> ByteArray
        // ByteArray is represented as intType in the compiler (same as IntArray)
        let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        let byteArrayType: TypeID
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            byteArrayType = types.intType
        }

        registerUuidInstanceMethod(
            named: "toByteArray",
            externalLinkName: "kk_uuid_toByteArray",
            returnType: byteArrayType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        registerUuidInstanceMethod(
            named: "version",
            externalLinkName: "kk_uuid_version",
            returnType: types.intType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        registerUuidInstanceMethod(
            named: "variant",
            externalLinkName: "kk_uuid_variant",
            returnType: types.intType,
            parameters: [],
            ownerSymbol: uuidSymbol,
            ownerType: uuidType,
            symbols: symbols,
            interner: interner
        )

        // mostSignificantBits: Long (property)
        registerUuidInstanceProperty(
            named: "mostSignificantBits",
            externalLinkName: "kk_uuid_mostSignificantBits",
            returnType: longType,
            ownerSymbol: uuidSymbol,
            symbols: symbols,
            interner: interner
        )

        // leastSignificantBits: Long (property)
        registerUuidInstanceProperty(
            named: "leastSignificantBits",
            externalLinkName: "kk_uuid_leastSignificantBits",
            returnType: longType,
            ownerSymbol: uuidSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Uuid.nameUUIDFromBytes(name: ByteArray) companion factory ---
        registerUuidCompanionMethod(
            named: "nameUUIDFromBytes",
            externalLinkName: "kk_uuid_nameUUIDFromBytes",
            returnType: uuidType,
            parameters: [(name: "name", type: byteArrayType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Uuid Helpers

    private func ensureUuidPackageHierarchy(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let uuidName = interner.intern("uuid")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinUuidFQ: [InternedString] = [kotlinName, uuidName]
        if symbols.lookup(fqName: kotlinUuidFQ) == nil {
            _ = symbols.define(
                kind: .package, name: uuidName, fqName: kotlinUuidFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinUuidFQ
    }

    private func ensureUuidCompanionSymbol(
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

    private func registerUuidCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
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

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerUuidInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
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
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
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

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerUuidInstanceProperty(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: {
            symbols.symbol($0)?.kind == .property
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
}
