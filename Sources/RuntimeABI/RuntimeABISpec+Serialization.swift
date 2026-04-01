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
            name: "kk_json_encodeMapToString",
            parameters: [
                RuntimeABIParameter(name: "jsonRaw", type: .intptr),
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Serialization"
        ),
    ]
}
