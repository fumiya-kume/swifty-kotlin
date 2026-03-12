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

// MARK: - List getOrElse (STDLIB-212)

@_cdecl("kk_list_getOrElse")
public func kk_list_getOrElse(_ listRaw: Int, _ index: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let list = runtimeListBox(from: listRaw),
       list.elements.indices.contains(index)
    {
        return list.elements[index]
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, index, &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return result
}

@_cdecl("kk_list_map")
public func kk_list_map(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_filter")
public func kk_list_filter(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_mapNotNull")
public func kk_list_mapNotNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeListBox(elements: []))
        }
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
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let filtered = list.elements.filter { maybeUnbox($0) != runtimeNullSentinelInt }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_forEach")
public func kk_list_forEach(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        _ = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return 0
}

@_cdecl("kk_map_forEach")
public func kk_map_forEach(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        _ = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

@_cdecl("kk_map_map")
public func kk_map_map(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_map_filter")
public func kk_map_filter(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
        if maybeUnbox(result) != 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_getOrElse")
public func kk_map_getOrElse(_ mapRaw: Int, _ key: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let map = runtimeMapBox(from: mapRaw) {
        for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
            if idx < map.values.count { return map.values[idx] }
            break
        }
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return result
}

@_cdecl("kk_mutable_map_getOrPut")
public func kk_mutable_map_getOrPut(_ mapRaw: Int, _ key: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    if let map = runtimeMapBox(from: mapRaw) {
        for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
            if idx < map.values.count {
                let existing = map.values[idx]
                if existing != runtimeNullSentinelInt {
                    return existing
                }
                var thrown = 0
                let result = lambda(closureRaw, &thrown)
                if thrown != 0 { outThrown?.pointee = thrown; return 0 }
                map.values[idx] = result
                return result
            }
            break
        }
    }

    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    if let map = runtimeMapBox(from: mapRaw) {
        map.keys.append(key)
        map.values.append(result)
    }
    return result
}

@_cdecl("kk_map_mapValues")
public func kk_map_mapValues(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mappedValues: [Int] = []
    mappedValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
        mappedValues.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: map.keys, values: mappedValues)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_mapKeys")
public func kk_map_mapKeys(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mappedKeys: [Int] = []
    mappedKeys.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, kk_pair_new(key, value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeMapBox(keys: [], values: [])) }
        mappedKeys.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: mappedKeys, values: map.values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_toList")
public func kk_map_toList(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var pairs: [Int] = []
    pairs.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        pairs.append(kk_pair_new(key, value))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_list_flatMap")
public func kk_list_flatMap(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let subListRaw = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_any")
public func kk_list_any(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 0 : 1
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_list_none")
public func kk_list_none(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 1 }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 1 : 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_list_all")
public func kk_list_all(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_list_fold")
public func kk_list_fold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return initial }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = initial
    for elem in list.elements {
        var thrown = 0
        acc = maybeUnbox(lambda(closureRaw, acc, elem, &thrown))
        if thrown != 0 { outThrown?.pointee = thrown; return initial }
    }
    return acc
}

@_cdecl("kk_list_reduce")
public func kk_list_reduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw), !list.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = list.elements[0]
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        acc = maybeUnbox(lambda(closureRaw, acc, list.elements[idx], &thrown))
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return acc
}

@_cdecl("kk_list_groupBy")
public func kk_list_groupBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [Int: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
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

@_cdecl("kk_list_sortedBy")
public func kk_list_sortedBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var elems: [Int] = []
    var keys: [Int] = []
    elems.reserveCapacity(list.elements.count)
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeListBox(elements: []))
        }
        elems.append(elem)
        keys.append(maybeUnbox(key))
    }
    let indices = Array(elems.indices)
    let sorted = indices.sorted { lhs, rhs in
        if keys[lhs] != keys[rhs] { return keys[lhs] < keys[rhs] }
        return lhs < rhs
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map { elems[$0] }))
}

@_cdecl("kk_list_count")
public func kk_list_count(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    if fnPtr == 0 {
        return list.elements.count
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_list_first")
public func kk_list_first(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw), !list.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Collection is empty.")
        return 0
    }
    if fnPtr == 0 {
        return list.elements[0]
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { return elem }
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return 0
}

@_cdecl("kk_list_last")
public func kk_list_last(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw), !list.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Collection is empty.")
        return 0
    }
    if fnPtr == 0 {
        return list.elements.last!
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastMatch: Int?
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { lastMatch = elem }
    }
    if let match = lastMatch { return match }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return 0
}

