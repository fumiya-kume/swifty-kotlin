public extension RuntimeABIExterns {
    static let resultExterns: [ExternDecl] = [
        kk_runCatching,
        kk_result_isSuccess,
        kk_result_isFailure,
        kk_result_getOrNull,
        kk_result_getOrDefault,
        kk_result_getOrElse,
        kk_result_getOrThrow,
        kk_result_exceptionOrNull,
        kk_result_map,
        kk_result_fold,
        kk_result_onSuccess,
        kk_result_onFailure,
    ]

    // STDLIB-280: runCatching
    static let kk_runCatching = ExternDecl(
        name: "kk_runCatching",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // STDLIB-283: Result properties
    static let kk_result_isSuccess = ExternDecl(
        name: "kk_result_isSuccess",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_result_isFailure = ExternDecl(
        name: "kk_result_isFailure",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-281: Result member functions
    static let kk_result_getOrNull = ExternDecl(
        name: "kk_result_getOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_result_getOrDefault = ExternDecl(
        name: "kk_result_getOrDefault",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_result_getOrElse = ExternDecl(
        name: "kk_result_getOrElse",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_result_getOrThrow = ExternDecl(
        name: "kk_result_getOrThrow",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_result_exceptionOrNull = ExternDecl(
        name: "kk_result_exceptionOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-283: Result HOF functions
    static let kk_result_map = ExternDecl(
        name: "kk_result_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_result_fold = ExternDecl(
        name: "kk_result_fold",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_result_onSuccess = ExternDecl(
        name: "kk_result_onSuccess",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_result_onFailure = ExternDecl(
        name: "kk_result_onFailure",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )
}
