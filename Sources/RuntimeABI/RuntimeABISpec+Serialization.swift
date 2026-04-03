// JSON Serialization ABI specification (STDLIB-SER-132).

public extension RuntimeABISpec {
    static let serializationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_json_default",
            parameters: [],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encodeToString",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encodeWithSerializer",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "serializerRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decodeFromString",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decodeWithSerializer",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "serializerRaw", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encodeMapToString",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_register_data_class_field_name",
            parameters: [
                RuntimeABIParameter(name: "classID", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_registerSerializer",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "serializerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_getRegisteredSerializer",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_context",
            parameters: [RuntimeABIParameter(name: "encoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeString",
            parameters: [
                RuntimeABIParameter(name: "encoderRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeInt",
            parameters: [
                RuntimeABIParameter(name: "encoderRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeBoolean",
            parameters: [
                RuntimeABIParameter(name: "encoderRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeDouble",
            parameters: [
                RuntimeABIParameter(name: "encoderRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeNull",
            parameters: [RuntimeABIParameter(name: "encoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_encoder_encodeValue",
            parameters: [
                RuntimeABIParameter(name: "encoderRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_context",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_decodeString",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_decodeInt",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_decodeBoolean",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_decodeDouble",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_json_decoder_decodeValue",
            parameters: [RuntimeABIParameter(name: "decoderRaw", type: .intptr)],
            returnType: .intptr,
            section: "Serialization"
        ),
    ]
}
