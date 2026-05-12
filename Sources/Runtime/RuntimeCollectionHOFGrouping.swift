import Foundation

/// `Grouping` runtime helpers (STDLIB-285/286).
///
/// Split out from `RuntimeCollectionHOF.swift`.

// MARK: - Grouping (STDLIB-285/286)

private func runtimeGroupingBox(from rawValue: Int) -> RuntimeGroupingBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeGroupingBox.self)
}

private func runtimeGroupingKeyIndex(from dest: RuntimeMapBox) -> [RuntimeElementKey: Int] {
    var keyIndex: [RuntimeElementKey: Int] = [:]
    for (index, key) in dest.keys.enumerated() {
        keyIndex[RuntimeElementKey(value: key)] = index
    }
    return keyIndex
}

@discardableResult
private func runtimeGroupingMapInsertOrUpdate(
    dest: RuntimeMapBox,
    keyIndex: inout [RuntimeElementKey: Int],
    key: RuntimeElementKey,
    value: Int
) -> Int {
    if let index = keyIndex[key] {
        dest.values[index] = value
        return index
    }
    let newIndex = dest.keys.count
    dest.keys.append(key.value)
    dest.values.append(value)
    keyIndex[key] = newIndex
    return newIndex
}

/// `list.groupingBy { keySelector }` — creates a RuntimeGroupingBox capturing the source and key selector.
@_cdecl("kk_list_groupingBy")
public func kk_list_groupingBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return registerRuntimeObject(RuntimeGroupingBox(
        sourceElements: list.elements,
        keyFnPtr: fnPtr,
        keyClosureRaw: closureRaw
    ))
}

/// `grouping.eachCount()` — counts elements per key, returns Map<K, Int>.
@_cdecl("kk_grouping_eachCount")
public func kk_grouping_eachCount(_ groupingRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    var keys: [Int] = []
    var counts: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]  // normalizedKey -> index (value-based lookup)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let idx = keyIndex[normalizedKey] {
            counts[idx] += 1
        } else {
            let newIdx = keys.count
            keyIndex[normalizedKey] = newIdx
            keys.append(normalizedKey.value)
            counts.append(1)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: counts.map { kk_box_int($0) }))
}

/// `grouping.eachCountTo(destination)` — counts elements per key into a destination map.
@_cdecl("kk_grouping_eachCountTo")
public func kk_grouping_eachCountTo(
    _ groupingRaw: Int,
    _ destRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex: [RuntimeElementKey: Int] = [:]
    keyIndex.reserveCapacity(dest.keys.count)
    for (index, key) in dest.keys.enumerated() {
        keyIndex[RuntimeElementKey(value: key)] = index
    }
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let index = keyIndex[normalizedKey] {
            let currentCount: Int
            if index < dest.values.count {
                let currentValue = dest.values[index]
                currentCount = currentValue == runtimeNullSentinelInt ? 0 : maybeUnbox(currentValue)
            } else {
                currentCount = 0
            }
            let updatedCount = currentCount + 1
            if index < dest.values.count {
                dest.values[index] = kk_box_int(updatedCount)
            } else {
                dest.values.append(kk_box_int(updatedCount))
            }
        } else {
            let newIndex = dest.keys.count
            keyIndex[normalizedKey] = newIndex
            dest.keys.append(normalizedKey.value)
            dest.values.append(kk_box_int(1))
        }
    }
    return destRaw
}

