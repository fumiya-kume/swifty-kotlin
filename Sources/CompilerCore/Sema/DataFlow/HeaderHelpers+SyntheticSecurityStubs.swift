import Foundation

/// Synthetic stubs for `javax.crypto.Cipher`, `SecretKeySpec`, `IvParameterSpec`, and `java.security.MessageDigest`.
extension DataFlowSemaPhase {
    func registerSyntheticSecurityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let cryptoPkg = ensurePackage(path: ["javax", "crypto"], symbols: symbols, interner: interner)
        let cryptoSpecPkg = ensurePackage(path: ["javax", "crypto", "spec"], symbols: symbols, interner: interner)

        let intType = types.intType
        let stringType = types.stringType
        let unitType = types.unitType
        let byteArrayType = makeSecurityByteArrayType(symbols: symbols, types: types, interner: interner)

        let secretKeySpecSymbol = ensureClassSymbol(
            named: "SecretKeySpec",
            in: cryptoSpecPkg,
            symbols: symbols,
            interner: interner
        )
        let secretKeySpecType = types.make(.classType(ClassType(
            classSymbol: secretKeySpecSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(secretKeySpecType, for: secretKeySpecSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_secretkeyspec_new",
            ownerSymbol: secretKeySpecSymbol,
            ownerType: secretKeySpecType,
            parameters: [
                ("key", byteArrayType),
                ("algorithm", stringType),
            ],
            symbols: symbols,
            interner: interner
        )

        let ivParameterSpecSymbol = ensureClassSymbol(
            named: "IvParameterSpec",
            in: cryptoSpecPkg,
            symbols: symbols,
            interner: interner
        )
        let ivParameterSpecType = types.make(.classType(ClassType(
            classSymbol: ivParameterSpecSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ivParameterSpecType, for: ivParameterSpecSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_ivparameterspec_new",
            ownerSymbol: ivParameterSpecSymbol,
            ownerType: ivParameterSpecType,
            parameters: [
                ("iv", byteArrayType),
            ],
            symbols: symbols,
            interner: interner
        )

        let cipherSymbol = ensureClassSymbol(
            named: "Cipher",
            in: cryptoPkg,
            symbols: symbols,
            interner: interner
        )
        let cipherType = types.make(.classType(ClassType(
            classSymbol: cipherSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cipherType, for: cipherSymbol)

        let cipherCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: cipherSymbol,
            symbols: symbols,
            interner: interner
        )

        registerCipherConstant(
            name: "ENCRYPT_MODE",
            value: 1,
            ownerFQName: cipherCompanionFQName,
            ownerSymbol: cipherSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerCipherConstant(
            name: "DECRYPT_MODE",
            value: 2,
            ownerFQName: cipherCompanionFQName,
            ownerSymbol: cipherSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerCipherConstant(
            name: "WRAP_MODE",
            value: 3,
            ownerFQName: cipherCompanionFQName,
            ownerSymbol: cipherSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerCipherConstant(
            name: "UNWRAP_MODE",
            value: 4,
            ownerFQName: cipherCompanionFQName,
            ownerSymbol: cipherSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_cipher_getInstance",
            companionFQName: cipherCompanionFQName,
            parameters: [("transformation", stringType)],
            returnType: cipherType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityInstanceMethod(
            name: "init",
            externalLinkName: "kk_cipher_init",
            ownerSymbol: cipherSymbol,
            ownerType: cipherType,
            parameters: [
                ("opmode", intType),
                ("key", secretKeySpecType),
            ],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityInstanceMethod(
            name: "init",
            externalLinkName: "kk_cipher_init_with_iv",
            ownerSymbol: cipherSymbol,
            ownerType: cipherType,
            parameters: [
                ("opmode", intType),
                ("key", secretKeySpecType),
                ("iv", ivParameterSpecType),
            ],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityInstanceMethod(
            name: "doFinal",
            externalLinkName: "kk_cipher_doFinal",
            ownerSymbol: cipherSymbol,
            ownerType: cipherType,
            parameters: [("data", byteArrayType)],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityInstanceMethod(
            name: "doFinal",
            externalLinkName: "kk_cipher_doFinal_noarg",
            ownerSymbol: cipherSymbol,
            ownerType: cipherType,
            parameters: [],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - MessageDigest stubs (java.security)
        let securityPkg = ensurePackage(path: ["java", "security"], symbols: symbols, interner: interner)
        let securityPkgSymbol = symbols.lookup(fqName: securityPkg)
        let digestSymbol = ensureClassSymbol(named: "MessageDigest", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: digestSymbol) }
        let digestType = types.make(.classType(ClassType(classSymbol: digestSymbol, args: [], nullability: .nonNull)))
        let digestByteArrayType: TypeID = if let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]) {
            types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(types.intType)], nullability: .nonNull)))
        } else { types.anyType }
        symbols.setPropertyType(digestType, for: digestSymbol)

        registerDigestTopLevel(packageFQName: securityPkg, name: "getInstance", parameterTypes: [types.stringType], returnType: digestType, externalLinkName: "kk_message_digest_getInstance", symbols: symbols, interner: interner)
        registerDigestMember(ownerSymbol: digestSymbol, ownerType: digestType, name: "digest", parameterTypes: [digestByteArrayType], returnType: digestByteArrayType, externalLinkName: "kk_message_digest_digest", symbols: symbols, interner: interner)
    }

    private func registerDigestTopLevel(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let fn = interner.intern(name)
        let fq = packageFQName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: sym) }
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

    private func registerDigestMember(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let fn = interner.intern(name)
        let fq = ownerInfo.fqName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: sym)
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

    private func ensureCipherCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existing = symbols.companionObjectSymbol(for: ownerSymbol),
           let info = symbols.symbol(existing)
        {
            return info.fqName
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

    private func registerCipherConstant(
        name: String,
        value: Int,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        intType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let constName = interner.intern(name)
        let constFQName = ownerFQName + [constName]
        guard symbols.lookupAll(fqName: constFQName).first(where: { symbols.symbol($0)?.kind == .property }) == nil else {
            return
        }
        let symbol = symbols.define(
            kind: .property,
            name: constName,
            fqName: constFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .constValue]
        )
        symbols.setParentSymbol(ownerSymbol, for: symbol)
        symbols.setPropertyType(intType, for: symbol)
        symbols.setConstValueExprKind(.intLiteral(Int64(value)), for: symbol)
    }

    private func registerSecurityCompanionFactory(
        name: String,
        externalLinkName: String,
        companionFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = companionFQName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
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

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(companionSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
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
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSecurityInstanceMethod(
        name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType &&
                existingSignature.receiverType == ownerType
        }) == nil else {
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSecurityConstructor(
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        guard symbols.lookupAll(fqName: ctorFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == ownerType
        }) == nil else {
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

    private func makeSecurityByteArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let byteArraySymbol = ensureClassSymbol(
            named: "ByteArray",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let byteArrayType = types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(byteArrayType, for: byteArraySymbol)
        return byteArrayType
    }

    private func registerDigestTopLevel(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let fn = interner.intern(name)
        let fq = packageFQName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: sym) }
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

    private func registerDigestMember(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let fn = interner.intern(name)
        let fq = ownerInfo.fqName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: sym)
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

}
