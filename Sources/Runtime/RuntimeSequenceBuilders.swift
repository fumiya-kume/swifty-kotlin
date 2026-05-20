import Foundation

/// `sequence { yield(...) }` / `iterator { yield(...) }` builders
/// and the `*To` destination-collection filter ops (STDLIB-331/553/564,
/// STDLIB-SEQ-021).
///
/// Split out from `RuntimeSequence.swift`.

// MARK: - Sequence Builder (sequence { yield(x) })

@_cdecl("kk_sequence_builder_create")
public func kk_sequence_builder_create() -> Int {
    let builder = RuntimeSequenceBuilderBox()
    return registerRuntimeObject(builder)
}

/// Resolve a raw handle to a RuntimeSequenceCoroutineBuilderProxy, or nil.
private func runtimeCoroutineBuilderProxy(from rawValue: Int) -> RuntimeSequenceCoroutineBuilderProxy? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceCoroutineBuilderProxy.self)
}

@_cdecl("kk_sequence_builder_yield")
public func kk_sequence_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    // STDLIB-563: If the handle is a coroutine builder proxy, yield lazily.
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        proxy.coroutine.yieldValue(value)
        return 0
    }
    if let builder = runtimeSequenceBuilderBox(from: builderRaw) {
        builder.elements.append(value)
        return 0
    }
    // STDLIB-331/564: yield() is shared across sequence/iterator builders.
    // When the builder handle is a RuntimeIteratorBuilderBox, delegate to
    // the continuation-based yield which suspends the producer thread.
    if runtimeIteratorBuilderBox(from: builderRaw) != nil {
        return kk_iterator_builder_yield(builderRaw, value)
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yield received invalid builder handle")
}

// MARK: - yieldAll(iterable) (STDLIB-553)

@_cdecl("kk_sequence_builder_yieldAll")
public func kk_sequence_builder_yieldAll(_ builderRaw: Int, _ collectionRaw: Int) -> Int {
    // STDLIB-563: If the handle is a coroutine builder proxy, yield each element lazily.
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        if let seq = runtimeSequenceBox(from: collectionRaw) {
            // Preserve outer lazy semantics: traverse nested sequence elements
            // on demand instead of materializing them first.
            runtimeTraverseSequence(seq, outThrown: nil) { elem in
                proxy.coroutine.yieldValue(elem)
                return true
            }
        } else if let list = runtimeListBox(from: collectionRaw) {
            for elem in list.elements {
                proxy.coroutine.yieldValue(elem)
            }
        } else if let array = runtimeArrayBox(from: collectionRaw) {
            for elem in array.elements {
                proxy.coroutine.yieldValue(elem)
            }
        } else if let set = runtimeSetBox(from: collectionRaw) {
            for elem in set.elements {
                proxy.coroutine.yieldValue(elem)
            }
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yieldAll received invalid collection handle (expected List, Array, Set, or Sequence)")
        }
        return 0
    }
    guard let builder = runtimeSequenceBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yieldAll received invalid builder handle")
    }
    // Accept List, Array, Set, or Sequence as the iterable source.
    if let elements = runtimeSequenceSourceElements(from: collectionRaw) {
        builder.elements.append(contentsOf: elements)
    } else if let set = runtimeSetBox(from: collectionRaw) {
        builder.elements.append(contentsOf: set.elements)
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yieldAll received invalid collection handle (expected List, Array, Set, or Sequence)")
    }
    return 0
}

@_cdecl("kk_sequence_builder_build")
public func kk_sequence_builder_build(_ fnPtr: Int, _ closureRaw: Int = 0) -> Int {
    // STDLIB-563: Use continuation-based lazy evaluation.
    // The coroutine runs the builder lambda on a background thread;
    // yield() suspends the producer and the elements are materialized
    // on demand when the sequence is consumed by a terminal operation.
    let coroutine = RuntimeSequenceCoroutine(fnPtr: fnPtr, closureRaw: closureRaw)
    let seq = RuntimeSequenceBox(steps: [.lazyBuilder(coroutine: coroutine)])
    return registerRuntimeObject(seq)
}

// MARK: - Iterator Builder (iterator { yield(x) }) (STDLIB-331/564)
// Continuation-based lazy iteration: the builder lambda runs on a background
// thread and suspends on each yield() call until the consumer calls next().

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}

@_cdecl("kk_iterator_builder_build")
public func kk_iterator_builder_build(_ fnPtr: Int) -> Int {
    let builder = RuntimeIteratorBuilderBox()
    let builderHandle = registerRuntimeObject(builder)

    // Spawn the producer on a background thread.  It blocks on producerGate
    // before invoking the lambda, so no work happens until the first
    // hasNext() call from the consumer.
    let thread = Thread {
        // Wait for the consumer to kick off the first advance.
        builder.producerGate.wait()
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: builderHandle, outThrown: &thrown)
        // Producer finished (or threw): mark done and wake the consumer.
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: iterator lambda threw an exception")
        }
        builder.state = .done
        builder.consumerGate.signal()
    }
    thread.qualityOfService = .userInitiated
    thread.start()

    return builderHandle
}

@_cdecl("kk_iterator_builder_yield")
public func kk_iterator_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    guard let builder = runtimeIteratorBuilderBox(from: builderRaw) else {
        // Fall back: the handle might be a RuntimeSequenceBuilderBox when yield
        // is shared between sequence/iterator builders in older lowering paths.
        if let seqBuilder = runtimeSequenceBuilderBox(from: builderRaw) {
            seqBuilder.elements.append(value)
            return 0
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_iterator_builder_yield received invalid builder handle")
    }
    // Store the value and suspend the producer until the consumer calls next().
    builder.yieldedValue = value
    builder.state = .hasValue
    builder.consumerGate.signal()   // wake consumer (hasNext is waiting)
    builder.producerGate.wait()     // block until consumer calls next hasNext()
    return 0
}

