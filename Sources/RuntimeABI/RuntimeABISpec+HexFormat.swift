public extension RuntimeABISpec {
    static let hexFormatFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_default",
            parameters: [],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_create",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_upperCase",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_bytes",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toHexString",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_toHexString",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_toHexString",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToInt",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToShort",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUByte",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUShort",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUInt",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToULong",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToLong",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToByteArray",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUByteArray",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
    ]
}
