import Foundation

/// Synthetic stubs for `javax.crypto.Cipher`, `SecretKeySpec`, `IvParameterSpec`, `Mac`, and `java.security.MessageDigest`.
extension DataFlowSemaPhase {
    func registerSyntheticSecurityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let cryptoPkg = ensurePackage(path: ["javax", "crypto"], symbols: symbols, interner: interner)
        let cryptoSpecPkg = ensurePackage(path: ["javax", "crypto", "spec"], symbols: symbols, interner: interner)

        let intType = types.intType
        let boolType = types.booleanType
        let stringType = types.stringType
        let unitType = types.unitType
        let anyType = types.anyType
        let byteArrayType = makeSecurityByteArrayType(symbols: symbols, types: types, interner: interner)
        let securityPkg = ensurePackage(path: ["java", "security"], symbols: symbols, interner: interner)
        let securityPkgSymbol = symbols.lookup(fqName: securityPkg)
        let certPkg = ensurePackage(path: ["java", "security", "cert"], symbols: symbols, interner: interner)
        let certPkgSymbol = symbols.lookup(fqName: certPkg)

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
            canThrow: true,
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
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_cipher_getInstance",
            ownerSymbol: cipherSymbol,
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

        let macSymbol = ensureClassSymbol(
            named: "Mac",
            in: cryptoPkg,
            symbols: symbols,
            interner: interner
        )
        let macType = types.make(.classType(ClassType(
            classSymbol: macSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(macType, for: macSymbol)

        let macCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: macSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_mac_getInstance",
            companionFQName: macCompanionFQName,
            parameters: [("algorithm", stringType)],
            returnType: macType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_mac_getInstance",
            ownerSymbol: macSymbol,
            parameters: [("algorithm", stringType)],
            returnType: macType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "init",
            externalLinkName: "kk_mac_init",
            ownerSymbol: macSymbol,
            ownerType: macType,
            parameters: [("key", secretKeySpecType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "doFinal",
            externalLinkName: "kk_mac_doFinal",
            ownerSymbol: macSymbol,
            ownerType: macType,
            parameters: [("data", byteArrayType)],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        let publicKeySymbol = ensureClassSymbol(
            named: "PublicKey",
            in: securityPkg,
            symbols: symbols,
            interner: interner
        )
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: publicKeySymbol) }
        let publicKeyType = types.make(.classType(ClassType(
            classSymbol: publicKeySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(publicKeyType, for: publicKeySymbol)

        let privateKeySymbol = ensureClassSymbol(
            named: "PrivateKey",
            in: securityPkg,
            symbols: symbols,
            interner: interner
        )
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: privateKeySymbol) }
        let privateKeyType = types.make(.classType(ClassType(
            classSymbol: privateKeySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(privateKeyType, for: privateKeySymbol)

        let keyPairSymbol = ensureClassSymbol(
            named: "KeyPair",
            in: securityPkg,
            symbols: symbols,
            interner: interner
        )
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: keyPairSymbol) }
        let keyPairType = types.make(.classType(ClassType(
            classSymbol: keyPairSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(keyPairType, for: keyPairSymbol)

        registerSecurityMemberProperty(
            name: "publicKey",
            ownerSymbol: keyPairSymbol,
            propertyType: publicKeyType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityMemberProperty(
            name: "privateKey",
            ownerSymbol: keyPairSymbol,
            propertyType: privateKeyType,
            symbols: symbols,
            interner: interner
        )

        let keyPairGeneratorSymbol = ensureClassSymbol(
            named: "KeyPairGenerator",
            in: securityPkg,
            symbols: symbols,
            interner: interner
        )
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: keyPairGeneratorSymbol) }
        let keyPairGeneratorType = types.make(.classType(ClassType(
            classSymbol: keyPairGeneratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(keyPairGeneratorType, for: keyPairGeneratorSymbol)
        let keyPairGeneratorCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: keyPairGeneratorSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_keypairgenerator_getInstance",
            ownerSymbol: keyPairGeneratorSymbol,
            ownerType: keyPairGeneratorType,
            parameters: [("algorithm", stringType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_keypairgenerator_getInstance",
            companionFQName: keyPairGeneratorCompanionFQName,
            parameters: [("algorithm", stringType)],
            returnType: keyPairGeneratorType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_keypairgenerator_getInstance",
            ownerSymbol: keyPairGeneratorSymbol,
            parameters: [("algorithm", stringType)],
            returnType: keyPairGeneratorType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "initialize",
            externalLinkName: "kk_keypairgenerator_initialize",
            ownerSymbol: keyPairGeneratorSymbol,
            ownerType: keyPairGeneratorType,
            parameters: [("keySize", intType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "generateKeyPair",
            externalLinkName: "kk_keypairgenerator_generateKeyPair",
            ownerSymbol: keyPairGeneratorSymbol,
            ownerType: keyPairGeneratorType,
            parameters: [],
            returnType: keyPairType,
            symbols: symbols,
            interner: interner
        )

        let signatureSymbol = ensureClassSymbol(
            named: "Signature",
            in: securityPkg,
            symbols: symbols,
            interner: interner
        )
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: signatureSymbol) }
        let signatureType = types.make(.classType(ClassType(
            classSymbol: signatureSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(signatureType, for: signatureSymbol)
        let signatureCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: signatureSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_signature_getInstance",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [("algorithm", stringType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_signature_getInstance",
            companionFQName: signatureCompanionFQName,
            parameters: [("algorithm", stringType)],
            returnType: signatureType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_signature_getInstance",
            ownerSymbol: signatureSymbol,
            parameters: [("algorithm", stringType)],
            returnType: signatureType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "initSign",
            externalLinkName: "kk_signature_initSign",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [("privateKey", privateKeyType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "initVerify",
            externalLinkName: "kk_signature_initVerify",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [("publicKey", publicKeyType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "update",
            externalLinkName: "kk_signature_update",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [("data", byteArrayType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "sign",
            externalLinkName: "kk_signature_sign",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "verify",
            externalLinkName: "kk_signature_verify",
            ownerSymbol: signatureSymbol,
            ownerType: signatureType,
            parameters: [("signatureBytes", byteArrayType)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        let certificateFactorySymbol = ensureClassSymbol(
            named: "CertificateFactory",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certificateFactorySymbol) }
        let certificateFactoryType = types.make(.classType(ClassType(
            classSymbol: certificateFactorySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(certificateFactoryType, for: certificateFactorySymbol)

        let x509CertificateSymbol = ensureClassSymbol(
            named: "X509Certificate",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: x509CertificateSymbol) }
        let x509CertificateType = types.make(.classType(ClassType(
            classSymbol: x509CertificateSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(x509CertificateType, for: x509CertificateSymbol)

        let certPathSymbol = ensureClassSymbol(
            named: "CertPath",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certPathSymbol) }
        let certPathType = types.make(.classType(ClassType(
            classSymbol: certPathSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(certPathType, for: certPathSymbol)

        let trustAnchorSymbol = ensureClassSymbol(
            named: "TrustAnchor",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: trustAnchorSymbol) }
        let trustAnchorType = types.make(.classType(ClassType(
            classSymbol: trustAnchorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(trustAnchorType, for: trustAnchorSymbol)

        let pkixParametersSymbol = ensureClassSymbol(
            named: "PKIXParameters",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: pkixParametersSymbol) }
        let pkixParametersType = types.make(.classType(ClassType(
            classSymbol: pkixParametersSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pkixParametersType, for: pkixParametersSymbol)

        let certPathValidatorSymbol = ensureClassSymbol(
            named: "CertPathValidator",
            in: certPkg,
            symbols: symbols,
            interner: interner
        )
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certPathValidatorSymbol) }
        let certPathValidatorType = types.make(.classType(ClassType(
            classSymbol: certPathValidatorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(certPathValidatorType, for: certPathValidatorSymbol)

        let certificateFactoryCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: certificateFactorySymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_certificatefactory_getInstance",
            ownerSymbol: certificateFactorySymbol,
            ownerType: certificateFactoryType,
            parameters: [("type", stringType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_certificatefactory_getInstance",
            companionFQName: certificateFactoryCompanionFQName,
            parameters: [("type", stringType)],
            returnType: certificateFactoryType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_certificatefactory_getInstance",
            ownerSymbol: certificateFactorySymbol,
            parameters: [("type", stringType)],
            returnType: certificateFactoryType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "generateCertificate",
            externalLinkName: "kk_certificatefactory_generateCertificate",
            ownerSymbol: certificateFactorySymbol,
            ownerType: certificateFactoryType,
            parameters: [("data", anyType)],
            returnType: x509CertificateType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityConstructor(
            externalLinkName: "kk_certpath_new",
            ownerSymbol: certPathSymbol,
            ownerType: certPathType,
            parameters: [("certificates", anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_trustanchor_new",
            ownerSymbol: trustAnchorSymbol,
            ownerType: trustAnchorType,
            parameters: [("certificate", x509CertificateType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_pkixparameters_new",
            ownerSymbol: pkixParametersSymbol,
            ownerType: pkixParametersType,
            parameters: [("trustAnchors", anyType)],
            symbols: symbols,
            interner: interner
        )

        let certPathValidatorCompanionFQName = ensureCipherCompanionSymbol(
            ownerSymbol: certPathValidatorSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityConstructor(
            externalLinkName: "kk_certpathvalidator_getInstance",
            ownerSymbol: certPathValidatorSymbol,
            ownerType: certPathValidatorType,
            parameters: [("algorithm", stringType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_certpathvalidator_getInstance",
            companionFQName: certPathValidatorCompanionFQName,
            parameters: [("algorithm", stringType)],
            returnType: certPathValidatorType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityStaticMethod(
            name: "getInstance",
            externalLinkName: "kk_certpathvalidator_getInstance",
            ownerSymbol: certPathValidatorSymbol,
            parameters: [("algorithm", stringType)],
            returnType: certPathValidatorType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "validate",
            externalLinkName: "kk_certpathvalidator_validate",
            ownerSymbol: certPathValidatorSymbol,
            ownerType: certPathValidatorType,
            parameters: [
                ("certPath", certPathType),
                ("parameters", pkixParametersType),
            ],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - MessageDigest stubs (java.security)
        let digestSymbol = ensureClassSymbol(named: "MessageDigest", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: digestSymbol) }
        let digestType = types.make(.classType(ClassType(classSymbol: digestSymbol, args: [], nullability: .nonNull)))
        let digestByteArrayType = byteArrayType
        symbols.setPropertyType(digestType, for: digestSymbol)

        registerDigestTopLevel(packageFQName: securityPkg, name: "getInstance", parameterTypes: [types.stringType], returnType: digestType, externalLinkName: "kk_message_digest_getInstance", symbols: symbols, interner: interner)
        registerDigestMember(ownerSymbol: digestSymbol, ownerType: digestType, name: "digest", parameterTypes: [digestByteArrayType], returnType: digestByteArrayType, externalLinkName: "kk_message_digest_digest", symbols: symbols, interner: interner)
    }

    private func ensureCompanionSymbol(
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

    private func ensureCipherCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        return ensureCompanionSymbol(ownerSymbol: ownerSymbol, symbols: symbols, interner: interner)
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
        let parentSymbol = symbols.lookup(fqName: ownerFQName) ?? ownerSymbol
        symbols.setParentSymbol(parentSymbol, for: symbol)
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
            flags: [.synthetic, .static]
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

    private func registerSecurityStaticMethod(
        name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType &&
                existingSignature.receiverType == nil
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
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
        canThrow: Bool = false,
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
                canThrow: canThrow,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSecurityMemberProperty(
        name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbols.symbol($0)?.kind == .property }) {
            symbols.setPropertyType(propertyType, for: existing)
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
