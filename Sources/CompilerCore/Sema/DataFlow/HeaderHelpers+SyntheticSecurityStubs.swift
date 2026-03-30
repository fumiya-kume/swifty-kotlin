import Foundation

/// Synthetic stubs for `javax.crypto.Cipher`, `SecretKeySpec`, and `IvParameterSpec`.
extension DataFlowSemaPhase {
    func registerSyntheticSecurityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
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

        // --- Digital Signature / Certificate stubs (STDLIB-SEC-146) ---
        let certPkg = ensurePackage(path: ["java", "security", "cert"], symbols: symbols, interner: interner)
        let certPkgSymbol = symbols.lookup(fqName: certPkg)
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // PublicKey and PrivateKey (opaque key types — no methods needed here)
        let publicKeySymbol = ensureClassSymbol(named: "PublicKey", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: publicKeySymbol) }
        let publicKeyType = types.make(.classType(ClassType(classSymbol: publicKeySymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(publicKeyType, for: publicKeySymbol)

        let privateKeySymbol = ensureClassSymbol(named: "PrivateKey", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: privateKeySymbol) }
        let privateKeyType = types.make(.classType(ClassType(classSymbol: privateKeySymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(privateKeyType, for: privateKeySymbol)

        // KeyPair
        let keyPairSymbol = ensureClassSymbol(named: "KeyPair", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: keyPairSymbol) }
        let keyPairType = types.make(.classType(ClassType(classSymbol: keyPairSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(keyPairType, for: keyPairSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_keypair_new",
            ownerSymbol: keyPairSymbol,
            ownerType: keyPairType,
            parameters: [
                ("publicKey", publicKeyType),
                ("privateKey", privateKeyType),
            ],
            symbols: symbols,
            interner: interner
        )

        registerSecurityMemberProperty(
            name: "publicKey",
            externalLinkName: "kk_keypair_publicKey",
            ownerSymbol: keyPairSymbol,
            propertyType: publicKeyType,
            symbols: symbols,
            interner: interner
        )

        registerSecurityMemberProperty(
            name: "privateKey",
            externalLinkName: "kk_keypair_privateKey",
            ownerSymbol: keyPairSymbol,
            propertyType: privateKeyType,
            symbols: symbols,
            interner: interner
        )

        // KeyPairGenerator
        let keyPairGeneratorSymbol = ensureClassSymbol(named: "KeyPairGenerator", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: keyPairGeneratorSymbol) }
        let keyPairGeneratorType = types.make(.classType(ClassType(classSymbol: keyPairGeneratorSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(keyPairGeneratorType, for: keyPairGeneratorSymbol)

        let keyPairGeneratorCompanionFQName = ensureSecurityCompanionSymbol(
            ownerSymbol: keyPairGeneratorSymbol,
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
        registerSecurityInstanceMethod(
            name: "initialize",
            externalLinkName: "kk_keypairgenerator_initialize",
            ownerSymbol: keyPairGeneratorSymbol,
            ownerType: keyPairGeneratorType,
            parameters: [("keysize", intType)],
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

        // Signature
        let signatureSymbol = ensureClassSymbol(named: "Signature", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: signatureSymbol) }
        let signatureType = types.make(.classType(ClassType(classSymbol: signatureSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(signatureType, for: signatureSymbol)

        let signatureCompanionFQName = ensureSecurityCompanionSymbol(
            ownerSymbol: signatureSymbol,
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
            parameters: [("signature", byteArrayType)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // Certificate (base type in java.security.cert)
        let certificateSymbol = ensureClassSymbol(named: "Certificate", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certificateSymbol) }
        let certificateType = types.make(.classType(ClassType(classSymbol: certificateSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(certificateType, for: certificateSymbol)

        // X509Certificate (subtype of Certificate)
        let x509CertSymbol = ensureClassSymbol(named: "X509Certificate", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: x509CertSymbol) }
        let x509CertType = types.make(.classType(ClassType(classSymbol: x509CertSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(x509CertType, for: x509CertSymbol)

        registerSecurityInstanceMethod(
            name: "getPublicKey",
            externalLinkName: "kk_x509certificate_getPublicKey",
            ownerSymbol: x509CertSymbol,
            ownerType: x509CertType,
            parameters: [],
            returnType: publicKeyType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "getEncoded",
            externalLinkName: "kk_x509certificate_getEncoded",
            ownerSymbol: x509CertSymbol,
            ownerType: x509CertType,
            parameters: [],
            returnType: byteArrayType,
            symbols: symbols,
            interner: interner
        )

        // CertificateFactory
        let certFactorySymbol = ensureClassSymbol(named: "CertificateFactory", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certFactorySymbol) }
        let certFactoryType = types.make(.classType(ClassType(classSymbol: certFactorySymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(certFactoryType, for: certFactorySymbol)

        let certFactoryCompanionFQName = ensureSecurityCompanionSymbol(
            ownerSymbol: certFactorySymbol,
            symbols: symbols,
            interner: interner
        )
        registerSecurityCompanionFactory(
            name: "getInstance",
            externalLinkName: "kk_certificatefactory_getInstance",
            companionFQName: certFactoryCompanionFQName,
            parameters: [("type", stringType)],
            returnType: certFactoryType,
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "generateCertificate",
            externalLinkName: "kk_certificatefactory_generateCertificate",
            ownerSymbol: certFactorySymbol,
            ownerType: certFactoryType,
            parameters: [("inStream", byteArrayType)],
            returnType: certificateType,
            symbols: symbols,
            interner: interner
        )

        // CertPath
        let certListType: TypeID = if let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]) {
            types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(certificateType)], nullability: .nonNull)))
        } else { types.anyType }

        let certPathSymbol = ensureClassSymbol(named: "CertPath", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certPathSymbol) }
        let certPathType = types.make(.classType(ClassType(classSymbol: certPathSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(certPathType, for: certPathSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_certpath_new",
            ownerSymbol: certPathSymbol,
            ownerType: certPathType,
            parameters: [("certificates", certListType)],
            symbols: symbols,
            interner: interner
        )

        // TrustAnchor
        let trustAnchorSymbol = ensureClassSymbol(named: "TrustAnchor", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: trustAnchorSymbol) }
        let trustAnchorType = types.make(.classType(ClassType(classSymbol: trustAnchorSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(trustAnchorType, for: trustAnchorSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_trustanchor_new",
            ownerSymbol: trustAnchorSymbol,
            ownerType: trustAnchorType,
            parameters: [("trustedCert", certificateType)],
            symbols: symbols,
            interner: interner
        )

        // PKIXParameters
        let trustAnchorListType: TypeID = if let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]) {
            types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(trustAnchorType)], nullability: .nonNull)))
        } else { types.anyType }

        let pkixParamsSymbol = ensureClassSymbol(named: "PKIXParameters", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: pkixParamsSymbol) }
        let pkixParamsType = types.make(.classType(ClassType(classSymbol: pkixParamsSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(pkixParamsType, for: pkixParamsSymbol)

        registerSecurityConstructor(
            externalLinkName: "kk_pkixparameters_new",
            ownerSymbol: pkixParamsSymbol,
            ownerType: pkixParamsType,
            parameters: [("trustAnchors", trustAnchorListType)],
            symbols: symbols,
            interner: interner
        )
        registerSecurityInstanceMethod(
            name: "setTrustAnchors",
            externalLinkName: "kk_pkixparameters_setTrustAnchors",
            ownerSymbol: pkixParamsSymbol,
            ownerType: pkixParamsType,
            parameters: [("trustAnchors", trustAnchorListType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )

        // CertPathValidator
        let certPathValidatorSymbol = ensureClassSymbol(named: "CertPathValidator", in: certPkg, symbols: symbols, interner: interner)
        if let certPkgSymbol { symbols.setParentSymbol(certPkgSymbol, for: certPathValidatorSymbol) }
        let certPathValidatorType = types.make(.classType(ClassType(classSymbol: certPathValidatorSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(certPathValidatorType, for: certPathValidatorSymbol)

        let certPathValidatorCompanionFQName = ensureSecurityCompanionSymbol(
            ownerSymbol: certPathValidatorSymbol,
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
        registerSecurityInstanceMethod(
            name: "validate",
            externalLinkName: "kk_certpathvalidator_validate",
            ownerSymbol: certPathValidatorSymbol,
            ownerType: certPathValidatorType,
            parameters: [
                ("certPath", certPathType),
                ("params", pkixParamsType),
            ],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
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

    private func ensureSecurityCompanionSymbol(
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

    private func registerSecurityMemberProperty(
        name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbols.symbol($0)?.kind == .property }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
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

}
