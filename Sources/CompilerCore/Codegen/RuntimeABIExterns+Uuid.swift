// MARK: - Uuid (kotlin.uuid.Uuid)

public extension RuntimeABIExterns {
    static let uuidExterns: [ExternDecl] = [
        kk_uuid_random,
        kk_uuid_parse,
        kk_uuid_toString,
        kk_uuid_toHexString,
        kk_uuid_toLongs,
        kk_uuid_toByteArray,
    ]

    static let kk_uuid_random = ExternDecl(
        name: "kk_uuid_random",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_uuid_parse = ExternDecl(
        name: "kk_uuid_parse",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_uuid_toString = ExternDecl(
        name: "kk_uuid_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_toHexString = ExternDecl(
        name: "kk_uuid_toHexString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_toLongs = ExternDecl(
        name: "kk_uuid_toLongs",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_toByteArray = ExternDecl(
        name: "kk_uuid_toByteArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
