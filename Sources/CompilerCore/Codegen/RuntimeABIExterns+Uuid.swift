// MARK: - Uuid (kotlin.uuid.Uuid)

public extension RuntimeABIExterns {
    static let uuidExterns: [ExternDecl] = [
        kk_uuid_random,
        kk_uuid_parse,
        kk_uuid_toString,
        kk_uuid_toHexString,
        kk_uuid_toLongs,
        kk_uuid_toByteArray,
        kk_uuid_version,
        kk_uuid_variant,
        kk_uuid_mostSignificantBits,
        kk_uuid_leastSignificantBits,
        kk_uuid_nameUUIDFromBytes,
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

    static let kk_uuid_version = ExternDecl(
        name: "kk_uuid_version",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_variant = ExternDecl(
        name: "kk_uuid_variant",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_mostSignificantBits = ExternDecl(
        name: "kk_uuid_mostSignificantBits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_leastSignificantBits = ExternDecl(
        name: "kk_uuid_leastSignificantBits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uuid_nameUUIDFromBytes = ExternDecl(
        name: "kk_uuid_nameUUIDFromBytes",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