/// `grouping.fold(initial) { acc, element -> ... }` — folds per key, returns Map<K, R>.
@_cdecl("kk_grouping_fold")
public func kk_grouping_fold(
    _ groupingRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    var keys: [Int] = []
    var accumulators: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]  // normalizedKey -> index (value-based lookup)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let idx = keyIndex[normalizedKey] {
            var thrown2 = 0
            accumulators[idx] = maybeUnbox(runtimeInvokeCollectionLambda2(
                fnPtr: fnPtr, closureRaw: closureRaw,
                lhs: accumulators[idx], rhs: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        } else {
            let newIdx = keys.count
            keyIndex[normalizedKey] = newIdx
            keys.append(normalizedKey.value)
            var thrown2 = 0
            let foldResult = maybeUnbox(runtimeInvokeCollectionLambda2(
                fnPtr: fnPtr, closureRaw: closureRaw,
                lhs: initial, rhs: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
            accumulators.append(foldResult)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: accumulators))
}

/// `grouping.reduceTo(destination) { key, acc, element -> ... }` — reduces per key into a destination map.
/// If the destination already contains a key, its current value is used as the initial accumulator.
@_cdecl("kk_grouping_reduceTo")
public func kk_grouping_reduceTo(
    _ groupingRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let idx = keyIndex[normalizedKey.value] {
            var thrown2 = 0
            let next = maybeUnbox(runtimeInvokeCollectionLambda3(
                fnPtr: fnPtr, closureRaw: closureRaw,
                arg1: normalizedKey.value, arg2: dest.values[idx], arg3: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
            _ = mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: normalizedKey.value, value: next)
        } else {
            _ = mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: normalizedKey.value, value: maybeUnbox(elem))
        }
    }
    return destRaw
}

/// `grouping.aggregate { key, accumulator, element, first -> ... }` — aggregates per key.
@_cdecl("kk_grouping_aggregate")
public func kk_grouping_aggregate(
    _ groupingRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    var keys: [Int] = []
    var accumulators: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let index = keyIndex[normalizedKey] {
            var thrown2 = 0
            let nextValue = runtimeInvokeCollectionLambda4(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                arg1: normalizedKey.value,
                arg2: accumulators[index],
                arg3: elem,
                arg4: 0,
                outThrown: &thrown2
            )
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
            accumulators[index] = maybeUnbox(nextValue)
        } else {
            keyIndex[normalizedKey] = keys.count
            keys.append(normalizedKey.value)
            var thrown2 = 0
            let nextValue = runtimeInvokeCollectionLambda4(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                arg1: normalizedKey.value,
                arg2: runtimeNullSentinelInt,
                arg3: elem,
                arg4: 1,
                outThrown: &thrown2
            )
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
            accumulators.append(maybeUnbox(nextValue))
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: accumulators))
}

/// `grouping.aggregateTo(destination) { key, accumulator, element, first -> ... }` mutates the destination map.
@_cdecl("kk_grouping_aggregateTo")
public func kk_grouping_aggregateTo(
    _ groupingRaw: Int,
    _ destinationRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    guard let destination = runtimeMapBox(from: destinationRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = runtimeGroupingKeyIndex(from: destination)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        let existingIndex = keyIndex[normalizedKey]
        let currentAccumulator = existingIndex.map { destination.values[$0] } ?? runtimeNullSentinelInt
        var thrown2 = 0
        let nextValue = maybeUnbox(runtimeInvokeCollectionLambda4(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: normalizedKey.value,
            arg2: currentAccumulator,
            arg3: elem,
            arg4: existingIndex == nil ? 1 : 0,
            outThrown: &thrown2
        ))
        if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        runtimeGroupingMapInsertOrUpdate(
            dest: destination,
            keyIndex: &keyIndex,
            key: normalizedKey,
            value: nextValue
        )
    }
    return destinationRaw
}

