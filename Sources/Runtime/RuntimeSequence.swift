// MARK: - Sequence Functions (STDLIB-003)

func runtimeSequenceBox(from rawValue: Int) -> RuntimeSequenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBox.self)
}

func runtimeSequenceBuilderBox(from rawValue: Int) -> RuntimeSequenceBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBuilderBox.self)
}

private let runtimeSequenceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")
private let runtimeIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")

/// Runtime box that materializes a `RuntimeSequenceBox` on first use and then
/// serves elements one-by-one. This lets source-implemented `Sequence<T>` and
/// `Iterator<T>` wrappers chain with runtime-backed lazy sequences through the
/// normal `Sequence`/`Iterator` itable dispatch path.
final class RuntimeSequenceIteratorBox {
    let seq: RuntimeSequenceBox
    fileprivate var elements: [Int] = []
    fileprivate var index: Int = 0
    fileprivate var materialized: Bool = false

    init(seq: RuntimeSequenceBox) {
        self.seq = seq
    }

    func materialize(outThrown: UnsafeMutablePointer<Int>?) {
        guard !materialized else { return }
        elements = evaluateSequence(seq, outThrown: outThrown, markConsumption: true)
        materialized = true
    }
}

func runtimeSequenceIteratorBox(from rawValue: Int) -> RuntimeSequenceIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceIteratorBox.self)
}


/// Dispatches an `Iterator` method on a source-implemented `Iterator` object by
/// looking up the `kotlin.collections.Iterator` itable dynamically.
private func runtimeIteratorMethodCall(
    _ iterRaw: Int,
    methodSlot: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fnPtr = kk_itable_lookup_dynamic(iterRaw, Int(runtimeIteratorInterfaceTypeID), methodSlot)
    guard fnPtr != 0 else {
        return 0
    }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return fn(iterRaw, outThrown)
}

/// Iterates a source-implemented `Sequence` object (created by Kotlin `object`
/// expressions implementing `kotlin.sequences.Sequence`) by dispatching through
/// the Sequence itable to obtain an `Iterator`, then driving that iterator with
/// the `Iterator` itable directly so thrown exceptions can be propagated.
/// Returns `true` if `rawValue` is a source `Sequence` and was iterated (or an
/// exception was recorded in `outThrown`). Returns `false` if it is not a source
/// `Sequence` so callers can fall back to runtime box handling.
private func runtimeTraverseSourceSequenceObject(
    _ rawValue: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    iterator: ((Int) -> Void)? = nil,
    yield: (Int) -> Bool
) -> Bool {
    let iteratorFnPtr = kk_itable_lookup_dynamic(rawValue, Int(runtimeSequenceInterfaceTypeID), 0)
    guard iteratorFnPtr != 0 else {
        return false
    }
    let iteratorFn = unsafeBitCast(
        iteratorFnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown: Int = 0
    let iterRaw = iteratorFn(rawValue, &thrown)
    iterator?(iterRaw)
    if thrown != 0 {
        if let outThrown {
            outThrown.pointee = thrown
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence iterator() threw an exception")
        }
        return true
    }
    while true {
        var hasNextThrown: Int = 0
        let hasNext = runtimeIteratorMethodCall(iterRaw, methodSlot: 0, outThrown: &hasNextThrown)
        if hasNextThrown != 0 {
            if let outThrown {
                outThrown.pointee = hasNextThrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence Iterator.hasNext() threw an exception")
            }
            return true
        }
        if hasNext == 0 { break }
        var nextThrown: Int = 0
        let element = runtimeIteratorMethodCall(iterRaw, methodSlot: 1, outThrown: &nextThrown)
        if nextThrown != 0 {
            if let outThrown {
                outThrown.pointee = nextThrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence Iterator.next() threw an exception")
            }
            return true
        }
        if !yield(element) { break }
    }
    return true
}

private func runtimeObjectBox(from rawValue: Int) -> RuntimeObjectBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeObjectBox.self)
}

func runtimeArrayBoxExcludingObjects(from rawValue: Int) -> RuntimeArrayBox? {
    guard let array = runtimeArrayBox(from: rawValue),
          type(of: array) == RuntimeArrayBox.self
    else {
        return nil
    }
    return array
}

func runtimeSequenceSourceElements(from rawValue: Int) -> [Int]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        return evaluateSequence(seq)
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.elements
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.elements
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var elements: [Int] = []
        if runtimeTraverseSourceSequenceObject(rawValue, outThrown: nil, yield: { elem in
            elements.append(elem)
            return true
        }) {
            return elements
        }
        return nil
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.elements
    }
    return nil
}

func runtimeSequenceSourceValues(from rawValue: Int) -> [RuntimeValue]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        return evaluateSequenceValues(seq)
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.values
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.values
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var values: [RuntimeValue] = []
        var iteratorRaw = 0
        if runtimeTraverseSourceSequenceObject(
            rawValue,
            outThrown: nil,
            iterator: { iteratorRaw = $0 },
            yield: { elem in
                values.append(runtimeSourceIteratorValue(elem, iteratorRaw: iteratorRaw))
                return true
            }
        ) {
            return values
        }
        return nil
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.values
    }
    return nil
}

