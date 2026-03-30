// Symmetric crypto extern declarations (STDLIB-SEC-144).

public extension RuntimeABIExterns {
    static let kk_keypairgenerator_getInstance = ExternDecl(
        name: "kk_keypairgenerator_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypairgenerator_initialize = ExternDecl(
        name: "kk_keypairgenerator_initialize",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypairgenerator_generateKeyPair = ExternDecl(
        name: "kk_keypairgenerator_generateKeyPair",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_new = ExternDecl(
        name: "kk_keypair_new",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_publicKey = ExternDecl(
        name: "kk_keypair_publicKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_privateKey = ExternDecl(
        name: "kk_keypair_privateKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_getInstance = ExternDecl(
        name: "kk_signature_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_initSign = ExternDecl(
        name: "kk_signature_initSign",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_initVerify = ExternDecl(
        name: "kk_signature_initVerify",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_update = ExternDecl(
        name: "kk_signature_update",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_sign = ExternDecl(
        name: "kk_signature_sign",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_verify = ExternDecl(
        name: "kk_signature_verify",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certificatefactory_getInstance = ExternDecl(
        name: "kk_certificatefactory_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certificatefactory_generateCertificate = ExternDecl(
        name: "kk_certificatefactory_generateCertificate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_x509certificate_getPublicKey = ExternDecl(
        name: "kk_x509certificate_getPublicKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_x509certificate_getEncoded = ExternDecl(
        name: "kk_x509certificate_getEncoded",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpath_new = ExternDecl(
        name: "kk_certpath_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpathvalidator_getInstance = ExternDecl(
        name: "kk_certpathvalidator_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpathvalidator_validate = ExternDecl(
        name: "kk_certpathvalidator_validate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_trustanchor_new = ExternDecl(
        name: "kk_trustanchor_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_pkixparameters_new = ExternDecl(
        name: "kk_pkixparameters_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_pkixparameters_setTrustAnchors = ExternDecl(
        name: "kk_pkixparameters_setTrustAnchors",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )


    static let kk_secretkeyspec_new = ExternDecl(
        name: "kk_secretkeyspec_new",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ivparameterspec_new = ExternDecl(
        name: "kk_ivparameterspec_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_cipher_getInstance = ExternDecl(
        name: "kk_cipher_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
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

    static let kk_keypairgenerator_getInstance = ExternDecl(
        name: "kk_keypairgenerator_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypairgenerator_initialize = ExternDecl(
        name: "kk_keypairgenerator_initialize",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypairgenerator_generateKeyPair = ExternDecl(
        name: "kk_keypairgenerator_generateKeyPair",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_new = ExternDecl(
        name: "kk_keypair_new",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_publicKey = ExternDecl(
        name: "kk_keypair_publicKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_keypair_privateKey = ExternDecl(
        name: "kk_keypair_privateKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_getInstance = ExternDecl(
        name: "kk_signature_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_initSign = ExternDecl(
        name: "kk_signature_initSign",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_initVerify = ExternDecl(
        name: "kk_signature_initVerify",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_update = ExternDecl(
        name: "kk_signature_update",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_sign = ExternDecl(
        name: "kk_signature_sign",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_signature_verify = ExternDecl(
        name: "kk_signature_verify",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certificatefactory_getInstance = ExternDecl(
        name: "kk_certificatefactory_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certificatefactory_generateCertificate = ExternDecl(
        name: "kk_certificatefactory_generateCertificate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_x509certificate_getPublicKey = ExternDecl(
        name: "kk_x509certificate_getPublicKey",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_x509certificate_getEncoded = ExternDecl(
        name: "kk_x509certificate_getEncoded",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpath_new = ExternDecl(
        name: "kk_certpath_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpathvalidator_getInstance = ExternDecl(
        name: "kk_certpathvalidator_getInstance",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_certpathvalidator_validate = ExternDecl(
        name: "kk_certpathvalidator_validate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_trustanchor_new = ExternDecl(
        name: "kk_trustanchor_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_pkixparameters_new = ExternDecl(
        name: "kk_pkixparameters_new",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_pkixparameters_setTrustAnchors = ExternDecl(
        name: "kk_pkixparameters_setTrustAnchors",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
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
        kk_x509certificate_getPublicKey,
        kk_x509certificate_getEncoded,
        kk_certpath_new,
        kk_certpathvalidator_getInstance,
        kk_certpathvalidator_validate,
        kk_trustanchor_new,
        kk_pkixparameters_new,
        kk_pkixparameters_setTrustAnchors,
        kk_secretkeyspec_new,
        kk_ivparameterspec_new,
        kk_cipher_getInstance,
        kk_cipher_init,
        kk_cipher_init_with_iv,
        kk_cipher_doFinal,
        kk_cipher_doFinal_noarg,
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
        kk_x509certificate_getPublicKey,
        kk_x509certificate_getEncoded,
        kk_certpath_new,
        kk_certpathvalidator_getInstance,
        kk_certpathvalidator_validate,
        kk_trustanchor_new,
        kk_pkixparameters_new,
        kk_pkixparameters_setTrustAnchors,
    ]
}
