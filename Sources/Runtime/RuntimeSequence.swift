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
private func applyMapStep(_ elements: [Int], fnPtr: Int) -> [Int] {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let result = lambda(0, elem, &thrown)
        if thrown != 0 { return [] }
        mapped.append(maybeUnbox(result))
    }
    return mapped
}

/// Applies a filter transformation to elements using the given function pointer.
/// Lambda signature: (closureRaw, elem, outThrown) -> Int (same as list HOFs).
private func applyFilterStep(_ elements: [Int], fnPtr: Int) -> [Int] {
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    for elem in elements {
        var thrown = 0
        let result = predicate(0, elem, &thrown)
        if thrown != 0 { return [] }
        if maybeUnbox(result) != 0 {
            filtered.append(elem)
        }
    }
    return filtered
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
    }

    // Apply transformation steps in order
    for step in seq.steps {
        switch step {
        case .source, .builder:
            break
        case let .mapStep(fnPtr):
            elements = applyMapStep(elements, fnPtr: fnPtr)
        case let .filterStep(fnPtr):
            elements = applyFilterStep(elements, fnPtr: fnPtr)
        case let .takeStep(count):
            if count >= 0, count < elements.count {
                elements = Array(elements.prefix(count))
            }
        }
    }

    return elements
}

// maybeUnbox() is defined in RuntimeCollectionHelpers.swift

// MARK: - Sequence Factory Functions

@_cdecl("kk_sequence_from_list")
public func kk_sequence_from_list(_ listRaw: Int) -> Int {
    let elements = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else {
        [Int]()
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: elements)])
    return registerRuntimeObject(seq)
}

// MARK: - Sequence Intermediate Operations (Lazy)

@_cdecl("kk_sequence_map")
public func kk_sequence_map(_ seqRaw: Int, _ fnPtr: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let newSeq = RuntimeSequenceBox(steps: [.mapStep(fnPtr: fnPtr)])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.mapStep(fnPtr: fnPtr))
    let newSeq = RuntimeSequenceBox(steps: newSteps)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_filter")
public func kk_sequence_filter(_ seqRaw: Int, _ fnPtr: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let newSeq = RuntimeSequenceBox(steps: [.filterStep(fnPtr: fnPtr)])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.filterStep(fnPtr: fnPtr))
    let newSeq = RuntimeSequenceBox(steps: newSteps)
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_take")
public func kk_sequence_take(_ seqRaw: Int, _ count: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let newSeq = RuntimeSequenceBox(steps: [.takeStep(count: count)])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.takeStep(count: count))
    let newSeq = RuntimeSequenceBox(steps: newSteps)
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence Terminal Operations

@_cdecl("kk_sequence_to_list")
public func kk_sequence_to_list(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let emptyList = RuntimeListBox(elements: [])
        return registerRuntimeObject(emptyList)
    }
    let elements = evaluateSequence(seq)
    let list = RuntimeListBox(elements: elements)
    return registerRuntimeObject(list)
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
        return 0
    }
    builder.elements.append(value)
    return 0
}

@_cdecl("kk_sequence_builder_build")
public func kk_sequence_builder_build(_ fnPtr: Int) -> Int {
    let builder = RuntimeSequenceBuilderBox()
    let builderHandle = registerRuntimeObject(builder)

    let builderBlock = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = builderBlock(builderHandle, &thrown)

    let seq = RuntimeSequenceBox(steps: [.builder(elements: builder.elements)])
    return registerRuntimeObject(seq)
}
