import Foundation

// MARK: - Sequence Functions (STDLIB-003)

/// Resolve a raw integer handle to a registered runtime object of the given type.
/// Returns nil if the handle is zero/null, not a registered object pointer, or
/// points to an object of a different type.
private func resolveRuntimeHandle<T: AnyObject>(_ rawValue: Int, as _: T.Type) -> T? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: T.self)
}

private func runtimeSequenceBox(from rawValue: Int) -> RuntimeSequenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBox.self)
}

private func runtimeSequenceBuilderBox(from rawValue: Int) -> RuntimeSequenceBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBuilderBox.self)
}

func runtimeSequenceSourceElements(from rawValue: Int) -> [Int]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        return evaluateSequence(seq)
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.elements
    }
    if let array = runtimeArrayBox(from: rawValue) {
        return array.elements
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
    if let array = runtimeArrayBox(from: rawValue) {
        return array.elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

/// Fail-fast variant that panics on invalid handles instead of returning nil.
/// Use this instead of `runtimeSequenceSourceElements(from:) ?? []` to distinguish
/// invalid handles from legitimately empty sequences.
private func runtimeSequenceSourceElementsOrPanic(from rawValue: Int, caller: StaticString) -> [Int] {
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

private final class SequenceTraversalState {
    var stop = false
    var limitReached = false
    var takeCounts: [Int: Int] = [:]
    var dropCounts: [Int: Int] = [:]
    var distinctSeen: [Int: [Int]] = [:]
    var zipIndices: [Int: Int] = [:]
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
private let kEmptySequenceNoSuchElement = "NoSuchElementException: Sequence is empty."
/// Error message for `reduce` on an empty sequence.
private let kEmptySequenceCannotReduce = "UnsupportedOperationException: Empty sequence can't be reduced."
/// Error message when a generator sequence exceeds the traversal hard limit.
private let kSequenceGeneratorLimitReached = "IllegalStateException: Sequence generator exceeded traversal hard limit (\(kSequenceGeneratorHardLimit))."
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
        runtimeSequenceTransformElement(
            maybeUnbox(mapped),
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
        runtimeSequenceTransformElement(
            maybeUnbox(mapped),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
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
        // Handle the sub-collection/sequence
        if let subList = runtimeListBox(from: subRaw) {
            for subElem in subList.elements {
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
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            runtimeTraverseSequence(subSeq, outThrown: outThrown) { subElem in
                runtimeSequenceTransformElement(
                    subElem,
                    steps: steps,
                    stepIndex: stepIndex + 1,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
                return !state.stop
            }
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
        if let subElements = runtimeCollectionElements(from: subRaw) {
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
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            runtimeTraverseSequence(subSeq, outThrown: outThrown) { subElem in
                runtimeSequenceTransformElement(
                    subElem,
                    steps: steps,
                    stepIndex: stepIndex + 1,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
                return !state.stop
            }
        }
    case .source, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
        runtimeSequenceTransformElement(
            element,
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
private func runtimeTraverseSequenceWithState(
    _ seq: RuntimeSequenceBox,
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    markConsumption: Bool = true,
    yield: @escaping (Int) -> Bool
) {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return
    }

    let transformSteps = seq.steps.filter {
        switch $0 {
        case .source, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
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
                if state.stop { return }
            }
            return
        case let .lazyBuilder(coroutine):
            // STDLIB-563: Lazy element-by-element iteration.
            // Request one element at a time from the coroutine so that
            // short-circuiting operations (take, first, etc.) only
            // compute the elements they actually need.
            coroutine.resetIteration()
            while true {
                let next = coroutine.nextElement()
                switch next {
                case let .value(element):
                    emit(element)
                    if state.stop { return }
                case .done:
                    return
                }
            }
        case let .stringSource(strRaw):
            // Lazy: iterate string characters on demand without pre-materializing.
            // NOTE: Kotlin Char is a UTF-16 code unit (16-bit). Iterating unicodeScalars
            // produces values > 0xFFFF for supplementary characters (e.g. emoji),
            // which do not fit in a Kotlin Char. We iterate utf16 code units instead to
            // match Kotlin's Char semantics correctly. Supplementary characters are split
            // into two surrogate code units, which is the expected Kotlin behaviour.
            let str = runtimeStringFromRawOrPanic(strRaw, caller: "kk_string_asSequence")
            for codeUnit in str.utf16 {
                emit(kk_box_char(Int(codeUnit)))
                if state.stop { return }
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
                    return
                }
                let unboxed = maybeUnbox(next)
                if unboxed == runtimeNullSentinelInt { return }
                emit(unboxed)
                current = unboxed
                generatedCount += 1
            }
            if generatedCount >= kSequenceGeneratorHardLimit, !state.stop {
                state.limitReached = true
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
                    return
                }
                let unboxed = maybeUnbox(next)
                if unboxed == runtimeNullSentinelInt { return }
                emit(unboxed)
                generatedCount += 1
            }
            if generatedCount >= kSequenceGeneratorHardLimit, !state.stop {
                state.limitReached = true
            }
            return
        case .mapStep, .filterStep, .filterNotStep, .takeStep, .dropStep, .distinctStep, .zipStep, .takeWhileStep, .dropWhileStep, .onEachStep, .onEachIndexedStep, .mapNotNullStep, .filterNotNullStep, .requireNoNullsStep, .mapIndexedStep, .withIndexStep, .flatMapStep, .flatMapIndexedStep:
            continue
        }
    }
}


/// Convenience wrapper that creates its own `SequenceTraversalState`.
private func runtimeTraverseSequence(
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

/// Extracts source elements from a sequence step, if applicable.
/// `.stringSource` is NOT extracted here — it is handled lazily in evaluateSequence
/// and runtimeTraverseSequence to avoid eager materialization.
private func extractSourceElements(from step: SequenceStepKind) -> [Int]? {
    switch step {
    case let .source(sourceElements):
        return sourceElements
    case let .builder(builderElements):
        return builderElements
    case let .lazyBuilder(coroutine):
        // STDLIB-563: Materialize the lazy coroutine into an element array.
        return coroutine.materializeAll()
    default:
        return nil
    }
}

/// Applies a map transformation to elements using the given function pointer.
/// Lambda signature: (closureRaw, elem, outThrown) -> Int (same as list HOFs).
private func applyMapStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        mapped.append(maybeUnbox(result))
    }
    return mapped
}

/// Applies a filter transformation to elements using the given function pointer.
/// Lambda signature: (closureRaw, elem, outThrown) -> Int (same as list HOFs).
private func applyFilterStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var filtered: [Int] = []
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if maybeUnbox(result) != 0 {
            filtered.append(elem)
        }
    }
    return filtered
}

/// Applies a filterNot transformation: keeps elements where predicate returns false.
/// Lambda signature: (closureRaw, elem, outThrown) -> Int (same as list HOFs).
private func applyFilterNotStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var filtered: [Int] = []
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if maybeUnbox(result) == 0 {
            filtered.append(elem)
        }
    }
    return filtered
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

/// Applies a mapNotNull transformation: maps elements and filters out null values.
private func applyMapNotNullStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if let normalized = runtimeMapNotNullResultValue(result) {
            mapped.append(normalized)
        }
    }
    return mapped
}

/// Applies a filterNotNull transformation: filters out null values.
private func applyFilterNotNullStep(_ elements: [Int]) -> [Int] {
    return elements.filter { runtimeNormalizeNullableCollectionValue($0) != nil }
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

/// Applies a mapIndexed transformation: maps elements with their index.
private func applyMapIndexedStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        mapped.append(maybeUnbox(result))
    }
    return mapped
}

