// Symmetric crypto extern declarations (STDLIB-SEC-144).

public extension RuntimeABIExterns {
    public static let kk_secretkeyspec_new = ExternDecl(
        name: "kk_secretkeyspec_new",
        parameterTypes: [intptr, intptr],
        returnType: intptr
    )

    public static let kk_ivparameterspec_new = ExternDecl(
        name: "kk_ivparameterspec_new",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_cipher_getInstance = ExternDecl(
        name: "kk_cipher_getInstance",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_cipher_init = ExternDecl(
        name: "kk_cipher_init",
        parameterTypes: [intptr, intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_cipher_init_with_iv = ExternDecl(
        name: "kk_cipher_init_with_iv",
        parameterTypes: [intptr, intptr, intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_cipher_doFinal = ExternDecl(
        name: "kk_cipher_doFinal",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_cipher_doFinal_noarg = ExternDecl(
        name: "kk_cipher_doFinal_noarg",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let securityExterns: [ExternDecl] = [
        kk_secretkeyspec_new,
        kk_ivparameterspec_new,
        kk_cipher_getInstance,
        kk_cipher_init,
        kk_cipher_init_with_iv,
        kk_cipher_doFinal,
        kk_cipher_doFinal_noarg,
    ]
}