@_cdecl("kk_iterator_builder_hasNext")
public func kk_iterator_builder_hasNext(_ iterRaw: Int) -> Int {
    // Support both RuntimeIteratorBuilderBox and RuntimeListIteratorBox
    // for backwards compatibility with older lowering paths.
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        switch iter.state {
        case .hasValue:
            // Value already prefetched by a prior hasNext; still available.
            return 1
        case .done:
            return 0
        case .initial:
            // Advance the producer to get the first (or next) value.
            iter.producerGate.signal()  // let producer run
            iter.consumerGate.wait()    // wait for yield or completion
            return iter.state == .hasValue ? 1 : 0
        }
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        return iter.index < iter.elements.count ? 1 : 0
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_iterator_builder_hasNext received invalid iterator handle")
}

@_cdecl("kk_iterator_builder_next")
public func kk_iterator_builder_next(_ iterRaw: Int) -> Int {
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        // If hasNext was not called first, advance the producer now.
        if iter.state == .initial {
            iter.producerGate.signal()
            iter.consumerGate.wait()
        }
        guard iter.state == .hasValue else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.yieldedValue
        // Reset state to initial so the next hasNext() will advance the producer.
        iter.state = .initial
        return value
    }
    // Backwards compatibility: older lowering paths may pass a RuntimeListIteratorBox.
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        guard iter.index < iter.elements.count else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.elements[iter.index]
        iter.index += 1
        return value
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_iterator_builder_next received invalid iterator handle")
}

// MARK: - Sequence destination-collection filter operations (STDLIB-SEQ-021)

/// `filterTo`: Evaluate the sequence and append elements matching the predicate to the destination.
@_cdecl("kk_sequence_filterTo")
public func kk_sequence_filterTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        let predicate = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if runtimeCollectionBool(predicate) {
            runtimeAppendToMutableCollection(destRaw, elem)
        }
    }
    return destRaw
}

/// `filterNotTo`: Evaluate the sequence and append elements NOT matching the predicate to the destination.
@_cdecl("kk_sequence_filterNotTo")
public func kk_sequence_filterNotTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        let predicate = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if !runtimeCollectionBool(predicate) {
            runtimeAppendToMutableCollection(destRaw, elem)
        }
    }
    return destRaw
}

/// `mapTo`: Evaluate the sequence and append transformed elements to the destination.
@_cdecl("kk_sequence_mapTo")
public func kk_sequence_mapTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        runtimeAppendToMutableCollection(destRaw, maybeUnbox(result))
    }
    return destRaw
}

/// `mapNotNullTo`: Evaluate the sequence and append non-null transformed elements to the destination.
@_cdecl("kk_sequence_mapNotNullTo")
public func kk_sequence_mapNotNullTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if let normalized = runtimeMapNotNullResultValue(result) {
            runtimeAppendToMutableCollection(destRaw, normalized)
        }
    }
    return destRaw
}

/// `flatMapTo`: Evaluate the sequence, flatten transform results, and append them.
@_cdecl("kk_sequence_flatMapTo")
public func kk_sequence_flatMapTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        let flattened = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        guard let flattenedElements = runtimeIterableElements(from: flattened) else {
            invalidContainerPanic(#function, "iterable")
        }
        for flattenedElement in flattenedElements {
            runtimeAppendToMutableCollection(destRaw, flattenedElement)
        }
    }
    return destRaw
}

/// `filterIndexedTo`: Evaluate the sequence and append elements matching the indexed predicate to the destination.
@_cdecl("kk_sequence_filterIndexedTo")
public func kk_sequence_filterIndexedTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if maybeUnbox(result) != 0 {
            runtimeAppendToMutableCollection(destRaw, elem)
        }
    }
    return destRaw
}

/// `mapIndexedNotNullTo`: Evaluate the sequence, apply the indexed transform, and append non-null results.
@_cdecl("kk_sequence_mapIndexedNotNullTo")
public func kk_sequence_mapIndexedNotNullTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if result != runtimeNullSentinelInt {
            runtimeAppendToMutableCollection(destRaw, maybeUnbox(result))
        }
    }
    return destRaw
}

/// `flatMapIndexedTo`: Evaluate the sequence, flatten indexed transform results, and append them.
@_cdecl("kk_sequence_flatMapIndexedTo")
public func kk_sequence_flatMapIndexedTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let flattened = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        guard let flattenedElements = runtimeIterableElements(from: flattened) else {
            invalidContainerPanic(#function, "iterable")
        }
        for flattenedElement in flattenedElements {
            runtimeAppendToMutableCollection(destRaw, flattenedElement)
        }
    }
    return destRaw
}

/// `filterNotNullTo`: Evaluate the sequence and append non-null elements to the destination.
@_cdecl("kk_sequence_filterNotNullTo")
public func kk_sequence_filterNotNullTo(_ seqRaw: Int, _ destRaw: Int) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements where runtimeNormalizeNullableCollectionValue(elem) != nil {
        runtimeAppendToMutableCollection(destRaw, elem)
    }
    return destRaw
}

/// `filterIsInstanceTo`: Evaluate the sequence and append elements of the given runtime type to the destination.
@_cdecl("kk_sequence_filterIsInstanceTo")
public func kk_sequence_filterIsInstanceTo(_ seqRaw: Int, _ destRaw: Int, _ typeToken: Int) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements where kk_op_is(elem, typeToken) != 0 {
        runtimeAppendToMutableCollection(destRaw, elem)
    }
    return destRaw
}
