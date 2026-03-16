import Foundation

// MARK: - Sequence Functions (STDLIB-003)

private func runtimeSequenceBox(from rawValue: Int) -> RuntimeSequenceBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSequenceBox.self)
}

private func runtimeSequenceBuilderBox(from rawValue: Int) -> RuntimeSequenceBuilderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSequenceBuilderBox.self)
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
    var takeCounts: [Int: Int] = [:]
    var dropCounts: [Int: Int] = [:]
    var distinctSeen: [Int: [Int]] = [:]
    var zipIndices: [Int: Int] = [:]
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

private func runtimeTraverseSequence(
    _ seq: RuntimeSequenceBox,
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
    let state = SequenceTraversalState()
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

            let hardLimit = 100_000
            var generatedCount = 1
            while generatedCount < hardLimit, !state.stop {
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
            return
        case .mapStep, .filterStep, .takeStep, .dropStep, .distinctStep, .zipStep, .takeWhileStep, .dropWhileStep:
            continue
        }
    }
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
            outThrown?.pointee = thrown
            return mapped
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
            outThrown?.pointee = thrown
            return filtered
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
            outThrown?.pointee = thrown
            return result
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
                outThrown?.pointee = thrown
                return result
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
            let hardLimit = 100_000
            while generated.count < hardLimit {
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
            var seen = Set<Int>()
            elements = elements.filter { seen.insert($0).inserted }
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
            return 0
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
            break
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
        outThrown?.pointee = runtimeAllocateThrowable(message: "UnsupportedOperationException: Empty sequence can't be reduced.")
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

// MARK: - Sequence Builder (sequence { yield(x) })

@_cdecl("kk_sequence_builder_create")
public func kk_sequence_builder_create() -> Int {
    let builder = RuntimeSequenceBuilderBox()
    return registerRuntimeObject(builder)
}

@_cdecl("kk_sequence_builder_yield")
public func kk_sequence_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    guard let builder = runtimeSequenceBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_builder_yield received invalid builder handle")
    }
    builder.elements.append(value)
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
