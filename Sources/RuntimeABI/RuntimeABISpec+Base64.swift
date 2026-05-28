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
            name: "kk_base64_withPadding_default",
            parameters: [
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_withPadding_urlsafe",
            parameters: [
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_withPadding_mime",
            parameters: [
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_withPadding_instance",
            parameters: [
                RuntimeABIParameter(name: "instanceRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
            ],
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
        RuntimeABIFunctionSpec(
            name: "kk_base64_decodeFromByteArray_default",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decodeFromByteArray_urlsafe",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decodeFromByteArray_mime",
            parameters: [
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "paddingOptionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encode_instance",
            parameters: [
                RuntimeABIParameter(name: "instanceRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decode_instance",
            parameters: [
                RuntimeABIParameter(name: "instanceRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_encodeToByteArray_instance",
            parameters: [
                RuntimeABIParameter(name: "instanceRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_base64_decodeFromByteArray_instance",
            parameters: [
                RuntimeABIParameter(name: "instanceRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
        // STDLIB-IO-ENC-FN-002: OutputStream.encodingWith(base64: Base64): OutputStream
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_encodingWith",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "base64Raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
    ]
}
