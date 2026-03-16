/// File I/O extern declarations (STDLIB-320)
public extension RuntimeABIExterns {
    static let fileIOExterns: [ExternDecl] = [
        kk_file_new,
        kk_file_readText,
        kk_file_writeText,
        kk_file_readLines,
    ]

    static let kk_file_new = ExternDecl(
        name: "kk_file_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_readText = ExternDecl(
        name: "kk_file_readText",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_file_writeText = ExternDecl(
        name: "kk_file_writeText",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_file_readLines = ExternDecl(
        name: "kk_file_readLines",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )
}
