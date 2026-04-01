// MARK: - JSON Serialization (STDLIB-SER-132)

public extension RuntimeABIExterns {
    static let serializationExterns: [ExternDecl] = [
        kk_json_default,
        kk_json_encodeToString,
        kk_json_decodeFromString,
        kk_json_encodeMapToString,
    ]

    static let kk_json_default = ExternDecl(
        name: "kk_json_default",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_json_encodeToString = ExternDecl(
        name: "kk_json_encodeToString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decodeFromString = ExternDecl(
        name: "kk_json_decodeFromString",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_json_encodeMapToString = ExternDecl(
        name: "kk_json_encodeMapToString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
