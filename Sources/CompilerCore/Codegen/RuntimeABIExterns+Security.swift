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

    static let securityExterns: [ExternDecl] = [
        kk_secretkeyspec_new,
        kk_ivparameterspec_new,
        kk_cipher_getInstance,
        kk_cipher_init,
        kk_cipher_init_with_iv,
        kk_cipher_doFinal,
        kk_cipher_doFinal_noarg,
    ]
}
