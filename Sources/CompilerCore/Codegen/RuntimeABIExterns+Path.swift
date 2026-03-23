// MARK: - kotlin.io.path.Path

public extension RuntimeABIExterns {
    static let kk_path_new = ExternDecl(
        name: "kk_path_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_name = ExternDecl(
        name: "kk_path_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_parent = ExternDecl(
        name: "kk_path_parent",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_toString = ExternDecl(
        name: "kk_path_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_resolve_string = ExternDecl(
        name: "kk_path_resolve_string",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_resolve_path = ExternDecl(
        name: "kk_path_resolve_path",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_exists = ExternDecl(
        name: "kk_path_exists",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_isDirectory = ExternDecl(
        name: "kk_path_isDirectory",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_isRegularFile = ExternDecl(
        name: "kk_path_isRegularFile",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_readText = ExternDecl(
        name: "kk_path_readText",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_path_writeText = ExternDecl(
        name: "kk_path_writeText",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_path_readLines = ExternDecl(
        name: "kk_path_readLines",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_path_createDirectories = ExternDecl(
        name: "kk_path_createDirectories",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_path_deleteIfExists = ExternDecl(
        name: "kk_path_deleteIfExists",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_path_listDirectoryEntries = ExternDecl(
        name: "kk_path_listDirectoryEntries",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let pathExterns: [ExternDecl] = [
        kk_path_new,
        kk_path_name,
        kk_path_parent,
        kk_path_toString,
        kk_path_resolve_string,
        kk_path_resolve_path,
        kk_path_exists,
        kk_path_isDirectory,
        kk_path_isRegularFile,
        kk_path_readText,
        kk_path_writeText,
        kk_path_readLines,
        kk_path_createDirectories,
        kk_path_deleteIfExists,
        kk_path_listDirectoryEntries,
    ]
}
