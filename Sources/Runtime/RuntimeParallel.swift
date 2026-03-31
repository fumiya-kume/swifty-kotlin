import Dispatch
import Foundation

// MARK: - Parallel Processing (STDLIB-PERF-155)

private final class UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private extension NSLock {
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

final class RuntimeParallelPoolBox {
    let workerCount: Int
    let chunkSize: Int

    init(workerCount: Int, chunkSize: Int = 32) {
        self.workerCount = max(1, workerCount)
        self.chunkSize = max(1, chunkSize)
    }
}

final class RuntimeParallelStreamBox {
    let elements: [Int]
    let workerCount: Int
    let chunkSize: Int

    init(elements: [Int], workerCount: Int, chunkSize: Int) {
        self.elements = elements
        self.workerCount = max(1, workerCount)
        self.chunkSize = max(1, chunkSize)
    }
}

private func runtimeParallelPoolBox(from rawValue: Int) -> RuntimeParallelPoolBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeParallelPoolBox.self)
}

private func runtimeParallelStreamBox(from rawValue: Int) -> RuntimeParallelStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeParallelStreamBox.self)
}

private func runtimeParallelSourceElements(from rawValue: Int) -> [Int]? {
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.elements
    }
    return nil
}

private func runtimeParallelInvalidHandlePanic(_ caller: StaticString, _ kind: StaticString) -> Never {
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid \(kind) handle")
}

private func runtimeParallelThrow(_ thrown: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown {
        outThrown.pointee = thrown
        return runtimeExceptionCaughtSentinel
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in parallel runtime lambda. outThrown was nil.")
}

private func runtimeParallelChunkPlan(count: Int, chunkSize: Int) -> [Range<Int>] {
    guard count > 0 else {
        return []
    }
    let normalizedChunkSize = max(1, chunkSize)
    var chunks: [Range<Int>] = []
    chunks.reserveCapacity((count + normalizedChunkSize - 1) / normalizedChunkSize)
    var start = 0
    while start < count {
        let end = min(count, start + normalizedChunkSize)
        chunks.append(start..<end)
        start = end
    }
    return chunks
}

private final class RuntimeParallelChunkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var nextChunkIndex = 0
    private var thrown = 0
    let chunks: [Range<Int>]

    init(chunks: [Range<Int>]) {
        self.chunks = chunks
    }

    func nextChunk() -> (index: Int, range: Range<Int>)? {
        lock.withLock {
            guard thrown == 0, nextChunkIndex < chunks.count else {
                return nil
            }
            let index = nextChunkIndex
            nextChunkIndex += 1
            return (index, chunks[index])
        }
    }

    func recordThrow(_ value: Int) {
        lock.withLock {
            if thrown == 0 {
                thrown = value
            }
        }
    }

    func hasThrown() -> Bool {
        lock.withLock { thrown != 0 }
    }

    func thrownValue() -> Int {
        lock.withLock { thrown }
    }
}

private func runtimeParallelMapSerial(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for element in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: element,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = runtimeParallelThrow(thrown, outThrown)
            return []
        }
        mapped.append(maybeUnbox(result))
    }
    return mapped
}

private func runtimeParallelForEachSerial(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    for element in elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: element,
            outThrown: &thrown
        )
        if thrown != 0 {
            return runtimeParallelThrow(thrown, outThrown)
        }
    }
    return 0
}

private func runtimeParallelReduceSerial(
    _ elements: [Int],
    initial: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    for element in elements {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: acc,
            rhs: element,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return runtimeParallelThrow(thrown, outThrown)
        }
    }
    return acc
}