/// `grouping.fold(initialValueSelector) { key, accumulator, element -> ... }` — folds per key, returns Map<K, R>.
/// The initial selector computes the seed accumulator and the operation then
/// runs for the first element as well as subsequent elements.
@_cdecl("kk_grouping_fold_initialValueSelector")
public func kk_grouping_fold_initialValueSelector(
    _ groupingRaw: Int,
    _ initialValueSelectorFnPtr: Int,
    _ initialValueSelectorClosureRaw: Int,
    _ operationFnPtr: Int,
    _ operationClosureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    var keys: [Int] = []
    var accumulators: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]  // normalizedKey -> index (value-based lookup)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let idx = keyIndex[normalizedKey] {
            var thrown2 = 0
            accumulators[idx] = maybeUnbox(runtimeInvokeCollectionLambda3(
                fnPtr: operationFnPtr, closureRaw: operationClosureRaw,
                arg1: keys[idx], arg2: accumulators[idx], arg3: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        } else {
            let newIdx = keys.count
            keyIndex[normalizedKey] = newIdx
            keys.append(normalizedKey.value)
            var thrown2 = 0
            let initialAccumulator = maybeUnbox(runtimeInvokeCollectionLambda2(
                fnPtr: initialValueSelectorFnPtr, closureRaw: initialValueSelectorClosureRaw,
                lhs: normalizedKey.value, rhs: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
            var thrown3 = 0
            let firstAccumulator = maybeUnbox(runtimeInvokeCollectionLambda3(
                fnPtr: operationFnPtr, closureRaw: operationClosureRaw,
                arg1: normalizedKey.value, arg2: initialAccumulator, arg3: elem, outThrown: &thrown3
            ))
            if thrown3 != 0 { return handleCollectionLambdaThrow(thrown3, outThrown) }
            accumulators.append(firstAccumulator)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: accumulators))
}

/// `grouping.foldTo(destination, initialValue) { accumulator, element -> ... }`
/// folds each group into the given destination map, updating entries in place.
@_cdecl("kk_grouping_foldTo")
public func kk_grouping_foldTo(
    _ groupingRaw: Int,
    _ destinationRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    guard let destination = runtimeMapBox(from: destinationRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = runtimeGroupingKeyIndex(from: destination)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))

        let currentAccumulator: Int
        if let index = keyIndex[normalizedKey] {
            currentAccumulator = destination.values[index]
        } else {
            currentAccumulator = initial
        }

        var thrown2 = 0
        let nextAccumulator = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr, closureRaw: closureRaw,
            lhs: currentAccumulator, rhs: elem, outThrown: &thrown2
        ))
        if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        runtimeGroupingMapInsertOrUpdate(
            dest: destination,
            keyIndex: &keyIndex,
            key: normalizedKey,
            value: nextAccumulator
        )
    }
    return destinationRaw
}

/// `grouping.foldTo(destination, initialValueSelector) { key, accumulator, element -> ... }`
/// folds each group into the given destination map, deriving the initial accumulator per key.
@_cdecl("kk_grouping_foldTo_selector")
public func kk_grouping_foldTo_selector(
    _ groupingRaw: Int,
    _ destinationRaw: Int,
    _ initialValueSelectorFnPtr: Int,
    _ initialValueSelectorClosureRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    guard let destination = runtimeMapBox(from: destinationRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = runtimeGroupingKeyIndex(from: destination)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))

        let currentAccumulator: Int
        if let index = keyIndex[normalizedKey] {
            currentAccumulator = destination.values[index]
        } else {
            var thrown2 = 0
            currentAccumulator = maybeUnbox(runtimeInvokeCollectionLambda2(
                fnPtr: initialValueSelectorFnPtr, closureRaw: initialValueSelectorClosureRaw,
                lhs: normalizedKey.value, rhs: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        }

        var thrown3 = 0
        let nextAccumulator = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr, closureRaw: closureRaw,
            arg1: normalizedKey.value, arg2: currentAccumulator, arg3: elem, outThrown: &thrown3
        ))
        if thrown3 != 0 { return handleCollectionLambdaThrow(thrown3, outThrown) }
        runtimeGroupingMapInsertOrUpdate(
            dest: destination,
            keyIndex: &keyIndex,
            key: normalizedKey,
            value: nextAccumulator
        )
    }
    return destinationRaw
}

/// `grouping.reduce { acc, element -> ... }` — reduces per key, returns Map<K, T>.
/// The lambda receives (accumulator, element); the first element of each group becomes the initial accumulator.
/// Keys are indexed via Dictionary for O(1) lookup per element.
@_cdecl("kk_grouping_reduce")
public func kk_grouping_reduce(
    _ groupingRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let grouping = runtimeGroupingBox(from: groupingRaw) else {
        invalidContainerPanic(#function, "grouping")
    }
    var keys: [Int] = []
    var accumulators: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]  // normalizedKey -> index (value-based lookup)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let idx = keyIndex[normalizedKey] {
            var thrown2 = 0
            accumulators[idx] = maybeUnbox(runtimeInvokeCollectionLambda2(
                fnPtr: fnPtr, closureRaw: closureRaw,
                lhs: accumulators[idx], rhs: elem, outThrown: &thrown2
            ))
            if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        } else {
            let newIdx = keys.count
            keyIndex[normalizedKey] = newIdx
            keys.append(normalizedKey.value)
            accumulators.append(elem)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: accumulators))
}
