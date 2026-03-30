// BroadcastChannel / Pipeline ABI specs (CORO-076)

public extension RuntimeABISpec {
    static let broadcastChannelFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_broadcast_channel_create",
            parameters: [
                RuntimeABIParameter(name: "subscriberCapacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_broadcast_channel_subscribe",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_broadcast_channel_unsubscribe",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "subscriberHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_broadcast_channel_send",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_broadcast_channel_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_pipeline_drain",
            parameters: [
                RuntimeABIParameter(name: "sourceHandle", type: .intptr),
                RuntimeABIParameter(name: "destHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
    ]
}