private func runtimeSequenceSourceElementsOrThrow(
    from rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let elements = evaluateSequence(seq, outThrown: outThrown)
        if let outThrown, outThrown.pointee != 0 {
            return nil
        }
        return elements
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.elements
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.elements
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var elements: [Int] = []
        if runtimeTraverseSourceSequenceObject(rawValue, outThrown: outThrown, yield: { elem in
            elements.append(elem)
            return true
        }) {
            return elements
        }
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

private func runtimeSequenceSourceValuesOrThrow(
    from rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> [RuntimeValue]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let values = evaluateSequenceValues(seq, outThrown: outThrown)
        if let outThrown, outThrown.pointee != 0 {
            return nil
        }
        return values
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.values
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.values
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var values: [RuntimeValue] = []
        var iteratorRaw = 0
        if runtimeTraverseSourceSequenceObject(
            rawValue,
            outThrown: outThrown,
            iterator: { iteratorRaw = $0 },
            yield: { elem in
                values.append(runtimeSourceIteratorValue(elem, iteratorRaw: iteratorRaw))
                return true
            }
        ) {
            return values
        }
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.values
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

/// Fail-fast variant that panics on invalid handles instead of returning nil.
/// Use this instead of `runtimeSequenceSourceElements(from:) ?? []` to distinguish
/// invalid handles from legitimately empty sequences.
func runtimeSequenceSourceElementsOrPanic(from rawValue: Int, caller: StaticString) -> [Int] {
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

func runtimeSequenceSourceValuesOrPanic(from rawValue: Int, caller: StaticString) -> [RuntimeValue] {
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

final class SequenceTraversalState {
    var stop = false
    var stopByDownstream = false
    var limitReached = false
    var takeCounts: [Int: Int] = [:]
    var dropCounts: [Int: Int] = [:]
    var distinctSeen: [Int: [Int]] = [:]
    var distinctBySeen: [Int: [Int]] = [:]
    var zipIndices: [Int: Int] = [:]
    var chunkedBuffers: [Int: [Int]] = [:]
}

// MARK: - Shared constants

/// Hard limit for generator-backed sequence traversal.
///
/// Generator sequences (created via `generateSequence`) are potentially infinite,
/// so we cap evaluation at this many elements to prevent unbounded computation.
/// Terminal operations like `last()` and `count()` that must consume the entire
/// sequence will report a `kSequenceGeneratorLimitReached` error via `outThrown`
/// when this limit is hit.
///
/// This limit only applies to generator steps; source-backed sequences (from lists,
/// arrays, or `sequenceOf`) are not affected.
private let kSequenceGeneratorHardLimit = 100_000

/// Error message for `first()` / `last()` on an empty sequence.
let kEmptySequenceNoSuchElement = "Sequence is empty."
private let kSequenceNoNonNullTransformResult = "No element of the sequence was transformed to a non-null value."
/// Error message for `reduce` on an empty sequence.
let kEmptySequenceCannotReduce = "Empty sequence can't be reduced."
/// Error message when a generator sequence exceeds the traversal hard limit.
let kSequenceGeneratorLimitReached = "IllegalStateException: Sequence generator exceeded traversal hard limit (\(kSequenceGeneratorHardLimit))."
private let kSequenceConstrainedOnceConsumed = "This sequence can be consumed only once."
/// Error message for `Sequence.requireNoNulls()` when a null element is encountered.
private let kSequenceRequireNoNullsFoundNull = "null element found in sequence."

private func runtimeSequenceBeginTraversal(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>?
) -> Bool {
    guard let state = seq.constrainOnceState else {
        return true
    }
    if state.consumed {
        if let outThrown {
            outThrown.pointee = runtimeAllocateIllegalStateException(message: kSequenceConstrainedOnceConsumed)
            return false
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: IllegalStateException: \(kSequenceConstrainedOnceConsumed)")
    }
    state.consumed = true
    return true
}

private func runtimeSequenceTransformElement(
    _ element: Int,
    steps: [SequenceStepKind],
    stepIndex: Int,
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) {
    if state.stop { return }
    if stepIndex >= steps.count {
        state.stop = !yield(element)
        state.stopByDownstream = state.stop
        return
    }

    switch steps[stepIndex] {
    case let .mapStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let mapped = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Keep the transform's already-boxed result as-is.
        runtimeSequenceTransformElement(
            mapped,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .filterStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if runtimeCollectionBool(predicateResult) {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .filterNotStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if !runtimeCollectionBool(predicateResult) {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .takeStep(count):
        let emitted = state.takeCounts[stepIndex, default: 0]
        if emitted >= count {
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: { value in
                let currentCount = state.takeCounts[stepIndex, default: 0]
                if currentCount >= count {
                    state.stop = true
                    return false
                }
                state.takeCounts[stepIndex] = currentCount + 1
                let shouldContinue = yield(value)
                if state.takeCounts[stepIndex, default: 0] >= count {
                    state.stop = true
                }
                return shouldContinue && !state.stop
            }
        )
    case let .dropStep(count):
        let skipped = state.dropCounts[stepIndex, default: 0]
        if skipped < count {
            state.dropCounts[stepIndex] = skipped + 1
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case .distinctStep:
        var seen = state.distinctSeen[stepIndex] ?? []
        if seen.contains(where: { runtimeValuesEqual($0, element) }) {
            return
        }
        seen.append(element)
        state.distinctSeen[stepIndex] = seen
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .distinctByStep(fnPtr, closureRaw):
        let selector = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let key = maybeUnbox(selector(closureRaw, element, &thrown))
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        var seen = state.distinctBySeen[stepIndex] ?? []
        if seen.contains(where: { runtimeValuesEqual($0, key) }) {
            return
        }
        seen.append(key)
        state.distinctBySeen[stepIndex] = seen
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .zipStep(otherElements):
        let index = state.zipIndices[stepIndex, default: 0]
        if index >= otherElements.count {
            state.stop = true
            return
        }
        state.zipIndices[stepIndex] = index + 1
        runtimeSequenceTransformElement(
            kk_pair_new(element, otherElements[index]),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .takeWhileStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if maybeUnbox(predicateResult) != 0 {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        } else {
            state.stop = true
        }
    case let .dropWhileStep(fnPtr, closureRaw):
        let dropping = state.dropCounts[stepIndex, default: 1] != 0
        if dropping {
            let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var thrown = 0
            let predicateResult = predicate(closureRaw, element, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                state.stop = true
                return
            }
            if maybeUnbox(predicateResult) == 0 {
                state.dropCounts[stepIndex] = 0
                runtimeSequenceTransformElement(
                    element,
                    steps: steps,
                    stepIndex: stepIndex + 1,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
        } else {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .onEachStep(fnPtr, closureRaw):
        let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        _ = action(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .onEachIndexedStep(fnPtr, closureRaw):
        let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        _ = action(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapNotNullStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let mapped = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if let unboxed = runtimeMapNotNullResultValue(mapped) {
            runtimeSequenceTransformElement(
                unboxed,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .filterNotNullStep:
        if runtimeNormalizeNullableCollectionValue(element) != nil {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .requireNoNullsStep:
        if runtimeNormalizeNullableCollectionValue(element) == nil {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: kSequenceRequireNoNullsFoundNull)
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let mapped = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Keep the transform's already-boxed result as-is.
        runtimeSequenceTransformElement(
            mapped,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapIndexedNotNullStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let mapped = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if let unboxed = runtimeMapNotNullResultValue(mapped) {
            runtimeSequenceTransformElement(
                unboxed,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .filterIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let keep = lambda(closureRaw, index, element, &thrown) != 0
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if keep {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .withIndexStep:
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        runtimeSequenceTransformElement(
            runtimeIndexedValueNew(index: index, value: element),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .flatMapStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let subRaw = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Handle the sub-collection/sequence, including source-implemented Sequences.
        guard let subElements = runtimeSequenceSourceElementsOrThrow(from: subRaw, caller: #function, outThrown: outThrown) else {
            return
        }
        for subElem in subElements {
            runtimeSequenceTransformElement(
                subElem,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
            if state.stop { return }
        }
    case let .flatMapIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let subRaw = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Handle the sub-collection/sequence, including source-implemented Sequences.
        guard let subElements = runtimeSequenceSourceElementsOrThrow(from: subRaw, caller: #function, outThrown: outThrown) else {
            return
        }
        for subElem in subElements {
            runtimeSequenceTransformElement(
                subElem,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
            if state.stop { return }
        }
    case .shuffledStep:
        return
    case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .chunkedTransformStep(size, fnPtr, closureRaw):
        let chunkSize = max(1, size)
        var buffer = state.chunkedBuffers[stepIndex, default: []]
        buffer.append(element)
        if buffer.count < chunkSize {
            state.chunkedBuffers[stepIndex] = buffer
            return
        }

        state.chunkedBuffers[stepIndex] = []
        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            maybeUnbox(transformed),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
}

private func runtimeSequenceFlushChunkedTransforms(
    _ steps: [SequenceStepKind],
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) {
    for stepIndex in steps.indices {
        if state.stopByDownstream { return }
        guard case let .chunkedTransformStep(_, fnPtr, closureRaw) = steps[stepIndex] else {
            continue
        }
        guard let buffer = state.chunkedBuffers.removeValue(forKey: stepIndex), !buffer.isEmpty else { continue }

        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            maybeUnbox(transformed),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
}

/// Traverse a sequence box lazily, allowing the caller to supply its own
/// `SequenceTraversalState` so that `limitReached` can be inspected afterwards.
func runtimeTraverseSequenceWithState(
    _ seq: RuntimeSequenceBox,
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    markConsumption: Bool = true,
    yield: @escaping (Int) -> Bool
) {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return
    }

    if let shuffledIndex = seq.steps.firstIndex(where: { step in
        if case .shuffledStep = step { return true }
        return false
    }) {
        let prefix = Array(seq.steps[..<shuffledIndex])
        let rest: [SequenceStepKind] =
            (shuffledIndex + 1) < seq.steps.endIndex
            ? Array(seq.steps[(shuffledIndex + 1)...])
            : []
        guard case let .shuffledStep(randomOpt) = seq.steps[shuffledIndex] else {
            return
        }
        let prefixBox = RuntimeSequenceBox(steps: prefix)
        var materialized = evaluateSequence(prefixBox)
        materialized = runtimeShuffleElementHandles(materialized, randomRaw: randomOpt)
        var newSteps: [SequenceStepKind] = [.source(elements: materialized)]
        newSteps.append(contentsOf: rest)
        return runtimeTraverseSequenceWithState(
            RuntimeSequenceBox(steps: newSteps),
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
    let transformSteps = seq.steps.filter {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
            false
        default:
            true
        }
    }
    let emit: (Int) -> Void = { element in
        runtimeSequenceTransformElement(
            element,
            steps: transformSteps,
            stepIndex: 0,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }

    for step in seq.steps {
        switch step {
        case let .source(sourceElements), let .builder(sourceElements):
            for element in sourceElements {
                emit(element)
                if state.stop { break }
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .valueSource(sourceValues):
            for value in sourceValues {
                emit(value.legacyRawValue)
                if state.stop { break }
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .lazyBuilder(coroutine):
            // STDLIB-563: Lazy element-by-element iteration.
            // Request one element at a time from the coroutine so that
            // short-circuiting operations (take, first, etc.) only
            // compute the elements they actually need.
            coroutine.resetIteration()
            var done = false
            while true {
                if state.stop || done { break }
                let next = coroutine.nextElement()
                switch next {
                case let .value(element):
                    emit(element)
                case .done:
                    done = true
                }
                if state.stop { break }
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .stringSource(source):
            // Lazy: iterate string characters on demand without pre-materializing.
            // NOTE: Kotlin Char is a UTF-16 code unit (16-bit). Iterating unicodeScalars
            // produces values > 0xFFFF for supplementary characters (e.g. emoji),
            // which do not fit in a Kotlin Char. We iterate utf16 code units instead to
            // match Kotlin's Char semantics correctly. Supplementary characters are split
            // into two surrogate code units, which is the expected Kotlin behaviour.
            for codeUnit in source.utf16 {
                emit(Int(codeUnit))
                if state.stop { break }
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .generator(seed, fnPtr, closureRaw):
            let nextFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var current = seed
            emit(current)
            if state.stop { return }

            var generatedCount = 1
            while generatedCount < kSequenceGeneratorHardLimit, !state.stop {
                var thrown = 0
                let next = nextFn(closureRaw, current, &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    state.stop = true
                    return
                }
                // KSP-500: don't unbox here. The compiler wraps nextFunction in
                // a boxing adapter (CallLowerer+ClosureAdapters.swift's
                // makeGenerateSequenceBoxingAdapter) whenever the element type
                // is a primitive, so `next` already comes back boxed — the
                // element must stay boxed to be distinguishable by later
                // `is`/filterIsInstance checks on a Sequence<Any>. The callee
                // unboxes `current` itself on entry (kk_unbox_int et al. are
                // idempotent), so feeding a boxed value back in is safe.
                if next == runtimeNullSentinelInt { break }
                emit(next)
                current = next
                generatedCount += 1
            }
            if generatedCount >= kSequenceGeneratorHardLimit, !state.stop {
                state.limitReached = true
                return
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .nullableGenerator(fnPtr, closureRaw):
            // STDLIB-SEQ-002: 1-arg form — calls no-arg nextFunction repeatedly until null.
            let noArgFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var generatedCount = 0
            while generatedCount < kSequenceGeneratorHardLimit, !state.stop {
                var thrown = 0
                let next = noArgFn(closureRaw, &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    state.stop = true
                    return
                }
                // KSP-500: see the .generator case above — the compiler's
                // boxing adapter already boxed this closure's return value, so
                // don't strip that here.
                if next == runtimeNullSentinelInt { break }
                emit(next)
                generatedCount += 1
            }
            if generatedCount >= kSequenceGeneratorHardLimit, !state.stop {
                state.limitReached = true
                return
            }
            if !state.limitReached, (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case .mapStep, .filterStep, .filterNotStep, .takeStep, .dropStep, .distinctStep,
             .distinctByStep, .zipStep, .takeWhileStep, .dropWhileStep, .onEachStep,
             .onEachIndexedStep, .mapNotNullStep, .filterNotNullStep,
             .filterIndexedStep, .requireNoNullsStep, .mapIndexedStep, .mapIndexedNotNullStep, .withIndexStep, .flatMapStep,
             .flatMapIndexedStep, .chunkedTransformStep, .shuffledStep:
            continue
        }
    }
}

/// Convenience wrapper that creates its own `SequenceTraversalState`.
func runtimeTraverseSequence(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>?,
    markConsumption: Bool = true,
    yield: @escaping (Int) -> Bool
) {
    let state = SequenceTraversalState()
    runtimeTraverseSequenceWithState(
        seq,
        state: state,
        outThrown: outThrown,
        markConsumption: markConsumption,
        yield: yield
    )
}

@discardableResult
func runtimeTraverseSequenceSource(
    _ rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) -> SequenceTraversalState? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let state = SequenceTraversalState()
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: yield)
        return state
    }
    if runtimeTraverseSourceSequenceObject(rawValue, outThrown: outThrown, yield: yield) {
        return nil
    }
    for elem in runtimeSequenceSourceElementsOrPanic(from: rawValue, caller: caller) {
        // swiftlint:disable:next for_where
        if !yield(elem) { break }
    }
    return nil
}

/// Extracts source elements from a sequence step, if applicable.
/// `.stringSource` is NOT extracted here — it is handled lazily in evaluateSequence
/// and runtimeTraverseSequence to avoid eager materialization.
private func extractSourceElements(from step: SequenceStepKind) -> [Int]? {
    switch step {
    case let .source(sourceElements):
        return sourceElements
    case let .valueSource(sourceValues):
        return sourceValues.map(\.legacyRawValue)
    case let .builder(builderElements):
        return builderElements
    case let .lazyBuilder(coroutine):
        // STDLIB-563: Materialize the lazy coroutine into an element array.
        return coroutine.materializeAll()
    default:
        return nil
    }
}

/// Applies a takeWhile transformation: takes elements while predicate returns true.
private func applyTakeWhileStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for elem in elements {
        var thrown = 0
        let predicateResult = predicate(closureRaw, elem, &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if maybeUnbox(predicateResult) == 0 {
            break
        }
        result.append(elem)
    }
    return result
}

/// Applies a dropWhile transformation: drops elements while predicate returns true, then takes the rest.
private func applyDropWhileStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var dropping = true
    var result: [Int] = []
    for elem in elements {
        if dropping {
            var thrown = 0
            let predicateResult = predicate(closureRaw, elem, &thrown)
            if thrown != 0 {
                if let outThrown = outThrown {
                    outThrown.pointee = thrown
                }
                return []
            }
            if maybeUnbox(predicateResult) == 0 {
                dropping = false
                result.append(elem)
            }
        } else {
            result.append(elem)
        }
    }
    return result
}

/// Applies a requireNoNulls transformation: fails on the first null element.
private func applyRequireNoNullsStep(_ elements: [Int], outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    for elem in elements where runtimeNormalizeNullableCollectionValue(elem) == nil {
        let thrown = runtimeAllocateIllegalArgumentException(message: kSequenceRequireNoNullsFoundNull)
        if let outThrown {
            outThrown.pointee = thrown
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Sequence.requireNoNulls encountered null but no outThrown was available.")
        }
        return []
    }
    return elements
}

private func applyOnEachIndexedStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
    }
    return elements
}

/// Applies a withIndex transformation: creates pairs of (index, element).
private func applyWithIndexStep(_ elements: [Int]) -> [Int] {
    var pairs: [Int] = []
    pairs.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        pairs.append(runtimeIndexedValueNew(index: idx, value: elem))
    }
    return pairs
}

/// Applies a flatMap transformation: maps each element to a collection and flattens the result.
private func applyFlatMapStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var result: [Int] = []
    for elem in elements {
        var thrown = 0
        let subRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if let subElements = runtimeCollectionElements(from: subRaw) {
            result.append(contentsOf: subElements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq, outThrown: outThrown))
            if let outThrown, outThrown.pointee != 0 { return [] }
        }
    }
    return result
}

/// Applies a flatMapIndexed transformation: maps each indexed element to a collection or sequence and flattens it.
private func applyFlatMapIndexedStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var result: [Int] = []
    for (index, elem) in elements.enumerated() {
        var thrown = 0
        let subRaw = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if let subElements = runtimeCollectionElements(from: subRaw) {
            result.append(contentsOf: subElements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq, outThrown: outThrown))
            if let outThrown, outThrown.pointee != 0 { return [] }
        }
    }
    return result
}

/// Applies a chunked transform step eagerly by grouping elements, applying the transform,
/// and including any trailing partial chunk.
private func applyChunkedTransformStep(
    _ elements: [Int],
    size: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    guard !elements.isEmpty else { return [] }

    let chunkSize = max(1, size)
    let expectedChunkCount = (elements.count + chunkSize - 1) / chunkSize
    var result: [Int] = []
    result.reserveCapacity(expectedChunkCount)

    var buffer: [Int] = []
    buffer.reserveCapacity(chunkSize)

    for element in elements {
        buffer.append(element)
        if buffer.count != chunkSize { continue }

        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        result.append(maybeUnbox(transformed))
        buffer = []
    }

    if !buffer.isEmpty {
        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        result.append(maybeUnbox(transformed))
    }

    return result
}

/// Shuffles a snapshot of element handles. `randomRaw == nil` uses the same
/// default behaviour as [Int].`shuffled()`.
private func runtimeShuffleElementHandles(_ elements: [Int], randomRaw: Int?) -> [Int] {
    guard elements.count > 1 else { return elements }
    if let randomRaw {
        var out = elements
        for i in stride(from: out.count - 1, through: 1, by: -1) {
            let j = runtimeRandomNextIntBelow(randomRaw, i + 1)
            out.swapAt(i, j)
        }
        return out
    }
    return elements.shuffled()
}

/// Evaluates the lazy sequence chain and returns the materialized elements.
/// This is the core of lazy semantics: steps are only executed here.
private func evaluateSequence(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    markConsumption: Bool = true
) -> [Int] {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return []
    }

    let hasTransformSteps = seq.steps.contains {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
            return false
        default:
            return true
        }
    }
    // Preserve Kotlin sequence laziness even for source-backed sequences.
    // Without the traversal path, intermediate steps like onEachIndexed would
    // eagerly touch every source element before downstream take()/first()
    // short-circuits, which is observably incorrect.
    if hasTransformSteps {
        var result: [Int] = []
        runtimeTraverseSequence(seq, outThrown: outThrown, markConsumption: false) { elem in
            result.append(elem)
            return true
        }
        if let outThrown, outThrown.pointee != 0 { return [] }
        return result
    }

    // Find the source elements
    var elements: [Int] = []
    for step in seq.steps {
        if let source = extractSourceElements(from: step) {
            elements = source
            break
        }
        if case let .valueSource(values) = step {
            elements = values.map(\.legacyRawValue)
            break
        }
        if case let .stringSource(source) = step {
            // Materialize string characters at terminal evaluation only.
            // Use utf16 code units (not unicodeScalars) so that supplementary characters
            // (emoji, etc. with scalar value > 0xFFFF) are represented as surrogate pairs,
            // matching Kotlin's UTF-16 Char semantics.
            elements = source.utf16.map { Int($0) }
            break
        }
        if case let .generator(seed, fnPtr, closureRaw) = step {
            // KSP-500: don't unbox `next` — see runtimeTraverseSequenceWithState's
            // .generator case for why the closure's boxed return must survive.
            var current = seed
            var generated: [Int] = [current]
            while generated.count < kSequenceGeneratorHardLimit {
                var thrown = 0
                let next = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: current, outThrown: &thrown)
                if thrown != 0 { break }
                if next == runtimeNullSentinelInt { break }
                generated.append(next)
                current = next
            }
            elements = generated
            break
        }
        if case let .nullableGenerator(fnPtr, closureRaw) = step {
            // STDLIB-SEQ-002: 1-arg form — no seed, call no-arg function until null.
            // KSP-500: don't unbox `next` — see runtimeTraverseSequenceWithState's
            // .nullableGenerator case for why the closure's boxed return must survive.
            let noArgFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var generated: [Int] = []
            while generated.count < kSequenceGeneratorHardLimit {
                var thrown = 0
                let next = noArgFn(closureRaw, &thrown)
                if thrown != 0 { break }
                if next == runtimeNullSentinelInt { break }
                generated.append(next)
            }
            elements = generated
            break
        }
    }

    // Apply transformation steps in order
    for step in seq.steps {
        switch step {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
            break
        case let .mapStep(fnPtr, closureRaw):
            elements = applyMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .filterStep(fnPtr, closureRaw):
            elements = applyFilterStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .filterNotStep(fnPtr, closureRaw):
            elements = applyFilterNotStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .takeStep(count):
            if count >= 0, count < elements.count {
                elements = Array(elements.prefix(count))
            }
        case let .dropStep(count):
            if count >= 0, count < elements.count {
                elements = Array(elements.dropFirst(count))
            } else if count >= elements.count {
                elements = []
            }
        case .distinctStep:
            var seen = Set<RuntimeElementKey>()
            seen.reserveCapacity(elements.count)
            elements = elements.filter { seen.insert(RuntimeElementKey(value: $0)).inserted }
        case let .distinctByStep(fnPtr, closureRaw):
            let selector = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var seen = Set<RuntimeElementKey>()
            seen.reserveCapacity(elements.count)
            var distinct: [Int] = []
            for elem in elements {
                var thrown = 0
                let key = maybeUnbox(selector(closureRaw, elem, &thrown))
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    return []
                }
                if seen.insert(RuntimeElementKey(value: key)).inserted {
                    distinct.append(elem)
                }
            }
            elements = distinct
        case let .zipStep(otherElements):
            let minCount = min(elements.count, otherElements.count)
            var zipped: [Int] = []
            zipped.reserveCapacity(minCount)
            for i in 0 ..< minCount {
                zipped.append(kk_pair_new(elements[i], otherElements[i]))
            }
            elements = zipped
        case let .takeWhileStep(fnPtr, closureRaw):
            elements = applyTakeWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .dropWhileStep(fnPtr, closureRaw):
            elements = applyDropWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .onEachStep(fnPtr, closureRaw):
            let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            for elem in elements {
                var thrown = 0
                _ = action(closureRaw, elem, &thrown)
                if thrown != 0 {
                    if let outThrown {
                        outThrown.pointee = thrown
                        return []
                    }
                    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence onEach lambda threw but no outThrown available")
                }
            }
        case let .onEachIndexedStep(fnPtr, closureRaw):
            elements = applyOnEachIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .mapNotNullStep(fnPtr, closureRaw):
            elements = applyMapNotNullStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case .filterNotNullStep:
            elements = applyFilterNotNullStep(elements)
        case .requireNoNullsStep:
            elements = applyRequireNoNullsStep(elements, outThrown: outThrown)
        case let .mapIndexedStep(fnPtr, closureRaw):
            elements = applyMapIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .mapIndexedNotNullStep(fnPtr, closureRaw):
            elements = applyMapIndexedNotNullStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .filterIndexedStep(fnPtr, closureRaw):
            elements = applyFilterIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case .withIndexStep:
            elements = applyWithIndexStep(elements)
        case let .flatMapStep(fnPtr, closureRaw):
            elements = applyFlatMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .flatMapIndexedStep(fnPtr, closureRaw):
            elements = applyFlatMapIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .chunkedTransformStep(size, fnPtr, closureRaw):
            elements = applyChunkedTransformStep(elements, size: size, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .shuffledStep(randomOpt):
            elements = runtimeShuffleElementHandles(elements, randomRaw: randomOpt)
        }
        if let outThrown, outThrown.pointee != 0 { return [] }
    }

    return elements
}

private func evaluateSequenceValues(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    markConsumption: Bool = true
) -> [RuntimeValue] {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return []
    }

    let hasTransformSteps = seq.steps.contains {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
            return false
        default:
            return true
        }
    }
    if hasTransformSteps {
        return evaluateSequence(seq, outThrown: outThrown, markConsumption: false).map { RuntimeValue(raw: $0) }
    }

    for step in seq.steps {
        switch step {
        case let .valueSource(values):
            return values
        case let .stringSource(source):
            return source.utf16.map { RuntimeValue(charScalar: Int($0)) }
        case .generator, .nullableGenerator:
            return evaluateSequence(seq, outThrown: outThrown, markConsumption: false).map { RuntimeValue(raw: $0) }
        default:
            if let source = extractSourceElements(from: step) {
                return source.map { RuntimeValue(raw: $0) }
            }
        }
    }
    return []
}

// maybeUnbox() is defined in RuntimeCollectionHelpers.swift

// MARK: - Sequence Factory Functions

@_cdecl("kk_sequence_from_list")
public func kk_sequence_from_list(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_from_list received invalid list handle")
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: list.elements)])
    return registerRuntimeObject(seq)
}

// MARK: - emptySequence (STDLIB-277)

@_cdecl("__kk_empty_sequence")
public func __kk_empty_sequence() -> Int {
    let seq = RuntimeSequenceBox(steps: [.source(elements: [])])
    return registerRuntimeObject(seq)
}

// MARK: - Sequence.ifEmpty (STDLIB-277)

@_cdecl("kk_sequence_ifEmpty")
public func kk_sequence_ifEmpty(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
    if elements.isEmpty {
        var thrown = 0
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let result = lambda(closureRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        return result
    }
    return seqRaw
}

@_cdecl("__kk_sequence_of")
public func __kk_sequence_of(_ arrayRaw: Int) -> Int {
    let elements: [Int]
    if let arr = runtimeArrayBox(from: arrayRaw) {
        elements = Array(arr.elements)
    } else if let list = runtimeListBox(from: arrayRaw) {
        // Source-backed vararg functions are normalized to a list at their
        // public call boundary; accept that representation while preserving
        // the packed-array ABI used by direct bridge calls.
        elements = Array(list.elements)
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_of expected RuntimeArrayBox or RuntimeListBox")
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: elements)])
    return registerRuntimeObject(seq)
}

/// Wrap a single element value in a one-element sequence.
/// Used by the compiler to ensure `Sequence + element` always passes a
/// collection handle to `kk_sequence_plus`, avoiding the ambiguity where
/// a raw element value could collide with a live runtime object handle.
@_cdecl("kk_sequence_of_single")
public func kk_sequence_of_single(_ element: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.source(elements: [element])])
    return registerRuntimeObject(seq)
}

@_cdecl("__kk_sequence_generate")
public func __kk_sequence_generate(_ seed: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.generator(seed: seed, fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
}

/// STDLIB-SEQ-002: 1-arg form `generateSequence(nextFunction: () -> T?)`.
/// Calls `nextFunction` (no-arg closure) repeatedly; stops when null is returned.
@_cdecl("__kk_sequence_generate_noarg")
public func __kk_sequence_generate_noarg(_ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.nullableGenerator(fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_constrainOnce")
public func kk_sequence_constrainOnce(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let constrained = RuntimeSequenceBox(
            steps: [.source(elements: sourceElements)],
            constrainOnceState: RuntimeSequenceConstrainOnceState()
        )
        return registerRuntimeObject(constrained)
    }
    let constrained = RuntimeSequenceBox(
        steps: seq.steps,
        constrainOnceState: seq.constrainOnceState ?? RuntimeSequenceConstrainOnceState()
    )
    return registerRuntimeObject(constrained)
}

// MARK: - Sequence Intermediate Operations (Lazy)

@_cdecl("kk_sequence_map")
public func kk_sequence_map(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let mapped = applyMapStep(sourceElements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        return registerRuntimeObject(RuntimeListBox(elements: mapped))
    }
    var newSteps = seq.steps
    newSteps.append(.mapStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_filter")
public func kk_sequence_filter(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let filtered = applyFilterStep(sourceElements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        return registerRuntimeObject(RuntimeListBox(elements: filtered))
    }
    var newSteps = seq.steps
    newSteps.append(.filterStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_take(_ seqRaw: Int, _ count: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .takeStep(count: count),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.takeStep(count: count))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_takeLast")
public func kk_sequence_takeLast(_ seqRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var elements: [Int] = []
    _ = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.suffix(clamped))))
}

public func kk_sequence_drop(_ seqRaw: Int, _ count: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .dropStep(count: count),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.dropStep(count: count))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_distinct(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .distinctStep,
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.distinctStep)
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_distinctBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .distinctByStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.distinctByStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_zip(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let otherElements = runtimeSequenceSourceElementsOrPanic(from: otherRaw, caller: #function)
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .zipStep(otherElements: otherElements),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.zipStep(otherElements: otherElements))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_zip_transform(
    _ seqRaw: Int,
    _ otherRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let leftElements = runtimeSequenceSourceElementsOrThrow(from: seqRaw, caller: #function, outThrown: outThrown) ?? []
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
    }
    let rightElements = runtimeSequenceSourceElementsOrThrow(from: otherRaw, caller: #function, outThrown: outThrown) ?? []
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
    }

    let count = min(leftElements.count, rightElements.count)
    var results: [Int] = []
    results.reserveCapacity(count)
    for index in 0 ..< count {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: leftElements[index],
            rhs: rightElements[index],
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        results.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

public func kk_sequence_takeWhile(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .takeWhileStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.takeWhileStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_takeLastWhile")
public func kk_sequence_takeLastWhile(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    var elements: [Int] = []
    _ = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for elem in elements.reversed() {
        var thrown = 0
        let predicateResult = predicate(closureRaw, elem, &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if maybeUnbox(predicateResult) == 0 {
            break
        }
        count += 1
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.suffix(count))))
}

@_cdecl("kk_sequence_filterNot")
public func kk_sequence_filterNot(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let filtered = applyFilterNotStep(sourceElements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        return registerRuntimeObject(RuntimeListBox(elements: filtered))
    }
    var newSteps = seq.steps
    newSteps.append(.filterNotStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

public func kk_sequence_dropWhile(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .dropWhileStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.dropWhileStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence Higher-Order Operations (STDLIB-271)

@_cdecl("kk_sequence_mapNotNull")
public func kk_sequence_mapNotNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .mapNotNullStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.mapNotNullStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_firstNotNullOf")
public func kk_sequence_firstNotNullOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var result = runtimeNullSentinelInt
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let transformed = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if let normalized = runtimeMapNotNullResultValue(transformed) {
            result = normalized
            found = true
            return false
        }
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            // swiftlint:disable:next for_where
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 {
        return handleCollectionLambdaThrow(outThrown.pointee, outThrown)
    }
    if !found {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: kSequenceNoNonNullTransformResult), outThrown)
    }
    return result
}

@_cdecl("kk_sequence_firstNotNullOfOrNull")
public func kk_sequence_firstNotNullOfOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = runtimeNullSentinelInt
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let transformed = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if let normalized = runtimeMapNotNullResultValue(transformed) {
            result = normalized
            return false
        }
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            // swiftlint:disable:next for_where
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 {
        return handleCollectionLambdaThrow(outThrown.pointee, outThrown)
    }
    return result
}

@_cdecl("kk_sequence_filterNotNull")
public func kk_sequence_filterNotNull(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .filterNotNullStep,
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.filterNotNullStep)
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_requireNoNulls")
public func kk_sequence_requireNoNulls(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .requireNoNullsStep,
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.requireNoNullsStep)
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_reversed")
public func kk_sequence_reversed(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let newSeq = RuntimeSequenceBox(steps: [
        .source(elements: Array(elements.reversed())),
    ])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_mapIndexed")
public func kk_sequence_mapIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .mapIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.mapIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_mapIndexedNotNull")
public func kk_sequence_mapIndexedNotNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .mapIndexedNotNullStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.mapIndexedNotNullStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_filterIndexed")
public func kk_sequence_filterIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .filterIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.filterIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_onEachIndexed")
public func kk_sequence_onEachIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .onEachIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.onEachIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_withIndex")
public func kk_sequence_withIndex(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .withIndexStep,
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.withIndexStep)
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

// MARK: - kk_sequence_zipWithNext (STDLIB: Sequence.zipWithNext)

public func kk_sequence_zipWithNext(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    guard values.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var pairs: [RuntimeValue] = []
    pairs.reserveCapacity(values.count - 1)
    for i in 0 ..< values.count - 1 {
        pairs.append(RuntimeValue(raw: runtimePairNew(firstValue: values[i], secondValue: values[i + 1])))
    }
    return registerRuntimeObject(RuntimeListBox(values: pairs))
}

public func kk_sequence_zipWithNextTransform(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let elements: [Int]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        elements = evaluateSequence(seq, outThrown: outThrown)
        if let outThrown, outThrown.pointee != 0 {
            return 0
        }
    } else {
        elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    guard elements.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var results: [Int] = []
    results.reserveCapacity(elements.count - 1)
    for i in 0 ..< elements.count - 1 {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: elements[i], rhs: elements[i + 1], outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return 0
        }
        results.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_sequence_flatMap")
public func kk_sequence_flatMap(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .flatMapStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.flatMapStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_flatMapIndexed")
public func kk_sequence_flatMapIndexed(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .flatMapIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.flatMapIndexedStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_to_list")
public func kk_sequence_to_list(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let values = runtimeSequenceSourceValuesOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    let list = RuntimeListBox(values: values)
    return registerRuntimeObject(list)
}

// MARK: - Sequence Sorting Operations (STDLIB-272)

@_cdecl("kk_sequence_sorted")
public func kk_sequence_sorted(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let seq = RuntimeSequenceBox(steps: [.source(elements: sorted)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_sortedBy")
public func kk_sequence_sortedBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var elems: [Int] = []
    var keys: [Int] = []
    elems.reserveCapacity(elements.count)
    keys.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        elems.append(elem)
        keys.append(maybeUnbox(key))
    }
    let sorted = elems.indices.sorted { lhs, rhs in
        let comparison = runtimeCompareValues(keys[lhs], keys[rhs])
        if comparison != 0 {
            return comparison < 0
        }
        return lhs < rhs
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: sorted.map { elems[$0] })])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_sortedByDescending")
public func kk_sequence_sortedByDescending(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var elems: [Int] = []
    var keys: [Int] = []
    elems.reserveCapacity(elements.count)
    keys.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        elems.append(elem)
        keys.append(maybeUnbox(key))
    }
    let sorted = elems.indices.sorted { lhs, rhs in
        let comparison = runtimeCompareValues(keys[lhs], keys[rhs])
        if comparison != 0 {
            return comparison > 0
        }
        return lhs < rhs
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: sorted.map { elems[$0] })])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_sortedDescending")
public func kk_sequence_sortedDescending(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison > 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let seq = RuntimeSequenceBox(steps: [.source(elements: sorted)])
    return registerRuntimeObject(seq)
}

// MARK: - Sequence Shuffling Operations (STDLIB-SEQ-019)

@_cdecl("kk_sequence_shuffled")
public func kk_sequence_shuffled(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .shuffledStep(randomRaw: nil),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.shuffledStep(randomRaw: nil))
    return registerRuntimeObject(RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState))
}

@_cdecl("kk_sequence_shuffled_random")
public func kk_sequence_shuffled_random(_ seqRaw: Int, _ randomRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .shuffledStep(randomRaw: randomRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.shuffledStep(randomRaw: randomRaw))
    return registerRuntimeObject(RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState))
}
// MARK: - Sequence Terminal Operations: first/firstOrNull/last/count (STDLIB-273)

@_cdecl("kk_sequence_first")
public func kk_sequence_first(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    } else {
        _ = runtimeTraverseSourceSequenceObject(seqRaw, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !found {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_firstOrNull")
public func kk_sequence_firstOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    } else {
        _ = runtimeTraverseSourceSequenceObject(seqRaw, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return found ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_random")
public func kk_sequence_random(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return 0
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    guard let element = elements.randomElement() else {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    return element
}

@_cdecl("kk_sequence_randomOrNull")
public func kk_sequence_randomOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return elements.randomElement() ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_last")
public func kk_sequence_last(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            result = elem
            found = true
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let last = elements.last {
            result = last
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !found {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_lastOrNull")
public func kk_sequence_lastOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            result = elem
            found = true
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let last = elements.last {
            result = last
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    return found ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_singleOrNull")
public func kk_sequence_singleOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var result = runtimeNullSentinelInt
    var count = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            count += 1
            if count == 1 {
                result = elem
                return true
            }
            result = runtimeNullSentinelInt
            return false
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if elements.count == 1 {
            result = elements[0]
            count = 1
        } else {
            count = elements.count
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    return count == 1 ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_single")
public func kk_sequence_single(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var result = 0
    var count = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            count += 1
            if count == 1 {
                result = elem
                return true
            }
            return false
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        count = elements.count
        if count == 1 {
            result = elements[0]
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    guard count == 1 else {
        let message = count == 0
            ? kEmptySequenceNoSuchElement
            : "NoSuchElementException: Sequence has more than one element."
        outThrown?.pointee = runtimeAllocateThrowable(message: message)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_count")
public func kk_sequence_count(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var count = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { _ in
            count += 1
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        count = elements.count
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return count
}

// MARK: - Sequence Terminal Operations: contains/indexOf/elementAt/sum/average/toMutableList/toMutableSet/unzip

@_cdecl("kk_sequence_contains")
public func kk_sequence_contains(_ seqRaw: Int, _ element: Int) -> Int {
    var found = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                found = true
                return false
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        found = elements.contains { runtimeValuesEqual($0, element) }
    }
    return found ? 1 : 0
}

@_cdecl("kk_sequence_indexOf")
public func kk_sequence_indexOf(_ seqRaw: Int, _ element: Int) -> Int {
    var index = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
                return false
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
                break
            }
            currentIndex += 1
        }
    }
    return index
}

@_cdecl("kk_sequence_indexOfFirst")
public func kk_sequence_indexOfFirst(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matchIndex = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
                return false
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
                break
            }
            currentIndex += 1
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    return matchIndex
}

@_cdecl("kk_sequence_lastIndexOf")
public func kk_sequence_lastIndexOf(_ seqRaw: Int, _ element: Int) -> Int {
    var index = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
            }
            currentIndex += 1
        }
    }
    return index
}

@_cdecl("kk_sequence_indexOfLast")
public func kk_sequence_indexOfLast(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matchIndex = -1
    var currentIndex = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
            }
            currentIndex += 1
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeExceptionCaughtSentinel
    }
    return matchIndex
}

@_cdecl("kk_sequence_intersect")
public func kk_sequence_intersect(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    guard let otherElements = runtimeIterableElements(from: otherRaw) else {
        invalidContainerPanic(#function, "iterable")
    }
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }

    var sourceElements: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            sourceElements.append(elem)
            return true
        }
    } else {
        sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }

    let result = runtimeDeduplicatePreservingOrder(sourceElements).filter { elem in
        otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

@_cdecl("kk_sequence_elementAtOrNull")
public func kk_sequence_elementAtOrNull(_ seqRaw: Int, _ index: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard elements.indices.contains(index) else {
        return runtimeNullSentinelInt
    }
    return elements[index]
}

@_cdecl("kk_sequence_elementAt")
public func kk_sequence_elementAt(_ seqRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "Sequence index \(index) out of bounds for length \(elements.count)."
        )
        return runtimeNullSentinelInt
    }
    return elements[index]
}

@_cdecl("kk_sequence_elementAtOrElse")
public func kk_sequence_elementAtOrElse(
    _ seqRaw: Int,
    _ index: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    if elements.indices.contains(index) {
        return elements[index]
    }
    let defaultValue = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = defaultValue(closureRaw, index, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return runtimeNullSentinelInt
    }
    return result
}

@_cdecl("kk_sequence_sum")
public func kk_sequence_sum(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var total = 0
    for element in elements { total &+= maybeUnbox(element) }
    return total
}

@_cdecl("kk_sequence_average")
public func kk_sequence_average(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard !elements.isEmpty else { return kk_double_to_bits(Double.nan) }
    var total = 0.0
    for element in elements { total += Double(maybeUnbox(element)) }
    return kk_double_to_bits(total / Double(elements.count))
}

@_cdecl("kk_sequence_toMutableList")
public func kk_sequence_toMutableList(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeListBox(values: values))
}

@_cdecl("kk_sequence_toMutableSet")
public func kk_sequence_toMutableSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)))
}

@_cdecl("kk_sequence_toHashSet")
public func kk_sequence_toHashSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)))
}

@_cdecl("kk_sequence_toCollection")
public func kk_sequence_toCollection(_ seqRaw: Int, _ destRaw: Int) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    for value in values {
        runtimeAppendToMutableCollection(destRaw, value)
    }
    return destRaw
}

@_cdecl("kk_sequence_unzip")
public func kk_sequence_unzip(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    var firstValues: [RuntimeValue] = []
    var secondValues: [RuntimeValue] = []
    firstValues.reserveCapacity(elements.count)
    secondValues.reserveCapacity(elements.count)
    for pairValue in elements {
        let pairRaw = pairValue.legacyRawValue
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pairRaw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in \(#function)")
        }
        firstValues.append(pairBox.firstValue)
        secondValues.append(pairBox.secondValue)
    }
    let firstList = registerRuntimeObject(RuntimeListBox(values: firstValues))
    let secondList = registerRuntimeObject(RuntimeListBox(values: secondValues))
    return runtimePairNew(
        firstValue: RuntimeValue(raw: firstList),
        secondValue: RuntimeValue(raw: secondList)
    )
}

// MARK: - Sequence Terminal Operations: any/all/none/fold/reduce (STDLIB-274)

@_cdecl("kk_sequence_any")
public func kk_sequence_any(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if fnPtr == 0 {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        return kk_box_bool(elements.isEmpty ? 0 : 1)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matched = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            matched = maybeUnbox(result) != 0
            return !matched
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(0)
            }
            if maybeUnbox(result) != 0 {
                matched = true
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(0)
    }
    return kk_box_bool(matched ? 1 : 0)
}

@_cdecl("kk_sequence_all")
public func kk_sequence_all(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var allMatched = true
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) == 0 {
                allMatched = false
                return false
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(0)
            }
            if maybeUnbox(result) == 0 {
                allMatched = false
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(0)
    }
    return kk_box_bool(allMatched ? 1 : 0)
}

@_cdecl("kk_sequence_none")
public func kk_sequence_none(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if fnPtr == 0 {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        return kk_box_bool(elements.isEmpty ? 1 : 0)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var foundMatch = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            foundMatch = maybeUnbox(result) != 0
            return !foundMatch
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(1)
            }
            if maybeUnbox(result) != 0 {
                foundMatch = true
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(1)
    }
    return kk_box_bool(foundMatch ? 0 : 1)
}

@_cdecl("kk_sequence_fold")
public func kk_sequence_fold(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
            if step.thrown != 0 { return false }
            acc = step.accumulator
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
            if step.thrown != 0 { return initial }
            acc = step.accumulator
        }
    }
    if let outThrown, outThrown.pointee != 0 { return initial }
    return acc
}

@_cdecl("kk_sequence_reduce")
public func kk_sequence_reduce(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            return true
        }
        let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return false }
        acc = step.accumulator
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            // swiftlint:disable:next for_where
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

@_cdecl("kk_sequence_reduceOrNull")
public func kk_sequence_reduceOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            return true
        }
        let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return false }
        acc = step.accumulator
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return hasAccumulator ? acc : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_reduceRight")
public func kk_sequence_reduceRight(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return runtimeReduceRightElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: 0,
        throwResult: 0,
        emptyMessage: kEmptySequenceCannotReduce,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightIndexedOrNull")
public func kk_sequence_reduceRightIndexedOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return runtimeReduceRightIndexedElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightOrNull")
public func kk_sequence_reduceRightOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return runtimeReduceRightElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightIndexed")
public func kk_sequence_reduceRightIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return runtimeReduceRightIndexedElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: 0,
        throwResult: 0,
        emptyMessage: kEmptySequenceCannotReduce,
        outThrown: outThrown
    )
}

// MARK: - Sequence Operations: chunked/windowed/onEach (STDLIB-276)

public func kk_sequence_chunked(_ seqRaw: Int, _ size: Int) -> Int {
    let chunkSize = max(1, size)
    // Lazily traverse upstream to build chunks on the fly
    var chunks: [Int] = []
    var currentChunk: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            currentChunk.append(elem)
            if currentChunk.count == chunkSize {
                let chunkList = RuntimeListBox(elements: currentChunk)
                chunks.append(registerRuntimeObject(chunkList))
                currentChunk = []
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        for elem in elements {
            currentChunk.append(elem)
            if currentChunk.count == chunkSize {
                let chunkList = RuntimeListBox(elements: currentChunk)
                chunks.append(registerRuntimeObject(chunkList))
                currentChunk = []
            }
        }
    }
    if !currentChunk.isEmpty {
        let chunkList = RuntimeListBox(elements: currentChunk)
        chunks.append(registerRuntimeObject(chunkList))
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: chunks)])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_chunked_transform(
    _ seqRaw: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid sequence in kk_sequence_chunked_transform")
    }

    let chunkedTransform = SequenceStepKind.chunkedTransformStep(
        size: max(1, size),
        fnPtr: fnPtr,
        closureRaw: closureRaw
    )
    let resultSeq = RuntimeSequenceBox(steps: seq.steps + [chunkedTransform])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_windowed(_ seqRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let includePartial = partialWindows != 0
    // Lazily traverse upstream to build windows on the fly
    var buffer: [Int] = []
    var windows: [Int] = []
    var elementIndex = 0
    var nextWindowStart = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            buffer.append(elem)
            elementIndex += 1
            // Emit windows whose start position we've passed
            while nextWindowStart + clampedSize <= elementIndex {
                let window = Array(buffer[nextWindowStart..<(nextWindowStart + clampedSize)])
                let windowList = RuntimeListBox(elements: window)
                windows.append(registerRuntimeObject(windowList))
                nextWindowStart += clampedStep
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        buffer = elements
        elementIndex = elements.count
        while nextWindowStart + clampedSize <= elementIndex {
            let window = Array(buffer[nextWindowStart..<(nextWindowStart + clampedSize)])
            let windowList = RuntimeListBox(elements: window)
            windows.append(registerRuntimeObject(windowList))
            nextWindowStart += clampedStep
        }
    }
    // Handle partial windows at the end
    if includePartial {
        while nextWindowStart < elementIndex {
            let end = min(nextWindowStart + clampedSize, elementIndex)
            let window = Array(buffer[nextWindowStart..<end])
            let windowList = RuntimeListBox(elements: window)
            windows.append(registerRuntimeObject(windowList))
            nextWindowStart += clampedStep
        }
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: windows)])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_windowed_transform(
    _ seqRaw: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let windowsRaw = kk_sequence_windowed(seqRaw, size, step, partialWindows)
    let windows = runtimeSequenceSourceElementsOrPanic(from: windowsRaw, caller: #function)
    var results: [Int] = []
    results.reserveCapacity(windows.count)
    for windowRaw in windows {
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: windowRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        results.append(maybeUnbox(transformed))
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: results)])
    return registerRuntimeObject(resultSeq)
}