@_cdecl("kk_list_find")
public func kk_list_find(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return runtimeNullSentinelInt }
    if fnPtr == 0 {
        return list.elements.first ?? runtimeNullSentinelInt
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_list_associateBy")
public func kk_list_associateBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(maybeUnbox(key))
        values.append(elem)
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associateWith")
public func kk_list_associateWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let value = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(elem)
        values.append(maybeUnbox(value))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associate")
public func kk_list_associate(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let pair = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(kk_pair_first(pair))
        values.append(kk_pair_second(pair))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_zip")
public func kk_list_zip(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeListBox(from: listRaw)?.elements ?? []
    let rhs = runtimeListBox(from: otherRaw)?.elements ?? []
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
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        // Pass index as raw Int (Kotlin primitive); elem stays boxed per ABI.
        _ = lambda(closureRaw, idx, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

@_cdecl("kk_list_mapIndexed")
public func kk_list_mapIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        // Pass index as raw Int (Kotlin primitive); elem stays boxed per ABI.
        let result = lambda(closureRaw, idx, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_sumOf")
public func kk_list_sumOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var total = 0
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_list_maxOrNull")
public func kk_list_maxOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw), let first = list.elements.first else {
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
    guard let list = runtimeListBox(from: listRaw), let first = list.elements.first else {
        return runtimeNullSentinelInt
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) < 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_reversed")
public func kk_list_reversed(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.reversed())))
}

@_cdecl("kk_list_sorted")
public func kk_list_sorted(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    return registerRuntimeObject(RuntimeListBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

@_cdecl("kk_list_shuffled")
public func kk_list_shuffled(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let shuffled = elements.shuffled()
    return registerRuntimeObject(RuntimeListBox(elements: shuffled))
}

@_cdecl("kk_list_random")
public func kk_list_random(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw), !list.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: List is empty.")
        return 0
    }
    return list.elements.randomElement()!
}

@_cdecl("kk_list_randomOrNull")
public func kk_list_randomOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw), let element = list.elements.randomElement() else {
        return runtimeNullSentinelInt
    }
    return element
}

@_cdecl("kk_list_flatten")
public func kk_list_flatten(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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

@_cdecl("kk_list_windowed")
public func kk_list_windowed(_ listRaw: Int, _ size: Int, _ step: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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

@_cdecl("kk_list_indexOf")
public func kk_list_indexOf(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return -1 }
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        return index
    }
    return -1
}

@_cdecl("kk_list_lastIndexOf")
public func kk_list_lastIndexOf(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return -1 }
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        lastIdx = index
    }
    return lastIdx
}

@_cdecl("kk_list_indexOfFirst")
public func kk_list_indexOfFirst(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return -1 }
        if maybeUnbox(result) != 0 { return index }
    }
    return -1
}

@_cdecl("kk_list_indexOfLast")
public func kk_list_indexOfLast(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return -1 }
        if maybeUnbox(result) != 0 { lastIdx = index }
    }
    return lastIdx
}

// MARK: - filterIsInstance (STDLIB-114)

@_cdecl("kk_list_filterIsInstance")
public func kk_list_filterIsInstance(_ listRaw: Int, _ typeToken: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    var result: [Int] = []
    for elem in elements where kk_op_is(elem, typeToken) != 0 {
        result.append(elem)
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

// MARK: - Sorting variants (STDLIB-115)

@_cdecl("kk_list_sortedDescending")
public func kk_list_sortedDescending(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
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
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
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
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var hadThrow = false
    let sorted = list.elements.enumerated().sorted { lhs, rhs in
        guard !hadThrow else { return false }
        var thrown = 0
        let result = lambda(closureRaw, lhs.element, rhs.element, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; hadThrow = true; return false }
        if result != 0 { return result < 0 }
        return lhs.offset < rhs.offset
    }.map(\.element)
    if hadThrow { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

// MARK: - Partition (STDLIB-112)

@_cdecl("kk_list_partition")
public func kk_list_partition(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
        return kk_pair_new(emptyList, emptyList)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matching: [Int] = []
    var nonMatching: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
            return kk_pair_new(emptyList, emptyList)
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

// MARK: - Array higher-order functions (STDLIB-088)

@_cdecl("kk_array_map")
public func kk_array_map(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(array.elements.count)
    for elem in array.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_array_filter")
public func kk_array_filter(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_forEach")
public func kk_array_forEach(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in array.elements {
        var thrown = 0
        _ = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return 0
}

@_cdecl("kk_array_any")
public func kk_array_any(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { return kk_box_bool(0) }
    // Zero-arg overload: any() returns true if array is non-empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 0 : 1) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in array.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return kk_box_bool(0) }
        if maybeUnbox(result) != 0 { return kk_box_bool(1) }
    }
    return kk_box_bool(0)
}

@_cdecl("kk_array_none")
public func kk_array_none(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { return kk_box_bool(1) }
    // Zero-arg overload: none() returns true if array is empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 1 : 0) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in array.elements {
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return kk_box_bool(1) }
        if maybeUnbox(result) != 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}