/// Applies an onEachIndexed transformation: runs a side effect with index and value.
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
        if let subList = runtimeListBox(from: subRaw) {
            result.append(contentsOf: subList.elements)
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
        case .source, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
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
        if case let .stringSource(strRaw) = step {
            // Materialize string characters at terminal evaluation only.
            // Use utf16 code units (not unicodeScalars) so that supplementary characters
            // (emoji, etc. with scalar value > 0xFFFF) are represented as surrogate pairs,
            // matching Kotlin's UTF-16 Char semantics.
            let str = runtimeStringFromRawOrPanic(strRaw, caller: "kk_string_asSequence")
            elements = str.utf16.map { kk_box_char(Int($0)) }
            break
        }
        if case let .generator(seed, fnPtr, closureRaw) = step {
            var current = seed
            var generated: [Int] = [current]
            while generated.count < kSequenceGeneratorHardLimit {
                var thrown = 0
                let next = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: current, outThrown: &thrown)
                if thrown != 0 { break }
                let unboxed = maybeUnbox(next)
                if unboxed == runtimeNullSentinelInt { break }
                generated.append(unboxed)
                current = unboxed
            }
            elements = generated
            break
        }
        if case let .nullableGenerator(fnPtr, closureRaw) = step {
            // STDLIB-SEQ-002: 1-arg form — no seed, call no-arg function until null.
            let noArgFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var generated: [Int] = []
            while generated.count < kSequenceGeneratorHardLimit {
                var thrown = 0
                let next = noArgFn(closureRaw, &thrown)
                if thrown != 0 { break }
                let unboxed = maybeUnbox(next)
                if unboxed == runtimeNullSentinelInt { break }
                generated.append(unboxed)
            }
            elements = generated
            break
        }
    }

    // Apply transformation steps in order
    for step in seq.steps {
        switch step {
        case .source, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder:
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
        case .withIndexStep:
            elements = applyWithIndexStep(elements)
        case let .flatMapStep(fnPtr, closureRaw):
            elements = applyFlatMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .flatMapIndexedStep(fnPtr, closureRaw):
            elements = applyFlatMapIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        }
        if let outThrown, outThrown.pointee != 0 { return [] }
    }

    return elements
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