private func runtimeParallelMapElements(
    _ elements: [Int],
    workerCount: Int,
    chunkSize: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    guard !elements.isEmpty else {
        return []
    }
    if workerCount <= 1 || elements.count == 1 {
        return runtimeParallelMapSerial(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    }

    let chunks = runtimeParallelChunkPlan(count: elements.count, chunkSize: chunkSize)
    guard chunks.count > 1 else {
        return runtimeParallelMapSerial(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    }

    let resultBuffer = UnsafeMutablePointer<Int>.allocate(capacity: elements.count)
    resultBuffer.initialize(repeating: 0, count: elements.count)
    defer {
        resultBuffer.deinitialize(count: elements.count)
        resultBuffer.deallocate()
    }
    let resultBox = UnsafeSendableBox(resultBuffer)

    let queue = RuntimeParallelChunkQueue(chunks: chunks)
    let group = DispatchGroup()
    let jobCount = min(workerCount, chunks.count)
    for _ in 0..<jobCount {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            while let job = queue.nextChunk() {
                if queue.hasThrown() {
                    return
                }
                for index in job.range {
                    if queue.hasThrown() {
                        return
                    }
                    var thrown = 0
                    let result = runtimeInvokeCollectionLambda1(
                        fnPtr: fnPtr,
                        closureRaw: closureRaw,
                        value: elements[index],
                        outThrown: &thrown
                    )
                    if thrown != 0 {
                        queue.recordThrow(thrown)
                        return
                    }
                    resultBox.value[index] = maybeUnbox(result)
                }
            }
        }
    }
    group.wait()

    let thrown = queue.thrownValue()
    if thrown != 0 {
        _ = runtimeParallelThrow(thrown, outThrown)
        return []
    }

    return Array(UnsafeBufferPointer(start: resultBuffer, count: elements.count))
}

private func runtimeParallelForEachElements(
    _ elements: [Int],
    workerCount: Int,
    chunkSize: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !elements.isEmpty else {
        return 0
    }
    if workerCount <= 1 || elements.count == 1 {
        return runtimeParallelForEachSerial(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    }

    let chunks = runtimeParallelChunkPlan(count: elements.count, chunkSize: chunkSize)
    guard chunks.count > 1 else {
        return runtimeParallelForEachSerial(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    }

    let queue = RuntimeParallelChunkQueue(chunks: chunks)
    let group = DispatchGroup()
    let jobCount = min(workerCount, chunks.count)
    for _ in 0..<jobCount {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            while let job = queue.nextChunk() {
                if queue.hasThrown() {
                    return
                }
                for index in job.range {
                    if queue.hasThrown() {
                        return
                    }
                    var thrown = 0
                    _ = runtimeInvokeCollectionLambda1(
                        fnPtr: fnPtr,
                        closureRaw: closureRaw,
                        value: elements[index],
                        outThrown: &thrown
                    )
                    if thrown != 0 {
                        queue.recordThrow(thrown)
                        return
                    }
                }
            }
        }
    }
    group.wait()

    let thrown = queue.thrownValue()
    if thrown != 0 {
        return runtimeParallelThrow(thrown, outThrown)
    }
    return 0
}

private func runtimeParallelReduceElements(
    _ elements: [Int],
    initial: Int,
    workerCount: Int,
    chunkSize: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !elements.isEmpty else {
        return initial
    }
    if workerCount <= 1 || elements.count == 1 {
        return runtimeParallelReduceSerial(
            elements,
            initial: initial,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
    }

    let chunks = runtimeParallelChunkPlan(count: elements.count, chunkSize: chunkSize)
    guard chunks.count > 1 else {
        return runtimeParallelReduceSerial(
            elements,
            initial: initial,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
    }

    let partials = UnsafeMutablePointer<Int>.allocate(capacity: chunks.count)
    partials.initialize(repeating: 0, count: chunks.count)
    defer {
        partials.deinitialize(count: chunks.count)
        partials.deallocate()
    }
    let partialsBox = UnsafeSendableBox(partials)

    let queue = RuntimeParallelChunkQueue(chunks: chunks)
    let group = DispatchGroup()
    let jobCount = min(workerCount, chunks.count)
    for _ in 0..<jobCount {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            while let job = queue.nextChunk() {
                if queue.hasThrown() {
                    return
                }
                guard let firstIndex = job.range.first else {
                    continue
                }
                // The first chunk starts from `initial` so that the caller-provided
                // initial value is correctly incorporated into the reduction.
                // Subsequent chunks start from their own first element and their
                // partial result is merged into `initial` during the final sequential
                // fold below.
                var acc: Int
                let remainingRange: Range<Int>
                if job.index == 0 {
                    // First chunk: start from `initial` and fold every element.
                    acc = initial
                    remainingRange = job.range
                } else {
                    // Other chunks: start from the chunk's first element.
                    acc = maybeUnbox(elements[firstIndex])
                    remainingRange = (firstIndex + 1)..<job.range.upperBound
                }
                for index in remainingRange {
                    if queue.hasThrown() {
                        return
                    }
                    var thrown = 0
                    acc = maybeUnbox(runtimeInvokeCollectionLambda2(
                        fnPtr: fnPtr,
                        closureRaw: closureRaw,
                        lhs: acc,
                        rhs: elements[index],
                        outThrown: &thrown
                    ))
                    if thrown != 0 {
                        queue.recordThrow(thrown)
                        return
                    }
                }
                partialsBox.value[job.index] = acc
            }
        }
    }
    group.wait()

    let thrown = queue.thrownValue()
    if thrown != 0 {
        return runtimeParallelThrow(thrown, outThrown)
    }

    // Chunk 0 already incorporates `initial`, so start the merge from its
    // partial rather than from `initial` again.
    var acc = partials[0]
    for index in 1..<chunks.count {
        let chunkPartial = partials[index]
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: acc,
            rhs: chunkPartial,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return runtimeParallelThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_parallel_pool_new")
public func kk_parallel_pool_new(_ workerCountRaw: Int) -> Int {
    registerRuntimeObject(RuntimeParallelPoolBox(workerCount: workerCountRaw))
}

@_cdecl("kk_parallel_stream_from_collection")
public func kk_parallel_stream_from_collection(_ collectionRaw: Int, _ poolRaw: Int) -> Int {
    guard let pool = runtimeParallelPoolBox(from: poolRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "pool")
    }
    guard let elements = runtimeParallelSourceElements(from: collectionRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "collection")
    }
    let chunkSize = max(1, min(pool.chunkSize, max(1, elements.count / max(1, pool.workerCount))))
    return registerRuntimeObject(
        RuntimeParallelStreamBox(
            elements: elements,
            workerCount: pool.workerCount,
            chunkSize: chunkSize
        )
    )
}

@_cdecl("kk_parallel_stream_to_list")
public func kk_parallel_stream_to_list(_ streamRaw: Int) -> Int {
    guard let stream = runtimeParallelStreamBox(from: streamRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "stream")
    }
    return registerRuntimeObject(RuntimeListBox(elements: stream.elements))
}

@_cdecl("kk_parallel_stream_map")
public func kk_parallel_stream_map(_ streamRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let stream = runtimeParallelStreamBox(from: streamRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "stream")
    }
    let mapped = runtimeParallelMapElements(
        stream.elements,
        workerCount: stream.workerCount,
        chunkSize: stream.chunkSize,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    return registerRuntimeObject(
        RuntimeParallelStreamBox(
            elements: mapped,
            workerCount: stream.workerCount,
            chunkSize: stream.chunkSize
        )
    )
}

@_cdecl("kk_parallel_stream_forEach")
public func kk_parallel_stream_forEach(_ streamRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let stream = runtimeParallelStreamBox(from: streamRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "stream")
    }
    return runtimeParallelForEachElements(
        stream.elements,
        workerCount: stream.workerCount,
        chunkSize: stream.chunkSize,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_parallel_stream_reduce")
public func kk_parallel_stream_reduce(_ streamRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let stream = runtimeParallelStreamBox(from: streamRaw) else {
        runtimeParallelInvalidHandlePanic(#function, "stream")
    }
    return runtimeParallelReduceElements(
        stream.elements,
        initial: initial,
        workerCount: stream.workerCount,
        chunkSize: stream.chunkSize,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}