@_cdecl("kk_sequence_onEach")
public func kk_sequence_onEach(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .onEachStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.onEachStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence Terminal Operations: toSet/toMap/groupBy/maxOrNull/minOrNull/flatten (STDLIB-470)

@_cdecl("kk_sequence_toSet")
public func kk_sequence_toSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)))
}

@_cdecl("kk_sequence_toSortedSet")
public func kk_sequence_toSortedSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    let sorted = values.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(sorted)))
}

@_cdecl("kk_sequence_toMap")
public func kk_sequence_toMap(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let collected = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    var keys: [Int] = []
    var values: [Int] = []
    // Dictionary mapping key index in `keys` for O(1) duplicate-key lookup.
    // Uses RuntimeElementKey to respect runtimeValuesEqual semantics (e.g. String content equality).
    var keyIndexByRuntimeKey: [RuntimeElementKey: Int] = [:]
    for element in collected {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: element) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_toMap element is not a valid Pair handle")
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
        guard isObjectPointer, let pair = tryCast(pointer, to: RuntimePairBox.self) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_toMap element is not a valid Pair handle")
        }
        let runtimeKey = RuntimeElementKey(value: pair.first)
        if let idx = keyIndexByRuntimeKey[runtimeKey] {
            values[idx] = pair.second
        } else {
            let newIndex = keys.count
            keyIndexByRuntimeKey[runtimeKey] = newIndex
            keys.append(pair.first)
            values.append(pair.second)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_sequence_groupBy")
public func kk_sequence_groupBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    // Uses RuntimeElementKey to respect runtimeValuesEqual semantics (e.g. String content equality).
    var keyToIndex: [RuntimeElementKey: Int] = [:]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let key = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let runtimeKey = RuntimeElementKey(value: key)
            if let grpIdx = keyToIndex[runtimeKey] {
                groupElements[grpIdx].append(elem)
            } else {
                let newIndex = groupKeys.count
                keyToIndex[runtimeKey] = newIndex
                groupKeys.append(key)
                groupElements.append([elem])
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let key = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
            }
            let runtimeKey = RuntimeElementKey(value: key)
            if let grpIdx = keyToIndex[runtimeKey] {
                groupElements[grpIdx].append(elem)
            } else {
                let newIndex = groupKeys.count
                keyToIndex[runtimeKey] = newIndex
                groupKeys.append(key)
                groupElements.append([elem])
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}

@_cdecl("kk_sequence_maxOrNull")
public func kk_sequence_maxOrNull(_ seqRaw: Int) -> Int {
    var best: Int?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if let current = best {
                if runtimeCompareValues(elem, current) > 0 {
                    best = elem
                }
            } else {
                best = elem
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        guard let first = elements.first else {
            return runtimeNullSentinelInt
        }
        best = first
        for elem in elements.dropFirst() where runtimeCompareValues(elem, best!) > 0 {
            best = elem
        }
    }
    return best ?? runtimeNullSentinelInt
}

/// Sequence<T : Comparable>.max(): T (throws NoSuchElementException if empty)
@_cdecl("kk_sequence_max")
public func kk_sequence_max(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let result = kk_sequence_maxOrNull(seqRaw)
    guard result != runtimeNullSentinelInt else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement), outThrown)
    }
    return result
}

