// MARK: - JSON Serialization (STDLIB-SER-132)

public extension RuntimeABIExterns {
    static let serializationExterns: [ExternDecl] = [
        kk_json_default,
        kk_json_encodeToString,
        kk_json_encodeWithSerializer,
        kk_json_decodeFromString,
        kk_json_decodeWithSerializer,
        kk_json_encodeMapToString,
        kk_json_registerSerializer,
        kk_json_getRegisteredSerializer,
        kk_json_encoder_context,
        kk_json_encoder_encodeString,
        kk_json_encoder_encodeInt,
        kk_json_encoder_encodeBoolean,
        kk_json_encoder_encodeDouble,
        kk_json_encoder_encodeNull,
        kk_json_encoder_encodeValue,
        kk_json_decoder_context,
        kk_json_decoder_decodeString,
        kk_json_decoder_decodeInt,
        kk_json_decoder_decodeBoolean,
        kk_json_decoder_decodeDouble,
        kk_json_decoder_decodeValue,
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

    static let kk_json_encodeWithSerializer = ExternDecl(
        name: "kk_json_encodeWithSerializer",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_json_decodeFromString = ExternDecl(
        name: "kk_json_decodeFromString",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_json_decodeWithSerializer = ExternDecl(
        name: "kk_json_decodeWithSerializer",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_json_encodeMapToString = ExternDecl(
        name: "kk_json_encodeMapToString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_registerSerializer = ExternDecl(
        name: "kk_json_registerSerializer",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_json_getRegisteredSerializer = ExternDecl(
        name: "kk_json_getRegisteredSerializer",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_context = ExternDecl(
        name: "kk_json_encoder_context",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeString = ExternDecl(
        name: "kk_json_encoder_encodeString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeInt = ExternDecl(
        name: "kk_json_encoder_encodeInt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeBoolean = ExternDecl(
        name: "kk_json_encoder_encodeBoolean",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeDouble = ExternDecl(
        name: "kk_json_encoder_encodeDouble",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeNull = ExternDecl(
        name: "kk_json_encoder_encodeNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_encoder_encodeValue = ExternDecl(
        name: "kk_json_encoder_encodeValue",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_context = ExternDecl(
        name: "kk_json_decoder_context",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_decodeString = ExternDecl(
        name: "kk_json_decoder_decodeString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_decodeInt = ExternDecl(
        name: "kk_json_decoder_decodeInt",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_decodeBoolean = ExternDecl(
        name: "kk_json_decoder_decodeBoolean",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_decodeDouble = ExternDecl(
        name: "kk_json_decoder_decodeDouble",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_json_decoder_decodeValue = ExternDecl(
        name: "kk_json_decoder_decodeValue",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
