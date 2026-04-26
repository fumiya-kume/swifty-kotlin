public extension RuntimeABISpec {
    static let base64Functions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_base64_padding_present",
            parameters: [],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_padding_absent",
            parameters: [],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_padding_present_optional",
            parameters: [],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_padding_absent_optional",
            parameters: [],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encode_default",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decode_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encode_urlsafe",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decode_urlsafe",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encode_mime",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decode_mime",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encodeToByteArray_default",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encodeToByteArray_urlsafe",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encodeToByteArray_mime",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
    ]
}