@_cdecl("kk_sequence_minOrNull")
public func kk_sequence_minOrNull(_ seqRaw: Int) -> Int {
    var best: Int?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if let current = best {
                if runtimeCompareValues(elem, current) < 0 {
                    best = elem
                }
            } else {
                best = elem
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        guard let first = elements.first else {
            return runtimeNullSentinelInt
        }
        best = first
        for elem in elements.dropFirst() where runtimeCompareValues(elem, best!) < 0 {
            best = elem
        }
    }
    return best ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_min")
public func kk_sequence_min(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var best: Int?
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        if let current = best {
            if runtimeCompareValues(elem, current) < 0 {
                best = elem
            }
        } else {
            best = elem
        }
        return true
    }
    if (outThrown?.pointee ?? 0) != 0 {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached), outThrown)
    }
    guard let best else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement), outThrown)
    }
    return best
}

@_cdecl("kk_sequence_flatten")
public func kk_sequence_flatten(_ seqRaw: Int) -> Int {
    var outerElements: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            outerElements.append(elem)
            return true
        }
    } else {
        outerElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    var result: [Int] = []
    for subRaw in outerElements {
        if let subList = runtimeListBox(from: subRaw) {
            result.append(contentsOf: subList.elements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq))
        }
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: result)])
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence plus/minus Operations (STDLIB-561, STDLIB-562)
//
// IMPORTANT: Both plus and minus eagerly materialize the entire input
// sequence via evaluateSequence.  Unlike Kotlin's stdlib (which returns
// a lazy sequence), our implementation is eager.  This is an intentional
// simplification -- eager evaluation is correct for finite sequences and
// keeps the implementation simple.  A future optimisation can add
// .concat / .minus step kinds to RuntimeSequenceBox for lazy evaluation
// without changing the public ABI.
//
// ABI CONTRACT:
// - kk_sequence_plus(seqRaw, otherRaw): `otherRaw` MUST be a collection
//   handle (sequence, list, or array).  The compiler wraps single-element
//   operands via kk_sequence_of_single before calling this function, so
//   the runtime never needs to guess whether otherRaw is an element or a
//   collection.
// - kk_sequence_minus(seqRaw, element): `element` is always a single
//   value (not a collection handle).  The compiler only emits this call
//   when the RHS is known to be a non-collection expression.