@_cdecl("kk_empty_sequence")
public func kk_empty_sequence() -> Int {
    let seq = RuntimeSequenceBox(steps: [.source(elements: [])])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_orEmpty")
public func kk_sequence_orEmpty(_ seqRaw: Int) -> Int {
    if seqRaw == runtimeNullSentinelInt || seqRaw == 0 {
        return kk_empty_sequence()
    }
    return seqRaw
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

@_cdecl("kk_sequence_of")
public func kk_sequence_of(_ arrayRaw: Int) -> Int {
    guard let arr = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_of expected RuntimeArrayBox")
    }
    let elements = Array(arr.elements)
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

@_cdecl("kk_sequence_generate")
public func kk_sequence_generate(_ seed: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.generator(seed: seed, fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
}

/// STDLIB-SEQ-002: 1-arg form `generateSequence(nextFunction: () -> T?)`.
/// Calls `nextFunction` (no-arg closure) repeatedly; stops when null is returned.
@_cdecl("kk_sequence_generate_noarg")
public func kk_sequence_generate_noarg(_ fnPtr: Int, _ closureRaw: Int) -> Int {
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

@_cdecl("kk_sequence_take")
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

@_cdecl("kk_sequence_drop")
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

@_cdecl("kk_sequence_distinct")
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

@_cdecl("kk_sequence_zip")
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

@_cdecl("kk_sequence_takeWhile")
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

@_cdecl("kk_sequence_dropWhile")
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

// MARK: - Sequence Terminal Operations

@_cdecl("kk_sequence_forEach")
public func kk_sequence_forEach(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            var thrown = 0
            _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
            if thrown != 0 {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        for elem in elements {
            var thrown = 0
            _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
            if thrown != 0 {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
            }
        }
    }
    return 0
}

@_cdecl("kk_sequence_forEachIndexed")
public func kk_sequence_forEachIndexed(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let elements: [Int]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        elements = evaluateSequence(seq)
    } else {
        elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence forEachIndexed lambda threw but no outThrown available")
        }
    }
    return 0
}

// MARK: - kk_sequence_zipWithNext (STDLIB: Sequence.zipWithNext)

@_cdecl("kk_sequence_zipWithNext")
public func kk_sequence_zipWithNext(_ seqRaw: Int) -> Int {
    let elements: [Int]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        elements = evaluateSequence(seq)
    } else {
        elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    guard elements.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var pairs: [Int] = []
    pairs.reserveCapacity(elements.count - 1)
    for i in 0 ..< elements.count - 1 {
        pairs.append(kk_pair_new(elements[i], elements[i + 1]))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_sequence_zipWithNextTransform")
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
    guard let elements = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    let list = RuntimeListBox(elements: elements)
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
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let seq = RuntimeSequenceBox(steps: [.source(elements: elements.shuffled())])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_shuffled_random")
public func kk_sequence_shuffled_random(_ seqRaw: Int, _ randomRaw: Int) -> Int {
    var elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard elements.count > 1 else {
        return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: elements)]))
    }
    for i in stride(from: elements.count - 1, through: 1, by: -1) {
        let j = kk_random_nextInt_until(randomRaw, i + 1, nil)
        elements.swapAt(i, j)
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: elements)]))
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
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let first = elements.first {
            result = first
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !found {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
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
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let first = elements.first {
            result = first
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return found ? result : runtimeNullSentinelInt
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
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
        return 0
    }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_find")
public func kk_sequence_find(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let predicateResult = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(predicateResult) != 0 {
                found = true
                result = elem
                return false
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let predicateResult = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            if maybeUnbox(predicateResult) != 0 {
                found = true
                result = elem
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return found ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_findLast")
public func kk_sequence_findLast(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = runtimeNullSentinelInt
    var hasMatch = false
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let predicateResult = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(predicateResult) != 0 {
                found = elem
                hasMatch = true
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let predicateResult = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            if maybeUnbox(predicateResult) != 0 {
                found = elem
                hasMatch = true
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    return hasMatch ? found : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_asIterable")
public func kk_sequence_asIterable(_ seqRaw: Int) -> Int {
    // Sequence is already an Iterable, so return the same handle
    return seqRaw
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
    return kk_box_bool(found ? 1 : 0)
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

@_cdecl("kk_sequence_sum")
public func kk_sequence_sum(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    return kk_list_sum(registerRuntimeObject(RuntimeListBox(elements: elements)))
}

@_cdecl("kk_sequence_average")
public func kk_sequence_average(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    return kk_list_average(registerRuntimeObject(RuntimeListBox(elements: elements)))
}

@_cdecl("kk_sequence_toMutableList")
public func kk_sequence_toMutableList(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_sequence_toMutableSet")
public func kk_sequence_toMutableSet(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

@_cdecl("kk_sequence_toHashSet")
public func kk_sequence_toHashSet(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

@_cdecl("kk_sequence_toCollection")
public func kk_sequence_toCollection(_ seqRaw: Int, _ destRaw: Int) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        runtimeAppendToMutableCollection(destRaw, elem)
    }
    return destRaw
}

@_cdecl("kk_sequence_unzip")
public func kk_sequence_unzip(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var firstValues: [Int] = []
    var secondValues: [Int] = []
    firstValues.reserveCapacity(elements.count)
    secondValues.reserveCapacity(elements.count)
    for pairRaw in elements {
        firstValues.append(kk_pair_first(pairRaw))
        secondValues.append(kk_pair_second(pairRaw))
    }
    let firstList = registerRuntimeObject(RuntimeListBox(elements: firstValues))
    let secondList = registerRuntimeObject(RuntimeListBox(elements: secondValues))
    return kk_pair_new(firstList, secondList)
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
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = initial
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let nextAcc = lambda(closureRaw, acc, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            acc = maybeUnbox(nextAcc)
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let nextAcc = lambda(closureRaw, acc, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return initial
            }
            acc = maybeUnbox(nextAcc)
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
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var hasAccumulator = false
    var acc = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            return true
        }
        var thrown = 0
        let nextAcc = lambda(closureRaw, acc, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

// MARK: - Sequence scan / runningFold / runningReduce (STDLIB-558, STDLIB-559, STDLIB-560)

@_cdecl("kk_sequence_scan")
public func kk_sequence_scan(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = maybeUnbox(initial)
    var results: [Int] = [acc]
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            var thrown = 0
            let nextAcc = lambda(closureRaw, acc, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            acc = maybeUnbox(nextAcc)
            results.append(acc)
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let nextAcc = lambda(closureRaw, acc, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            acc = maybeUnbox(nextAcc)
            results.append(acc)
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_sequence_runningFold")
public func kk_sequence_runningFold(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_sequence_scan(seqRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_sequence_runningReduce")
public func kk_sequence_runningReduce(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var hasAccumulator = false
    var acc = 0
    var results: [Int] = []
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            results.append(acc)
            return true
        }
        var thrown = 0
        let nextAcc = lambda(closureRaw, acc, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        results.append(acc)
        return true
    }

    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// MARK: - Sequence foldIndexed / runningFoldIndexed / scanIndexed / reduceIndexed / reduceIndexedOrNull
// MARK: - (STDLIB-556, STDLIB-557, STDLIB-SEQ-015, STDLIB-SEQ-016, STDLIB-SEQ-017)

@_cdecl("kk_sequence_runningReduceIndexed")
public func kk_sequence_runningReduceIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    var results: [Int] = []
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            results.append(acc)
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: acc,
            arg3: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        results.append(acc)
        index += 1
        return true
    }

    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_sequence_foldIndexed")
public func kk_sequence_foldIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    var index = 0
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            var thrown = 0
            let nextAcc = runtimeInvokeCollectionLambda3(
                fnPtr: fnPtr, closureRaw: closureRaw,
                arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            acc = maybeUnbox(nextAcc)
            index += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let nextAcc = runtimeInvokeCollectionLambda3(
                fnPtr: fnPtr, closureRaw: closureRaw,
                arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return initial
            }
            acc = maybeUnbox(nextAcc)
            index += 1
        }
    }
    if let outThrown, outThrown.pointee != 0 { return initial }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return initial
    }
    return acc
}

@_cdecl("kk_sequence_runningFoldIndexed")
public func kk_sequence_runningFoldIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_sequence_scanIndexed(seqRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_sequence_scanIndexed")
public func kk_sequence_scanIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = maybeUnbox(initial)
    var index = 0
    var results: [Int] = [acc]
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown) { elem in
            var thrown = 0
            let nextAcc = runtimeInvokeCollectionLambda3(
                fnPtr: fnPtr, closureRaw: closureRaw,
                arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            acc = maybeUnbox(nextAcc)
            index += 1
            results.append(acc)
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let nextAcc = runtimeInvokeCollectionLambda3(
                fnPtr: fnPtr, closureRaw: closureRaw,
                arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            acc = maybeUnbox(nextAcc)
            index += 1
            results.append(acc)
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

@_cdecl("kk_sequence_reduceIndexed")
public func kk_sequence_reduceIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr, closureRaw: closureRaw,
            arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        return true
    }

    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

@_cdecl("kk_sequence_reduceIndexedOrNull")
public func kk_sequence_reduceIndexedOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: acc,
            arg3: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        return true
    }

    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let st = SequenceTraversalState()
        traversalState = st
        runtimeTraverseSequenceWithState(seq, state: st, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        return runtimeNullSentinelInt
    }
    return acc
}

// MARK: - Sequence Terminal Operations: joinToString/sumOf/associate/associateBy (STDLIB-275)

@_cdecl("kk_sequence_joinToString")
public func kk_sequence_joinToString(_ seqRaw: Int, _ separatorRaw: Int, _ prefixRaw: Int, _ postfixRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let joined = elements.map(runtimeElementToString).joined(separator: separator)
    let stringValue = prefix + joined + postfix
    let utf8 = Array(stringValue.utf8)
    return Int(bitPattern: utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    })
}

@_cdecl("kk_sequence_sumOf")
public func kk_sequence_sumOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var total = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            total += maybeUnbox(result)
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            total += maybeUnbox(result)
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return total
}

@_cdecl("kk_sequence_associate")
public func kk_sequence_associate(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let pair = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            keys.append(kk_pair_first(pair))
            values.append(kk_pair_second(pair))
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let pair = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
            }
            keys.append(kk_pair_first(pair))
            values.append(kk_pair_second(pair))
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_sequence_associateBy")
public func kk_sequence_associateBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let key = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            keys.append(maybeUnbox(key))
            values.append(elem)
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
            keys.append(maybeUnbox(key))
            values.append(elem)
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_sequence_partition")
public func kk_sequence_partition(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matching: [Int] = []
    var nonMatching: [Int] = []
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
                matching.append(elem)
            } else {
                nonMatching.append(elem)
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            if maybeUnbox(result) != 0 {
                matching.append(elem)
            } else {
                nonMatching.append(elem)
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    let matchingList = registerRuntimeObject(RuntimeListBox(elements: matching))
    let nonMatchingList = registerRuntimeObject(RuntimeListBox(elements: nonMatching))
    return kk_pair_new(matchingList, nonMatchingList)
}

@_cdecl("kk_sequence_associateWith")
public func kk_sequence_associateWith(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let value = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            keys.append(elem)
            values.append(maybeUnbox(value))
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let value = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
            }
            keys.append(elem)
            values.append(maybeUnbox(value))
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

// MARK: - Sequence destination map operations (STDLIB-SEQ-023)

@_cdecl("kk_sequence_associateTo")
public func kk_sequence_associateTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMapBox(from: destRaw) != nil else {
        invalidContainerPanic(#function, "map")
    }
    var traversalState: SequenceTraversalState?
    var didThrow = false
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let pair = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        _ = kk_mutable_map_put(destRaw, kk_pair_first(pair), kk_pair_second(pair))
        return true
    }
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }
    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

@_cdecl("kk_sequence_associateByTo")
public func kk_sequence_associateByTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMapBox(from: destRaw) != nil else {
        invalidContainerPanic(#function, "map")
    }
    var traversalState: SequenceTraversalState?
    var didThrow = false
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        _ = kk_mutable_map_put(destRaw, maybeUnbox(key), elem)
        return true
    }
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }
    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

@_cdecl("kk_sequence_associateWithTo")
public func kk_sequence_associateWithTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeMapBox(from: destRaw) != nil else {
        invalidContainerPanic(#function, "map")
    }
    var traversalState: SequenceTraversalState?
    var didThrow = false
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let value = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        _ = kk_mutable_map_put(destRaw, elem, maybeUnbox(value))
        return true
    }
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }
    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

@_cdecl("kk_sequence_groupByTo")
public func kk_sequence_groupByTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex: [RuntimeElementKey: Int] = [:]
    var cachedLists: [Int: RuntimeListBox] = [:]
    for (index, key) in dest.keys.enumerated() {
        keyIndex[RuntimeElementKey(value: key)] = index
        if index < dest.values.count, let existingList = runtimeListBox(from: dest.values[index]) {
            cachedLists[index] = existingList
        }
    }

    var traversalState: SequenceTraversalState?
    var didThrow = false
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let index = keyIndex[normalizedKey] {
            if let existingList = cachedLists[index] {
                existingList.elements.append(elem)
            } else {
                guard index < dest.values.count,
                      let existingList = runtimeListBox(from: dest.values[index])
                else {
                    invalidContainerPanic(#function, "MutableList")
                }
                cachedLists[index] = existingList
                existingList.elements.append(elem)
            }
        } else {
            let newIndex = dest.keys.count
            let newList = RuntimeListBox(elements: [elem])
            dest.keys.append(normalizedKey.value)
            dest.values.append(registerRuntimeObject(newList))
            keyIndex[normalizedKey] = newIndex
            cachedLists[newIndex] = newList
        }
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

@_cdecl("kk_sequence_minByOrNull")
public func kk_sequence_minByOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestElement: Int?
    var bestSelector: Int?
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestSelector {
                if runtimeCompareValues(normalizedSelector, current) < 0 {
                    bestSelector = normalizedSelector
                    bestElement = elem
                }
            } else {
                bestSelector = normalizedSelector
                bestElement = elem
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestSelector {
                if runtimeCompareValues(normalizedSelector, current) < 0 {
                    bestSelector = normalizedSelector
                    bestElement = elem
                }
            } else {
                bestSelector = normalizedSelector
                bestElement = elem
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    return bestElement ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_maxByOrNull")
public func kk_sequence_maxByOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestElement: Int?
    var bestSelector: Int?
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestSelector {
                if runtimeCompareValues(normalizedSelector, current) > 0 {
                    bestSelector = normalizedSelector
                    bestElement = elem
                }
            } else {
                bestSelector = normalizedSelector
                bestElement = elem
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestSelector {
                if runtimeCompareValues(normalizedSelector, current) > 0 {
                    bestSelector = normalizedSelector
                    bestElement = elem
                }
            } else {
                bestSelector = normalizedSelector
                bestElement = elem
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    return bestElement ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_minOf")
public func kk_sequence_minOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestValue: Int?
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestValue {
                if runtimeCompareValues(normalizedSelector, current) < 0 {
                    bestValue = normalizedSelector
                }
            } else {
                bestValue = normalizedSelector
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestValue {
                if runtimeCompareValues(normalizedSelector, current) < 0 {
                    bestValue = normalizedSelector
                }
            } else {
                bestValue = normalizedSelector
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    guard let bestValue else {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
        return runtimeNullSentinelInt
    }
    return bestValue
}

@_cdecl("kk_sequence_maxOf")
public func kk_sequence_maxOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestValue: Int?
    var traversalState: SequenceTraversalState?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown) { elem in
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestValue {
                if runtimeCompareValues(normalizedSelector, current) > 0 {
                    bestValue = normalizedSelector
                }
            } else {
                bestValue = normalizedSelector
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let selector = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeNullSentinelInt
            }
            let normalizedSelector = maybeUnbox(selector)
            if let current = bestValue {
                if runtimeCompareValues(normalizedSelector, current) > 0 {
                    bestValue = normalizedSelector
                }
            } else {
                bestValue = normalizedSelector
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    guard let bestValue else {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
        return runtimeNullSentinelInt
    }
    return bestValue
}

// MARK: - Sequence Operations: chunked/windowed/onEach (STDLIB-276)

@_cdecl("kk_sequence_chunked")
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

@_cdecl("kk_sequence_chunked_transform")
public func kk_sequence_chunked_transform(
    _ seqRaw: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let chunksRaw = kk_sequence_chunked(seqRaw, size)
    let chunks = runtimeSequenceSourceElementsOrPanic(from: chunksRaw, caller: #function)
    var results: [Int] = []
    results.reserveCapacity(chunks.count)
    for chunkRaw in chunks {
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
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

@_cdecl("kk_sequence_windowed")
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

@_cdecl("kk_sequence_windowed_transform")
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
        let transformed = runtimeInvokeCollectionLambda1(
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
    var collected: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            collected.append(elem)
            return true
        }
    } else {
        collected = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(collected)))
}

@_cdecl("kk_sequence_toMap")
public func kk_sequence_toMap(_ seqRaw: Int) -> Int {
    var collected: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            collected.append(elem)
            return true
        }
    } else {
        collected = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
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
        let isObjectPointer = runtimeStorage.withLock { state in
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
    var best: Int? = nil
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

@_cdecl("kk_sequence_minOrNull")
public func kk_sequence_minOrNull(_ seqRaw: Int) -> Int {
    var best: Int? = nil
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
    let lhsElements: [Int]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        lhsElements = evaluateSequence(seq)
    } else if let list = runtimeListBox(from: seqRaw) {
        lhsElements = list.elements
    } else if let array = runtimeArrayBox(from: seqRaw) {
        lhsElements = array.elements
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_plus received invalid LHS collection handle")
    }
    let rhsElements: [Int]
    if let seq = runtimeSequenceBox(from: otherRaw) {
        rhsElements = evaluateSequence(seq)
    } else if let list = runtimeListBox(from: otherRaw) {
        rhsElements = list.elements
    } else if let array = runtimeArrayBox(from: otherRaw) {
        rhsElements = array.elements
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_plus received invalid RHS collection handle (the compiler must wrap single elements via kk_sequence_of_single)")
    }
    // Single-allocation concatenation: create an array with the exact
    // final capacity up front so there are no intermediate reallocations
    // or copy-on-write copies.
    let totalCount = lhsElements.count + rhsElements.count
    let combined = Array<Int>(unsafeUninitializedCapacity: totalCount) { buffer, initializedCount in
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
    let elements: [Int]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        elements = evaluateSequence(seq)
    } else if let list = runtimeListBox(from: seqRaw) {
        elements = list.elements
    } else if let array = runtimeArrayBox(from: seqRaw) {
        elements = array.elements
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_minus received invalid LHS collection handle")
    }
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
