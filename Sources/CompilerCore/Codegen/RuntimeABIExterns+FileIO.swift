/// File I/O extern declarations (STDLIB-320/321/322/323)
public extension RuntimeABIExterns {
    static let fileIOExterns: [ExternDecl] = [
        kk_file_new,
        kk_file_readText,
        kk_file_writeText,
        kk_file_readLines,
        kk_file_exists,
        kk_file_isFile,
        kk_file_isDirectory,
        kk_file_name,
        kk_file_path,
        kk_file_forEachLine,
        kk_file_delete,
        kk_file_mkdirs,
        kk_file_listFiles,
        kk_file_walk,
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

    static let kk_file_exists = ExternDecl(
        name: "kk_file_exists",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_isFile = ExternDecl(
        name: "kk_file_isFile",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_isDirectory = ExternDecl(
        name: "kk_file_isDirectory",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_name = ExternDecl(
        name: "kk_file_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_path = ExternDecl(
        name: "kk_file_path",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_forEachLine = ExternDecl(
        name: "kk_file_forEachLine",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_file_delete = ExternDecl(
        name: "kk_file_delete",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_mkdirs = ExternDecl(
        name: "kk_file_mkdirs",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_listFiles = ExternDecl(
        name: "kk_file_listFiles",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_file_walk = ExternDecl(
        name: "kk_file_walk",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
