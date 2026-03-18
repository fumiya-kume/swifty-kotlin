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

private func runtimeSequenceSourceElements(from rawValue: Int) -> [Int]? {
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
        if maybeUnbox(predicateResult) != 0 {
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
        state.takeCounts[stepIndex] = emitted + 1
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
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
    case .source, .builder, .generator:
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
    yield: @escaping (Int) -> Bool
) {
    let transformSteps = seq.steps.filter {
        switch $0 {
        case .source, .builder, .generator:
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
        case .mapStep, .filterStep, .takeStep, .dropStep, .distinctStep, .zipStep, .takeWhileStep, .dropWhileStep, .onEachStep:
            continue
        }
    }
}

/// Convenience wrapper that creates its own `SequenceTraversalState`.
private func runtimeTraverseSequence(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) {
    let state = SequenceTraversalState()
    runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: yield)
}

/// Extracts source elements from a sequence step, if applicable.
private func extractSourceElements(from step: SequenceStepKind) -> [Int]? {
    switch step {
    case let .source(sourceElements): sourceElements
    case let .builder(builderElements): builderElements
    default: nil
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

/// Evaluates the lazy sequence chain and returns the materialized elements.
/// This is the core of lazy semantics: steps are only executed here.
private func evaluateSequence(_ seq: RuntimeSequenceBox) -> [Int] {
    // Find the source elements
    var elements: [Int] = []
    for step in seq.steps {
        if let source = extractSourceElements(from: step) {
            elements = source
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
    }

    // Apply transformation steps in order
    for step in seq.steps {
        switch step {
        case .source, .builder, .generator:
            break
        case let .mapStep(fnPtr, closureRaw):
            elements = applyMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .filterStep(fnPtr, closureRaw):
            elements = applyFilterStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
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
            elements = applyTakeWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .dropWhileStep(fnPtr, closureRaw):
            elements = applyDropWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .onEachStep(fnPtr, closureRaw):
            let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            for elem in elements {
                var thrown = 0
                _ = action(closureRaw, elem, &thrown)
                if thrown != 0 { return [] }
            }
        }
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

@_cdecl("kk_sequence_generate")
public func kk_sequence_generate(_ seed: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.generator(seed: seed, fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var mapped: [Int] = []
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        let normalized = maybeUnbox(result)
        if normalized != runtimeNullSentinelInt {
            mapped.append(normalized)
        }
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: mapped)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_filterNotNull")
public func kk_sequence_filterNotNull(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let filtered = elements.filter { maybeUnbox($0) != runtimeNullSentinelInt }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: filtered)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_mapIndexed")
public func kk_sequence_mapIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        mapped.append(maybeUnbox(result))
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: mapped)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_withIndex")
public func kk_sequence_withIndex(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var pairs: [Int] = []
    pairs.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        pairs.append(kk_pair_new(idx, elem))
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: pairs)])
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence Terminal Operations

@_cdecl("kk_sequence_forEach")
public func kk_sequence_forEach(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    for elem in elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
        }
    }
    return 0
}

@_cdecl("kk_sequence_flatMap")
public func kk_sequence_flatMap(_ seqRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var result: [Int] = []
    for elem in elements {
        var thrown = 0
        let subRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
        }
        if let subList = runtimeListBox(from: subRaw) {
            result.append(contentsOf: subList.elements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq))
        }
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: result)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_to_list")
public func kk_sequence_to_list(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
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
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !found {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
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

// MARK: - Sequence foldIndexed / reduceIndexed (STDLIB-556, STDLIB-557)

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
    let newSeq = RuntimeSequenceBox(steps: newSteps)
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
// NOTE: The compiler resolves the correct Kotlin overload (element vs
// collection) at compile time via sema.bindings.isCollectionExpr, so
// at the runtime level otherRaw in kk_sequence_plus is always a
// collection handle (sequence/list/array).  The single-element overload
// is handled by the compiler emitting the element wrapped in a
// single-element sequence before calling this function.

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
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_plus received invalid LHS sequence handle")
    }
    let rhsElements: [Int]
    if let seq = runtimeSequenceBox(from: otherRaw) {
        rhsElements = evaluateSequence(seq)
    } else if let list = runtimeListBox(from: otherRaw) {
        rhsElements = list.elements
    } else if let array = runtimeArrayBox(from: otherRaw) {
        rhsElements = array.elements
    } else {
        // Single element case: otherRaw is a plain value, not a collection.
        // This path is kept as a defensive fallback; the compiler should
        // normally wrap single elements before reaching here.
        rhsElements = [otherRaw]
    }
    var combined = lhsElements
    combined.reserveCapacity(lhsElements.count + rhsElements.count)
    combined.append(contentsOf: rhsElements)
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: combined)])
    return registerRuntimeObject(newSeq)
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
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_minus received invalid sequence handle")
    }
    var result = elements
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

@_cdecl("kk_sequence_builder_yield")
public func kk_sequence_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    if let builder = runtimeSequenceBuilderBox(from: builderRaw) {
        builder.elements.append(value)
        return 0
    }
    // STDLIB-331/564: yield() is shared across sequence/iterator builders.
    // When the builder handle is a RuntimeIteratorBuilderBox, delegate there.
    if let iterBuilder = runtimeIteratorBuilderBox(from: builderRaw) {
        iterBuilder.elements.append(value)
        return 0
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yield received invalid builder handle")
}

// MARK: - yieldAll(iterable) (STDLIB-553)

@_cdecl("kk_sequence_builder_yieldAll")
public func kk_sequence_builder_yieldAll(_ builderRaw: Int, _ collectionRaw: Int) -> Int {
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
public func kk_sequence_builder_build(_ fnPtr: Int) -> Int {
    let builder = RuntimeSequenceBuilderBox()
    let builderHandle = registerRuntimeObject(builder)

    var thrown = 0
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: builderHandle, outThrown: &thrown)

    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
    }

    let seq = RuntimeSequenceBox(steps: [.builder(elements: builder.elements)])
    return registerRuntimeObject(seq)
}

// MARK: - Iterator Builder (iterator { yield(x) }) (STDLIB-331/564)

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}

@_cdecl("kk_iterator_builder_build")
public func kk_iterator_builder_build(_ fnPtr: Int) -> Int {
    let builder = RuntimeIteratorBuilderBox()
    let builderHandle = registerRuntimeObject(builder)

    var thrown = 0
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: builderHandle, outThrown: &thrown)

    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: iterator lambda threw but no outThrown available")
    }

    // The builder now holds all yielded elements; return it directly as
    // the iterator handle.  hasNext / next operate on the same box.
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
    builder.elements.append(value)
    return 0
}

@_cdecl("kk_iterator_builder_hasNext")
public func kk_iterator_builder_hasNext(_ iterRaw: Int) -> Int {
    // Support both RuntimeIteratorBuilderBox and RuntimeListIteratorBox
    // for backwards compatibility with older lowering paths.
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.index < iter.elements.count ? 1 : 0
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        return iter.index < iter.elements.count ? 1 : 0
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_iterator_builder_hasNext received invalid iterator handle")
}

@_cdecl("kk_iterator_builder_next")
public func kk_iterator_builder_next(_ iterRaw: Int) -> Int {
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        guard iter.index < iter.elements.count else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.elements[iter.index]
        iter.index += 1
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
