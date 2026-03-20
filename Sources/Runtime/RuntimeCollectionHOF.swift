import Foundation

private let indexedValueRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.IndexedValue".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

private func runtimeIndexedValueNew(index: Int, value: Int) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(first: index, second: value))
    runtimeRegisterObjectType(rawValue: raw, classID: indexedValueRuntimeTypeID)
    return raw
}

private func handleCollectionLambdaThrow(_ thrown: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown = outThrown {
        outThrown.pointee = thrown
        return runtimeExceptionCaughtSentinel
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in collection HOF lambda. outThrown was nil.")
    }
}

/// Panics when a collection HOF receives an invalid container handle.
/// Replaces silent fallbacks (return empty list/map/0/false) that mask runtime corruption.
private func invalidContainerPanic(_ caller: StaticString, _ kind: StaticString) -> Never {
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid \(kind) handle")
}

// MARK: - Closeable.use {} (STDLIB-250)

/// Calls `close()` on a Closeable resource via vtable dispatch (slot 0).
/// The vtable function pointer follows the standard compiler ABI:
///   (self, outThrown) -> Int
/// Returns 0 on success, or the thrown exception handle if close() threw.
private func runtimeCloseableClose(_ resourceRaw: Int) -> Int {
    let closeFnPtr = kk_vtable_lookup(resourceRaw, 0)
    guard closeFnPtr != 0 else { return 0 }
    let closeFn = unsafeBitCast(closeFnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var closeThrown = 0
    _ = closeFn(resourceRaw, &closeThrown)
    return closeThrown
}

/// `resource.use { block }` — calls the block with the resource, then calls
/// close() on the resource in a finally-style manner (regardless of whether
/// the block threw), matching Kotlin's `use {}` semantics.
/// Runtime signature: kk_use(resourceRaw, fnPtr, closureRaw, outThrown) -> R
@_cdecl("kk_use")
public func kk_use(_ resourceRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    // Call the lambda with the resource as its argument
    var blockThrown = 0
    let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: resourceRaw, outThrown: &blockThrown)

    // Always close the resource (finally semantics)
    let closeThrown = runtimeCloseableClose(resourceRaw)

    // Kotlin use {} exception semantics:
    // 1. If block threw and close() also threw, propagate the block exception
    //    (close exception is suppressed — mirrors Kotlin's addSuppressed behavior).
    // 2. If only block threw, propagate the block exception.
    // 3. If only close() threw, propagate the close exception.
    if blockThrown != 0 {
        // Block threw — propagate the block exception (case 1 & 2).
        // Note: close exception, if any, is suppressed.
        return handleCollectionLambdaThrow(blockThrown, outThrown)
    }
    if closeThrown != 0 {
        // Only close() threw (case 3) — propagate it.
        return handleCollectionLambdaThrow(closeThrown, outThrown)
    }
    return result
}

// MARK: - List getOrElse (STDLIB-212)

