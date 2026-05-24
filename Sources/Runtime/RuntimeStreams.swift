import Foundation

// MARK: - kotlin.streams bridge functions (STDLIB-STREAMS-FN-001, STDLIB-STREAMS-FN-005)

private func runtimeStreamElementsOrPanic(from streamRaw: Int, caller: StaticString) -> [Int] {
    if let elements = runtimeParallelStreamElements(from: streamRaw) {
        return elements
    }
    if let elements = runtimeSequenceSourceElements(from: streamRaw) {
        return elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid stream handle")
}

private func runtimeStreamAsSequence(_ streamRaw: Int, caller: StaticString) -> Int {
    let elements = runtimeStreamElementsOrPanic(from: streamRaw, caller: caller)
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: elements)]))
}

private func runtimeSequenceAsStream(_ sequenceRaw: Int, caller: StaticString) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: sequenceRaw, caller: caller)
    return registerRuntimeObject(RuntimeParallelStreamBox(
        elements: elements,
        workerCount: 1,
        chunkSize: max(1, elements.count)
    ))
}

@_cdecl("kk_stream_asSequence")
public func kk_stream_asSequence(_ streamRaw: Int) -> Int {
    runtimeStreamAsSequence(streamRaw, caller: #function)
}

@_cdecl("kk_int_stream_asSequence")
public func kk_int_stream_asSequence(_ streamRaw: Int) -> Int {
    runtimeStreamAsSequence(streamRaw, caller: #function)
}

@_cdecl("kk_long_stream_asSequence")
public func kk_long_stream_asSequence(_ streamRaw: Int) -> Int {
    runtimeStreamAsSequence(streamRaw, caller: #function)
}

@_cdecl("kk_double_stream_asSequence")
public func kk_double_stream_asSequence(_ streamRaw: Int) -> Int {
    runtimeStreamAsSequence(streamRaw, caller: #function)
}

@_cdecl("kk_sequence_asStream")
public func kk_sequence_asStream(_ sequenceRaw: Int) -> Int {
    runtimeSequenceAsStream(sequenceRaw, caller: #function)
}
