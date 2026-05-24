// JVM stream ABI specs (kotlin.streams)

public extension RuntimeABISpec {
    static let streamFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_stream_asSequence",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_stream_asSequence",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_stream_asSequence",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_stream_toList",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_stream_asSequence",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_asStream",
            parameters: [
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Streams"
        ),
    ]
}