@_cdecl("kk_list_getOrElse")
public func kk_list_getOrElse(_ listRaw: Int, _ index: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    if list.elements.indices.contains(index) {
        return list.elements[index]
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, index, &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_map")
public func kk_list_map(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_filter")
public func kk_list_filter(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var filtered: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_mapNotNull")
public func kk_list_mapNotNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var mapped: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalized = maybeUnbox(result)
        if normalized != runtimeNullSentinelInt {
            mapped.append(normalized)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_filterNotNull")
public func kk_list_filterNotNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    let filtered = list.elements.filter { maybeUnbox($0) != runtimeNullSentinelInt }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_forEach")
public func kk_list_forEach(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for elem in list.elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_map_forEach")
public func kk_map_forEach(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: kk_pair_new(key, value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_map_map")
public func kk_map_map(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mapped: [Int] = []
    mapped.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: kk_pair_new(key, value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_map_filter")
public func kk_map_filter(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: kk_pair_new(key, value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_count")
public func kk_map_count(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_map_any")
public func kk_map_any(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_map_all")
public func kk_map_all(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_map_none")
public func kk_map_none(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_map_getOrElse")
public func kk_map_getOrElse(_ mapRaw: Int, _ key: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
        if idx < map.values.count { return map.values[idx] }
        break
    }
    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_mutable_map_getOrPut")
public func kk_mutable_map_getOrPut(_ mapRaw: Int, _ key: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
        if idx < map.values.count {
            let existing = map.values[idx]
            if existing != runtimeNullSentinelInt {
                return existing
            }
            var thrown = 0
            let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
            if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
            map.values[idx] = result
            return result
        }
        break
    }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    map.keys.append(key)
    map.values.append(result)
    return result
}

@_cdecl("kk_map_mapValues")
public func kk_map_mapValues(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mappedValues: [Int] = []
    mappedValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: kk_pair_new(key, value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mappedValues.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: map.keys, values: mappedValues)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_mapKeys")
public func kk_map_mapKeys(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mappedKeys: [Int] = []
    mappedKeys.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: kk_pair_new(key, value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mappedKeys.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: mappedKeys, values: map.values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_toList")
public func kk_map_toList(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var pairs: [Int] = []
    pairs.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        pairs.append(kk_pair_new(key, value))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_map_flatMap")
public func kk_map_flatMap(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let subListRaw = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_map_maxByOrNull")
public func kk_map_maxByOrNull(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let pairCount = min(map.keys.count, map.values.count)
    guard pairCount > 0 else {
        return runtimeNullSentinelInt
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestKey = map.keys[0]
    var bestValue = map.values[0]
    var thrown = 0
    var bestSelector = lambda(closureRaw, kk_pair_new(bestKey, bestValue), &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for idx in 1 ..< pairCount {
        let key = map.keys[idx]
        let value = map.values[idx]
        thrown = 0
        let selector = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(selector, bestSelector) > 0 {
            bestKey = key
            bestValue = value
            bestSelector = selector
        }
    }
    return kk_pair_new(bestKey, bestValue)
}

@_cdecl("kk_map_minByOrNull")
public func kk_map_minByOrNull(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let pairCount = min(map.keys.count, map.values.count)
    guard pairCount > 0 else {
        return runtimeNullSentinelInt
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestKey = map.keys[0]
    var bestValue = map.values[0]
    var thrown = 0
    var bestSelector = lambda(closureRaw, kk_pair_new(bestKey, bestValue), &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for idx in 1 ..< pairCount {
        let key = map.keys[idx]
        let value = map.values[idx]
        thrown = 0
        let selector = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(selector, bestSelector) < 0 {
            bestKey = key
            bestValue = value
            bestSelector = selector
        }
    }
    return kk_pair_new(bestKey, bestValue)
}

@_cdecl("kk_list_flatMap")
public func kk_list_flatMap(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var result: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let subListRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_any")
public func kk_list_any(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 0 : 1
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_list_none")
public func kk_list_none(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 1 : 0
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_list_all")
public func kk_list_all(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_list_fold")
public func kk_list_fold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var acc = initial
    for elem in list.elements {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: elem, outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_list_reduce")
public func kk_list_reduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Empty collection can't be reduced."), outThrown)
    }
    var acc = list.elements[0]
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: list.elements[idx], outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

// MARK: - List scan / runningFold / runningReduce (STDLIB-442)

@_cdecl("kk_list_scan")
public func kk_list_scan(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var acc = maybeUnbox(initial)
    var results: [Int] = []
    results.reserveCapacity(list.elements.count + 1)
    results.append(acc)
    for elem in list.elements {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: elem, outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_list_runningFold")
public func kk_list_runningFold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_list_scan(listRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_list_runningReduce")
public func kk_list_runningReduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Empty collection can't be reduced."), outThrown)
    }
    var acc = maybeUnbox(list.elements[0])
    var results: [Int] = []
    results.reserveCapacity(list.elements.count)
    results.append(acc)
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: list.elements[idx], outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// MARK: - List reduceOrNull / scanReduce (STDLIB-526..530)

@_cdecl("kk_list_reduceOrNull")
public func kk_list_reduceOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var acc = maybeUnbox(list.elements[0])
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: list.elements[idx], outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

// Deprecated: kk_list_scanReduce is a deprecated alias for kk_list_runningReduce.
// Kotlin renamed scanReduce to runningReduce; this entrypoint is kept for ABI compatibility.
@_cdecl("kk_list_scanReduce")
public func kk_list_scanReduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_list_runningReduce(listRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_list_groupBy")
public func kk_list_groupBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [Int: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        if let grpIdx = keyToIndex[unboxedKey] {
            groupElements[grpIdx].append(elem)
        } else {
            let newIndex = groupKeys.count
            keyToIndex[unboxedKey] = newIndex
            groupKeys.append(unboxedKey)
            groupElements.append([elem])
        }
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}

// MARK: - groupBy with value transform (two-lambda variant)
// Kotlin: list.groupBy(keySelector, valueTransform) -> Map<K, List<V>>

@_cdecl("kk_list_groupByTransform")
public func kk_list_groupByTransform(_ listRaw: Int, _ keyFnPtr: Int, _ keyClosureRaw: Int, _ valueFnPtr: Int, _ valueClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [Int: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: keyFnPtr, closureRaw: keyClosureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        var thrown2 = 0
        let transformedValue = runtimeInvokeCollectionLambda1(fnPtr: valueFnPtr, closureRaw: valueClosureRaw, value: elem, outThrown: &thrown2)
        if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        if let grpIdx = keyToIndex[unboxedKey] {
            groupElements[grpIdx].append(transformedValue)
        } else {
            let newIndex = groupKeys.count
            keyToIndex[unboxedKey] = newIndex
            groupKeys.append(unboxedKey)
            groupElements.append([transformedValue])
        }
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}

@_cdecl("kk_list_sortedBy")
public func kk_list_sortedBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var indexed: [(offset: Int, element: Int, key: Int)] = []
    indexed.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        indexed.append((offset: indexed.count, element: elem, key: key))
    }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.key, rhs.key)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map(\.element)))
}

@_cdecl("kk_list_count")
public func kk_list_count(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.count
    }
    var count = 0
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_list_first")
public func kk_list_first(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return list.elements[0]
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return handleCollectionLambdaThrow(outThrown!.pointee, outThrown)
}

@_cdecl("kk_list_last")
public func kk_list_last(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return list.elements.last!
    }
    var lastMatch: Int?
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { lastMatch = elem }
    }
    if let match = lastMatch { return match }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return handleCollectionLambdaThrow(outThrown!.pointee, outThrown)
}

@_cdecl("kk_list_find")
public func kk_list_find(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.first ?? runtimeNullSentinelInt
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_list_associateBy")
public func kk_list_associateBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(maybeUnbox(key))
        values.append(elem)
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associateWith")
public func kk_list_associateWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(elem)
        values.append(maybeUnbox(value))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associate")
public func kk_list_associate(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let pair = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(kk_pair_first(pair))
        values.append(kk_pair_second(pair))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

// MARK: - STDLIB-535/536/537: associateByTo / associateWithTo / groupByTo

/// Builds a key-index dictionary from existing map keys for O(1) lookups.
/// Shared helper to avoid duplicating key-index precomputation across *To functions.
private func buildKeyIndex(from dest: RuntimeMapBox) -> [Int: Int] {
    var keyIndex: [Int: Int] = [:]
    for (i, k) in dest.keys.enumerated() {
        keyIndex[k] = i
    }
    return keyIndex
}

/// Inserts or updates a key-value pair in a destination map, maintaining the key index.
/// Returns the updated key index.
@discardableResult
private func mapInsertOrUpdate(
    dest: RuntimeMapBox,
    keyIndex: inout [Int: Int],
    key: Int,
    value: Int
) -> Int {
    if let index = keyIndex[key] {
        dest.values[index] = value
        return index
    } else {
        let newIndex = dest.keys.count
        dest.keys.append(key)
        dest.values.append(value)
        keyIndex[key] = newIndex
        return newIndex
    }
}

@_cdecl("kk_list_associateByTo")
public func kk_list_associateByTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: unboxedKey, value: elem)
    }
    return destRaw
}

@_cdecl("kk_list_associateWithTo")
public func kk_list_associateWithTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    for elem in list.elements {
        var thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(elem)
        let unboxedValue = maybeUnbox(value)
        mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: unboxedKey, value: unboxedValue)
    }
    return destRaw
}

@_cdecl("kk_list_groupByTo")
public func kk_list_groupByTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    var cachedLists: [Int: RuntimeListBox] = [:]
    for (i, _) in dest.keys.enumerated() {
        if let existingList = runtimeListBox(from: dest.values[i]) {
            cachedLists[i] = existingList
        }
    }
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        if let index = keyIndex[unboxedKey] {
            if let existingList = cachedLists[index] {
                existingList.elements.append(elem)
            } else {
                guard let existingList = runtimeListBox(from: dest.values[index]) else {
                    invalidContainerPanic(#function, "MutableList")
                }
                cachedLists[index] = existingList
                existingList.elements.append(elem)
            }
        } else {
            let newIndex = dest.keys.count
            let newList = RuntimeListBox(elements: [elem])
            dest.keys.append(unboxedKey)
            dest.values.append(registerRuntimeObject(newList))
            keyIndex[unboxedKey] = newIndex
            cachedLists[newIndex] = newList
        }
    }
    return destRaw
}

@_cdecl("kk_list_zip")
public func kk_list_zip(_ listRaw: Int, _ otherRaw: Int) -> Int {
    guard let lhsBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard let rhsBox = runtimeListBox(from: otherRaw) else { invalidContainerPanic(#function, "list") }
    let lhs = lhsBox.elements
    let rhs = rhsBox.elements
    let count = min(lhs.count, rhs.count)
    var pairs: [Int] = []
    pairs.reserveCapacity(count)
    for index in 0 ..< count {
        pairs.append(kk_pair_new(lhs[index], rhs[index]))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_list_unzip")
public func kk_list_unzip(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
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

@_cdecl("kk_list_withIndex")
public func kk_list_withIndex(_ listRaw: Int) -> Int {
    let box = RuntimeIndexingIterableBox(listRaw: listRaw)
    return registerRuntimeObject(box)
}

@_cdecl("kk_list_forEachIndexed")
public func kk_list_forEachIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        // Pass index as raw Int (Kotlin primitive); elem stays boxed per ABI.
        _ = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_list_mapIndexed")
public func kk_list_mapIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        // Pass index as raw Int (Kotlin primitive); elem stays boxed per ABI.
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_sumOf")
public func kk_list_sumOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var total = 0
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_list_maxOrNull")
public func kk_list_maxOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let first = list.elements.first else {
        return runtimeNullSentinelInt
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) > 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_minOrNull")
public func kk_list_minOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let first = list.elements.first else {
        return runtimeNullSentinelInt
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) < 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_maxByOrNull")
public func kk_list_maxByOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) > 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_minByOrNull")
public func kk_list_minByOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) < 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_maxOfOrNull")
public func kk_list_maxOfOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[0], outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(value, bestValue) > 0 {
            bestValue = value
        }
    }
    return bestValue
}

@_cdecl("kk_list_minOfOrNull")
public func kk_list_minOfOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[0], outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(value, bestValue) < 0 {
            bestValue = value
        }
    }
    return bestValue
}

@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_reversed")
public func kk_list_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.reversed())))
}

@_cdecl("kk_list_as_reversed")
public func kk_list_as_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return registerRuntimeObject(RuntimeListBox(reversedViewOf: listBox))
}

@_cdecl("kk_list_sorted")
public func kk_list_sorted(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_distinct")
public func kk_list_distinct(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

/// Returns a list containing only elements with distinct keys returned by the selector.
///
/// Key deduplication uses `RuntimeElementKey` which delegates to
/// `kk_any_hashCode` / `runtimeValuesEqual` for structural equality,
/// so data-class and other reference-typed keys compare by value.
@_cdecl("kk_list_distinctBy")
public func kk_list_distinctBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var seenKeys = Set<RuntimeElementKey>()
    seenKeys.reserveCapacity(list.elements.count)
    var result: [Int] = []
    result.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if seenKeys.insert(RuntimeElementKey(value: key)).inserted {
            result.append(elem)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_shuffled")
public func kk_list_shuffled(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let shuffled = elements.shuffled()
    return registerRuntimeObject(RuntimeListBox(elements: shuffled))
}

// MARK: - shuffled(random: Random) overload (STDLIB-531)

@_cdecl("kk_list_shuffled_random")
public func kk_list_shuffled_random(_ listRaw: Int, _ randomRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var elements = listBox.elements
    // Fisher-Yates shuffle delegating to kk_random_nextInt_until.
    // NOTE: kk_random_nextInt_until currently ignores the Random instance
    // and uses Swift's SystemRandomNumberGenerator, so seeded Random
    // instances (e.g. Random(42)) do NOT yet produce deterministic results.
    // The randomRaw parameter is threaded through so that adding seeded
    // RNG support requires changes only in RuntimeRandom.swift.
    guard elements.count > 1 else {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    for i in stride(from: elements.count - 1, through: 1, by: -1) {
        let j = kk_random_nextInt_until(randomRaw, i + 1, nil)
        elements.swapAt(i, j)
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_list_random")
public func kk_list_random(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "NoSuchElementException: List is empty."), outThrown)
    }
    return list.elements.randomElement()!
}

@_cdecl("kk_list_randomOrNull")
public func kk_list_randomOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let element = list.elements.randomElement() else {
        return runtimeNullSentinelInt
    }
    return element
}

@_cdecl("kk_list_flatten")
public func kk_list_flatten(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    var result: [Int] = []
    for subListRaw in elements {
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_chunked")
public func kk_list_chunked(_ listRaw: Int, _ size: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clampedSize = max(1, size)
    var chunks: [Int] = []
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        let chunk = Array(elements[i ..< end])
        chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunk)))
        i = end
    }
    return registerRuntimeObject(RuntimeListBox(elements: chunks))
}

@_cdecl("kk_list_chunked_transform")
public func kk_list_chunked_transform(_ listRaw: Int, _ size: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clampedSize = max(1, size)
    let estimatedChunks = elements.isEmpty ? 0 : (elements.count + clampedSize - 1) / clampedSize
    var result: [Int] = []
    result.reserveCapacity(estimatedChunks)
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        let chunk = Array(elements[i ..< end])
        let chunkList = registerRuntimeObject(RuntimeListBox(elements: chunk))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: chunkList, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        result.append(maybeUnbox(transformed))
        i = end
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_windowed_default")
public func kk_list_windowed_default(_ listRaw: Int, _ size: Int) -> Int {
    return kk_list_windowed(listRaw, size, 1)
}

@_cdecl("kk_list_windowed")
public func kk_list_windowed(_ listRaw: Int, _ size: Int, _ step: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    var windows: [Int] = []
    var i = 0
    while i + clampedSize <= elements.count {
        let window = Array(elements[i ..< (i + clampedSize)])
        windows.append(registerRuntimeObject(RuntimeListBox(elements: window)))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}

@_cdecl("kk_list_windowed_partial")
public func kk_list_windowed_partial(_ listRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let partial = partialWindows != 0
    var windows: [Int] = []
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        if !partial && end - i < clampedSize { break }
        let window = Array(elements[i ..< end])
        windows.append(registerRuntimeObject(RuntimeListBox(elements: window)))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}

@_cdecl("kk_list_indexOf")
public func kk_list_indexOf(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        return index
    }
    return -1
}

@_cdecl("kk_list_lastIndexOf")
public func kk_list_lastIndexOf(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        lastIdx = index
    }
    return lastIdx
}

@_cdecl("kk_list_indexOfFirst")
public func kk_list_indexOfFirst(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return index }
    }
    return -1
}

@_cdecl("kk_list_indexOfLast")
public func kk_list_indexOfLast(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { lastIdx = index }
    }
    return lastIdx
}

// MARK: - binarySearch with comparison lambda (STDLIB-547)

@_cdecl("kk_list_binarySearch_compare")
public func kk_list_binarySearch_compare(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var low = 0
    var high = list.elements.count - 1
    while low <= high {
        let mid = low + (high - low) / 2
        var thrown = 0
        let cmp = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[mid], outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let cmpVal = maybeUnbox(cmp)
        if cmpVal < 0 {
            low = mid + 1
        } else if cmpVal > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

// MARK: - filterIsInstance (STDLIB-114)

@_cdecl("kk_list_filterIsInstance")
public func kk_list_filterIsInstance(_ listRaw: Int, _ typeToken: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    var result: [Int] = []
    for elem in elements where kk_op_is(elem, typeToken) != 0 {
        result.append(elem)
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

// MARK: - Sorting variants (STDLIB-115)

@_cdecl("kk_list_sortedDescending")
public func kk_list_sortedDescending(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison > 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedByDescending")
public func kk_list_sortedByDescending(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(key)
    }
    let indexed = list.elements.enumerated().map { ($0.offset, $0.element, keys[$0.offset]) }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.2, rhs.2)
        if comparison != 0 { return comparison > 0 }
        return lhs.0 < rhs.0
    }.map(\.1)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedWith")
public func kk_list_sortedWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var hadThrow = false
    let sorted = list.elements.enumerated().sorted { lhs, rhs in
        guard !hadThrow else { return false }
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: lhs.element, rhs: rhs.element, outThrown: &thrown)
        if thrown != 0 { _ = handleCollectionLambdaThrow(thrown, outThrown); hadThrow = true; return false }
        if result != 0 { return result < 0 }
        return lhs.offset < rhs.offset
    }.map(\.element)
    if hadThrow { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

// MARK: - takeWhile / dropWhile / takeLastWhile / dropLastWhile (STDLIB-440)

/// Invoke a predicate lambda and evaluate its boolean result.
/// Returns `(thrownValue, satisfied)`. When `thrownValue != 0` the caller must
/// propagate the exception via `handleCollectionLambdaThrow`.
private func evalPredicate(
    fnPtr: Int, closureRaw: Int, value: Int
) -> (thrownValue: Int, satisfied: Bool) {
    var thrown = 0
    let predResult = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr, closureRaw: closureRaw, value: value, outThrown: &thrown)
    if thrown != 0 { return (thrownValue: thrown, satisfied: false) }
    return (thrownValue: 0, satisfied: maybeUnbox(predResult) != 0)
}

@_cdecl("kk_list_takeWhile")
public func kk_list_takeWhile(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (i, elem) in list.elements.enumerated() {
        let (thrownValue, satisfied) = evalPredicate(
            fnPtr: fnPtr, closureRaw: closureRaw, value: elem)
        if thrownValue != 0 { return handleCollectionLambdaThrow(thrownValue, outThrown) }
        if !satisfied {
            let result = Array(list.elements[..<i])
            return registerRuntimeObject(RuntimeListBox(elements: result))
        }
    }
    // Predicate was true for all elements — always return a new list (Kotlin snapshot semantics).
    return registerRuntimeObject(RuntimeListBox(elements: list.elements))
}

@_cdecl("kk_list_dropWhile")
public func kk_list_dropWhile(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (i, elem) in list.elements.enumerated() {
        let (thrownValue, satisfied) = evalPredicate(
            fnPtr: fnPtr, closureRaw: closureRaw, value: elem)
        if thrownValue != 0 { return handleCollectionLambdaThrow(thrownValue, outThrown) }
        if !satisfied {
            // Use array slice for the remaining elements instead of appending one-by-one.
            let result = Array(list.elements[i...])
            return registerRuntimeObject(RuntimeListBox(elements: result))
        }
    }
    // All elements matched the predicate — everything was dropped.
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

/// Count how many elements from the end of `elements` satisfy the predicate.
/// Returns `(thrownValue: non-zero, count: 0)` when the predicate throws;
/// the caller is expected to propagate the exception via `handleCollectionLambdaThrow`.
private func computeMatchingSuffixCount(
    elements: [Int], fnPtr: Int, closureRaw: Int
) -> (thrownValue: Int, count: Int) {
    var count = 0
    for elem in elements.reversed() {
        let (thrownValue, satisfied) = evalPredicate(
            fnPtr: fnPtr, closureRaw: closureRaw, value: elem)
        if thrownValue != 0 { return (thrownValue: thrownValue, count: 0) }
        if !satisfied { break }
        count += 1
    }
    return (thrownValue: 0, count: count)
}

@_cdecl("kk_list_takeLastWhile")
public func kk_list_takeLastWhile(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let (thrownValue, count) = computeMatchingSuffixCount(
        elements: list.elements, fnPtr: fnPtr, closureRaw: closureRaw)
    if thrownValue != 0 { return handleCollectionLambdaThrow(thrownValue, outThrown) }
    var result = [Int]()
    result.reserveCapacity(count)
    result.append(contentsOf: list.elements.suffix(count))
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_dropLastWhile")
public func kk_list_dropLastWhile(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let (thrownValue, dropCount) = computeMatchingSuffixCount(
        elements: list.elements, fnPtr: fnPtr, closureRaw: closureRaw)
    if thrownValue != 0 { return handleCollectionLambdaThrow(thrownValue, outThrown) }
    let keepCount = list.elements.count - dropCount
    var result = [Int]()
    result.reserveCapacity(keepCount)
    result.append(contentsOf: list.elements.prefix(keepCount))
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

// MARK: - onEach / onEachIndexed (STDLIB-300)

@_cdecl("kk_list_onEach")
public func kk_list_onEach(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        _ = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return listRaw
}

@_cdecl("kk_list_onEachIndexed")
public func kk_list_onEachIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        _ = lambda(closureRaw, idx, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return listRaw
}

// MARK: - Partition (STDLIB-112)

@_cdecl("kk_list_partition")
public func kk_list_partition(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var matching: [Int] = []
    var nonMatching: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if maybeUnbox(result) != 0 {
            matching.append(elem)
        } else {
            nonMatching.append(elem)
        }
    }
    let matchingList = registerRuntimeObject(RuntimeListBox(elements: matching))
    let nonMatchingList = registerRuntimeObject(RuntimeListBox(elements: nonMatching))
    return kk_pair_new(matchingList, nonMatchingList)
}

// MARK: - MutableList in-place sort (STDLIB-205)

@_cdecl("kk_mutable_list_sort")
public func kk_mutable_list_sort(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let indexed = list.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 { return comparison < 0 }
        return lhs.offset < rhs.offset
    }.map(\.element)
    for i in 0 ..< indexed.count {
        list.elements[i] = indexed[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sortBy")
public func kk_mutable_list_sortBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(maybeUnbox(key))
    }
    let sorted = list.elements.enumerated().sorted { lhs, rhs in
        if keys[lhs.offset] != keys[rhs.offset] { return keys[lhs.offset] < keys[rhs.offset] }
        return lhs.offset < rhs.offset
    }.map(\.element)
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sortByDescending")
public func kk_mutable_list_sortByDescending(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(maybeUnbox(key))
    }
    let sorted = list.elements.enumerated().sorted { lhs, rhs in
        if keys[lhs.offset] != keys[rhs.offset] { return keys[lhs.offset] > keys[rhs.offset] }
        return lhs.offset < rhs.offset
    }.map(\.element)
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i]
    }
    return 0
}

// MARK: - Set higher-order functions (STDLIB-268)

@_cdecl("kk_set_map")
public func kk_set_map(_ setRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        invalidContainerPanic(#function, "set")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(set.elements.count)
    for elem in set.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_set_filter")
public func kk_set_filter(_ setRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        invalidContainerPanic(#function, "set")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    for elem in set.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_set_forEach")
public func kk_set_forEach(_ setRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else { invalidContainerPanic(#function, "set") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in set.elements {
        var thrown = 0
        _ = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return 0
}

// MARK: - Array higher-order functions (STDLIB-088)

@_cdecl("kk_array_map")
public func kk_array_map(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var mapped: [Int] = []
    mapped.reserveCapacity(array.elements.count)
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_array_filter")
public func kk_array_filter(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var filtered: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_forEach")
public func kk_array_forEach(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    for elem in array.elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_array_any")
public func kk_array_any(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    // Zero-arg overload: any() returns true if array is non-empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 0 : 1) }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return kk_box_bool(1) }
    }
    return kk_box_bool(0)
}

@_cdecl("kk_array_none")
public func kk_array_none(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    // Zero-arg overload: none() returns true if array is empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 1 : 0) }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

// MARK: - Grouping (STDLIB-285/286)

private func runtimeGroupingBox(from rawValue: Int) -> RuntimeGroupingBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else { return nil }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else { return nil }
    return tryCast(ptr, to: RuntimeGroupingBox.self)
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
    var keyIndex: [Int: Int] = [:]  // normalizedKey -> index (O(1) lookup for immediate values)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = maybeUnbox(key)
        if let idx = keyIndex[normalizedKey] {
            counts[idx] += 1
        } else if let idx = keys.firstIndex(where: { runtimeValuesEqual($0, normalizedKey) }) {
            // Fallback: hash collision or boxed value — linear scan
            keyIndex[normalizedKey] = idx
            counts[idx] += 1
        } else {
            let newIdx = keys.count
            keyIndex[normalizedKey] = newIdx
            keys.append(normalizedKey)
            counts.append(1)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: counts.map { kk_box_int($0) }))
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
    var keyIndex: [Int: Int] = [:]  // normalizedKey -> index (O(1) lookup for immediate values)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = maybeUnbox(key)
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
            keys.append(normalizedKey)
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
    var keyIndex: [Int: Int] = [:]  // normalizedKey -> index (O(1) lookup per element)
    for elem in grouping.sourceElements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: grouping.keyFnPtr, closureRaw: grouping.keyClosureRaw,
            value: elem, outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let normalizedKey = maybeUnbox(key)
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
            keys.append(normalizedKey)
            accumulators.append(elem)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: accumulators))
}
