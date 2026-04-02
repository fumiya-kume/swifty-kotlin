// Symmetric crypto extern declarations (STDLIB-SEC-144).

public extension RuntimeABIExterns {
    static let kk_secretkeyspec_new = ExternDecl(
        name: "kk_secretkeyspec_new",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_ivparameterspec_new = ExternDecl(
        name: "kk_ivparameterspec_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_getInstance = ExternDecl(
        name: "kk_cipher_getInstance",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_init = ExternDecl(
        name: "kk_cipher_init",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_init_with_iv = ExternDecl(
        name: "kk_cipher_init_with_iv",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_doFinal = ExternDecl(
        name: "kk_cipher_doFinal",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_doFinal_noarg = ExternDecl(
        name: "kk_cipher_doFinal_noarg",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let securityExterns: [ExternDecl] = [
        kk_keypairgenerator_getInstance,
        kk_keypairgenerator_initialize,
        kk_keypairgenerator_generateKeyPair,
        kk_keypair_new,
        kk_keypair_publicKey,
        kk_keypair_privateKey,
        kk_signature_getInstance,
        kk_signature_initSign,
        kk_signature_initVerify,
        kk_signature_update,
        kk_signature_sign,
        kk_signature_verify,
        kk_certificatefactory_getInstance,
        kk_certificatefactory_generateCertificate,
        kk_certificatefactory_generateCertificate_inputStream,
        kk_x509certificate_getPublicKey,
        kk_x509certificate_getEncoded,
        kk_certpath_new,
        kk_certificatefactory_generateCertPath,
        kk_certpathvalidator_getInstance,
        kk_certpathvalidator_validate,
        kk_trustanchor_new,
        kk_trustanchor_new_with_constraints,
        kk_pkixparameters_new,
        kk_pkixparameters_new_from_set,
        kk_pkixparameters_setTrustAnchors,
        kk_secretkeyspec_new,
        kk_ivparameterspec_new,
        kk_cipher_getInstance,
        kk_cipher_init,
        kk_cipher_init_with_iv,
        kk_cipher_doFinal,
        kk_cipher_doFinal_noarg,
    ]
}
