// Symmetric crypto functions (STDLIB-SEC-144).

public extension RuntimeABISpec {
    static let securityFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_secretkeyspec_new",
            parameters: [
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "algorithmRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ivparameterspec_new",
            parameters: [
                RuntimeABIParameter(name: "ivRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_getInstance",
            parameters: [
                RuntimeABIParameter(name: "transformationRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_init",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "opmodeRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_init_with_iv",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "opmodeRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "ivRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_doFinal",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "dataRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_doFinal_noarg",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypairgenerator_getInstance",
            parameters: [
                RuntimeABIParameter(name: "algorithmRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypairgenerator_initialize",
            parameters: [
                RuntimeABIParameter(name: "generatorRaw", type: .intptr),
                RuntimeABIParameter(name: "keySizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypairgenerator_generateKeyPair",
            parameters: [
                RuntimeABIParameter(name: "generatorRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypair_new",
            parameters: [
                RuntimeABIParameter(name: "publicKeyRaw", type: .intptr),
                RuntimeABIParameter(name: "privateKeyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypair_public",
            parameters: [
                RuntimeABIParameter(name: "keyPairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypair_private",
            parameters: [
                RuntimeABIParameter(name: "keyPairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypair_publicKey",
            parameters: [
                RuntimeABIParameter(name: "keyPairRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_keypair_privateKey",
            parameters: [
                RuntimeABIParameter(name: "keyPairRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_getInstance",
            parameters: [
                RuntimeABIParameter(name: "algorithmRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_initSign",
            parameters: [
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "privateKeyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_initVerify",
            parameters: [
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "publicKeyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_update",
            parameters: [
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "dataRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_sign",
            parameters: [
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_signature_verify",
            parameters: [
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "signatureBytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_certificatefactory_getInstance",
            parameters: [
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_certificatefactory_generateCertificate",
            parameters: [
                RuntimeABIParameter(name: "factoryRaw", type: .intptr),
                RuntimeABIParameter(name: "dataRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_x509certificate_getPublicKey",
            parameters: [
                RuntimeABIParameter(name: "certificateRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_x509certificate_getEncoded",
            parameters: [
                RuntimeABIParameter(name: "certificateRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_certpath_new",
            parameters: [
                RuntimeABIParameter(name: "certificatesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_certpathvalidator_getInstance",
            parameters: [
                RuntimeABIParameter(name: "algorithmRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_certpathvalidator_validate",
            parameters: [
                RuntimeABIParameter(name: "validatorRaw", type: .intptr),
                RuntimeABIParameter(name: "certPathRaw", type: .intptr),
                RuntimeABIParameter(name: "parametersRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_trustanchor_new",
            parameters: [
                RuntimeABIParameter(name: "certificateRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pkixparameters_new",
            parameters: [
                RuntimeABIParameter(name: "trustAnchorsRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pkixparameters_setTrustAnchors",
            parameters: [
                RuntimeABIParameter(name: "parametersRaw", type: .intptr),
                RuntimeABIParameter(name: "trustAnchorsRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
    ]
}
