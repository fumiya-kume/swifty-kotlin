// Uuid functions (kotlin.uuid.Uuid).

public extension RuntimeABISpec {
    static let uuidFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_uuid_random",
            parameters: [],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_parse",
            parameters: [
                RuntimeABIParameter(name: "uuidString", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_toString",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_toHexString",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_toLongs",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_toByteArray",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
    ]
}