@_cdecl("kk_sequence_plus")
public func kk_sequence_plus(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let lhsElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let rhsElements = runtimeSequenceSourceElementsOrPanic(from: otherRaw, caller: #function)
    // Single-allocation concatenation: create an array with the exact
    // final capacity up front so there are no intermediate reallocations
    // or copy-on-write copies.
    let totalCount = lhsElements.count + rhsElements.count
    let combined = [Int](unsafeUninitializedCapacity: totalCount) { buffer, initializedCount in
        var idx = 0
        for e in lhsElements { buffer[idx] = e; idx += 1 }
        for e in rhsElements { buffer[idx] = e; idx += 1 }
        initializedCount = idx
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: combined)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_plus_element")
public func kk_sequence_plus_element(_ seqRaw: Int, _ element: Int) -> Int {
    let wrappedElement = kk_sequence_of_single(element)
    return kk_sequence_plus(seqRaw, wrappedElement)
}

@_cdecl("kk_sequence_minus")
public func kk_sequence_minus(_ seqRaw: Int, _ element: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var result = elements
    // NOTE: runtimeValuesEqual compares primitives (Int, String, Bool, etc.)
    // by value but falls back to pointer identity for collection types
    // (List, Set, Map).  This means `minus` cannot remove collection
    // elements by structural equality (e.g., two distinct `listOf(1)`
    // instances).  This is a known limitation; fixing it requires adding
    // recursive structural comparison to runtimeValuesEqual, which is
    // tracked separately.
    if let index = result.firstIndex(where: { runtimeValuesEqual($0, element) }) {
        result.remove(at: index)
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: result)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_union")
public func kk_sequence_union(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(selfElements + otherElements)))
}

@_cdecl("kk_sequence_subtract")
public func kk_sequence_subtract(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = runtimeDeduplicatePreservingOrder(selfElements).filter { elem in
        !otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

// MARK: - Runtime-backed Sequence/Iterator itable support

/// `Sequence.iterator()` implementation for `RuntimeSequenceBox`.
/// Returns a `RuntimeSequenceIteratorBox` handle registered with the
/// `kotlin.collections.Iterator` itable so source `Sequence` wrappers can call
/// `hasNext()` / `next()` through normal interface dispatch.
@_cdecl("kk_sequence_box_iterator")
public func kk_sequence_box_iterator(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        return 0
    }
    let iterator = RuntimeSequenceIteratorBox(seq: seq)
    let raw = registerRuntimeObject(iterator as AnyObject)
    _ = kk_object_register_itable_iface(raw, Int(runtimeIteratorInterfaceTypeID), 0)
    let hasNextPtr = unsafeBitCast(
        kk_sequence_iterator_hasNext as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    _ = kk_object_register_itable_method(raw, 0, 0, hasNextPtr)
    let nextPtr = unsafeBitCast(
        kk_sequence_iterator_next as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    _ = kk_object_register_itable_method(raw, 0, 1, nextPtr)
    return raw
}

@_cdecl("kk_sequence_iterator_hasNext")
public func kk_sequence_iterator_hasNext(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeSequenceIteratorBox(from: iterRaw) else {
        return 0
    }
    iter.materialize(outThrown: outThrown)
    if outThrown?.pointee != 0 {
        return 0
    }
    return iter.index < iter.elements.count ? 1 : 0
}

@_cdecl("kk_sequence_iterator_next")
public func kk_sequence_iterator_next(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeSequenceIteratorBox(from: iterRaw) else {
        return 0
    }
    iter.materialize(outThrown: outThrown)
    if outThrown?.pointee != 0 {
        return 0
    }
    guard iter.index < iter.elements.count else {
        return 0
    }
    let value = iter.elements[iter.index]
    iter.index += 1
    return value
}

func registerRuntimeObject(_ box: RuntimeSequenceBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject)
    _ = kk_object_register_itable_iface(raw, Int(runtimeSequenceInterfaceTypeID), 0)
    let iteratorPtr = unsafeBitCast(
        kk_sequence_box_iterator as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    _ = kk_object_register_itable_method(raw, 0, 0, iteratorPtr)
    return raw
}
