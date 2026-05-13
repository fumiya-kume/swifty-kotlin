import Foundation

/// Set / Map runtime functions (STDLIB-001 + STDLIB-266 set operations).
///
/// Split out from `RuntimeCollections.swift`.

// MARK: - Set Functions (STDLIB-001)

@_cdecl("kk_set_of")
public func kk_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

@_cdecl("kk_set_of_not_null")
public func kk_set_of_not_null(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        for element in array.elements.prefix(count) where element != runtimeNullSentinelInt {
            elements.append(element)
        }
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

// STDLIB-410: emptySet<T>() - allocates a fresh empty set each call to avoid
// aliasing with mutable collection operations.
@_cdecl("kk_emptySet")
public func kk_emptySet() -> Int {
    return registerRuntimeObject(RuntimeSetBox(elements: []))
}

@_cdecl("kk_set_size")
public func kk_set_size(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return 0
    }
    return set.elements.count
}

@_cdecl("kk_set_contains")
public func kk_set_contains(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(set.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0)
}

@_cdecl("kk_set_is_empty")
public func kk_set_is_empty(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(set.elements.isEmpty ? 1 : 0)
}


@_cdecl("kk_set_containsAll")
public func kk_set_containsAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    let otherElements: [Int]
    if let otherList = runtimeListBox(from: collectionRaw) {
        otherElements = otherList.elements
    } else if let otherSet = runtimeSetBox(from: collectionRaw) {
        otherElements = otherSet.elements
    } else {
        return kk_box_bool(0)
    }
    for element in otherElements {
        if !set.elements.contains(where: { runtimeValuesEqual($0, element) }) {
            return kk_box_bool(0)
        }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_set_to_string")
public func kk_set_to_string(_ setRaw: Int) -> UnsafeMutableRawPointer {
    guard let set = runtimeSetBox(from: setRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = set.elements.map(runtimeElementToString)
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_set_toList")
public func kk_set_toList(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: set.elements))
}

@_cdecl("kk_set_first")
public func kk_set_first(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw),
          let first = set.elements.first
    else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "Collection is empty."))
        return 0
    }
    return first
}

@_cdecl("kk_set_firstOrNull")
public func kk_set_firstOrNull(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let first = set.elements.first
    else {
        return runtimeNullSentinelInt
    }
    return first
}

@_cdecl("kk_set_last")
public func kk_set_last(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw),
          let last = set.elements.last
    else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "Collection is empty."))
        return 0
    }
    return last
}

@_cdecl("kk_set_lastOrNull")
public func kk_set_lastOrNull(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let last = set.elements.last
    else {
        return runtimeNullSentinelInt
    }
    return last
}

@_cdecl("kk_set_singleOrNull")
public func kk_set_singleOrNull(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          set.elements.count == 1
    else {
        return runtimeNullSentinelInt
    }
    return set.elements[0]
}

@_cdecl("kk_collection_toList")
public func kk_collection_toList(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: list.elements))
    }
    if let set = runtimeSetBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: set.elements))
    }
    // Delegate to kk_sequence_to_list when the handle is a sequence box.
    // This can happen when Collection.toList() is resolved on a sequence
    // receiver via the synthetic Collection stub.
    if let ptr = UnsafeMutableRawPointer(bitPattern: collRaw) {
        let isObj = runtimeStorage.withLock { $0.objectPointers.contains(UInt(bitPattern: ptr)) }
        if isObj, tryCast(ptr, to: RuntimeSequenceBox.self) != nil {
            return kk_sequence_to_list(collRaw, nil)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

@_cdecl("kk_collection_size")
public func kk_collection_size(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.elements.count
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.elements.count
    }
    return 0
}

@_cdecl("kk_collection_isEmpty")
public func kk_collection_isEmpty(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.elements.isEmpty ? 1 : 0
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.elements.isEmpty ? 1 : 0
    }
    return 1
}

// MARK: - Set Operations (STDLIB-266)

@_cdecl("kk_set_intersect")
public func kk_set_intersect(_ setRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSetBox(from: setRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = selfElements.filter { elem in
        otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

@_cdecl("kk_set_union")
public func kk_set_union(_ setRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSetBox(from: setRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    let combined = selfElements + otherElements
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(combined)))
}

@_cdecl("kk_set_subtract")
public func kk_set_subtract(_ setRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSetBox(from: setRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = selfElements.filter { elem in
        !otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

@_cdecl("kk_mutable_set_add")
public func kk_mutable_set_add(_ setRaw: Int, _ elem: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    if set.elements.contains(where: { runtimeValuesEqual($0, elem) }) {
        return kk_box_bool(0)
    }
    set.elements.append(elem)
    return kk_box_bool(1)
}

@_cdecl("kk_mutable_set_remove")
public func kk_mutable_set_remove(_ setRaw: Int, _ elem: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let index = set.elements.firstIndex(where: { runtimeValuesEqual($0, elem) })
    else {
        return kk_box_bool(0)
    }
    set.elements.remove(at: index)
    return kk_box_bool(1)
}

@_cdecl("kk_mutable_set_clear")
public func kk_mutable_set_clear(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return 0
    }
    set.elements.removeAll(keepingCapacity: false)
    return 0
}

@_cdecl("kk_mutable_set_addAll")
public func kk_mutable_set_addAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    kk_mutable_collection_addAll(setRaw, collectionRaw)
}

@_cdecl("kk_mutable_set_removeAll")
public func kk_mutable_set_removeAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    let collectionElements: [Int]
    if let collection = runtimeListBox(from: collectionRaw) {
        collectionElements = collection.elements
    } else if let collection = runtimeSetBox(from: collectionRaw) {
        collectionElements = collection.elements
    } else {
        return kk_box_bool(0)
    }
    let originalCount = set.elements.count
    set.elements.removeAll { elem in
        collectionElements.contains(where: { runtimeValuesEqual($0, elem) })
    }
    return kk_box_bool(set.elements.count != originalCount ? 1 : 0)
}

@_cdecl("kk_mutable_set_retainAll")
public func kk_mutable_set_retainAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    let collectionElements: [Int]
    if let collection = runtimeListBox(from: collectionRaw) {
        collectionElements = collection.elements
    } else if let collection = runtimeSetBox(from: collectionRaw) {
        collectionElements = collection.elements
    } else {
        return kk_box_bool(0)
    }
    let originalCount = set.elements.count
    set.elements.removeAll { elem in
        !collectionElements.contains(where: { runtimeValuesEqual($0, elem) })
    }
    return kk_box_bool(set.elements.count != originalCount ? 1 : 0)
}

// MARK: - Map Functions (STDLIB-001)

@_cdecl("kk_map_of")
public func kk_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if count > 0, let arrays = runtimeMapArrayPair(keysRaw: keysArrayRaw, valuesRaw: valuesArrayRaw) {
        let effectiveCount = min(count, arrays.keys.count, arrays.values.count)
        if effectiveCount > 0 {
            keys = Array(arrays.keys.prefix(effectiveCount))
            values = Array(arrays.values.prefix(effectiveCount))
        }
    }
    (keys, values) = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

// STDLIB-410: emptyMap<K,V>() - allocates a fresh empty map each call to avoid
// aliasing with mutable collection operations (e.g., kk_mutable_map_put).
@_cdecl("kk_emptyMap")
public func kk_emptyMap() -> Int {
    return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
}

@_cdecl("kk_mutable_map_put")
public func kk_mutable_map_put(_ mapRaw: Int, _ key: Int, _ value: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeNullSentinelInt
    }
    if let index = map.keys.firstIndex(where: { runtimeValuesEqual($0, key) }) {
        let previous = index < map.values.count ? map.values[index] : runtimeNullSentinelInt
        if index < map.values.count {
            map.values[index] = value
        } else {
            map.values.append(value)
        }
        return previous
    }
    map.keys.append(key)
    map.values.append(value)
    return runtimeNullSentinelInt
}

@_cdecl("kk_mutable_map_remove")
public func kk_mutable_map_remove(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let index = map.keys.firstIndex(where: { runtimeValuesEqual($0, key) })
    else {
        return runtimeNullSentinelInt
    }
    map.keys.remove(at: index)
    guard index < map.values.count else {
        return runtimeNullSentinelInt
    }
    return map.values.remove(at: index)
}

@_cdecl("kk_mutable_map_clear")
public func kk_mutable_map_clear(_ mapRaw: Int) -> Int {
    if let map = runtimeMapBox(from: mapRaw) {
        map.keys.removeAll()
        map.values.removeAll()
    }
    return 0
}

@_cdecl("kk_mutable_map_putAll")
public func kk_mutable_map_putAll(_ mapRaw: Int, _ otherMapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let other = runtimeMapBox(from: otherMapRaw) else { return 0 }
    for (idx, key) in other.keys.enumerated() {
        guard idx < other.values.count else { break }
        var found = false
        for (existIdx, existKey) in map.keys.enumerated() where runtimeValuesEqual(existKey, key) {
            if existIdx < map.values.count {
                map.values[existIdx] = other.values[idx]
            } else {
                map.values.append(other.values[idx])
            }
            found = true
            break
        }
        if !found {
            map.keys.append(key)
            map.values.append(other.values[idx])
        }
    }
    return 0
}

@_cdecl("kk_mutable_map_plusAssign_pair")
public func kk_mutable_map_plusAssign_pair(_ mapRaw: Int, _ pairRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        return 0
    }
    _ = kk_mutable_map_put(mapRaw, pairBox.first, pairBox.second)
    return 0
}

@_cdecl("kk_map_size")
public func kk_map_size(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return 0
    }
    return map.keys.count
}

@_cdecl("kk_map_get")
public func kk_map_get(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeNullSentinelInt
    }
    for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
        guard idx < map.values.count else { return runtimeNullSentinelInt }
        return map.values[idx]
    }
    return runtimeNullSentinelInt
}

@inline(__always)
private func runtimeMapDefaultValue(_ map: RuntimeMapBox, key: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int? {
    guard map.defaultValueFnPtr != 0 else {
        return nil
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(
        fnPtr: map.defaultValueFnPtr,
        closureRaw: map.defaultValueClosureRaw,
        value: key,
        outThrown: &thrown
    )
    if thrown != 0 {
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return result
}

@inline(__always)
private func runtimeMapMissingKey(outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: Key is not in the map.")
    return 0
}

@_cdecl("kk_map_getValue")
public func kk_map_getValue(_ mapRaw: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeMapMissingKey(outThrown: outThrown)
    }
    for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
        guard idx < map.values.count else {
            break
        }
        return map.values[idx]
    }
    if let defaultValue = runtimeMapDefaultValue(map, key: key, outThrown: outThrown) {
        return defaultValue
    }
    return runtimeMapMissingKey(outThrown: outThrown)
}

@_cdecl("kk_map_getOrDefault")
public func kk_map_getOrDefault(_ mapRaw: Int, _ key: Int, _ defaultValue: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return defaultValue
    }
    for (idx, mapKey) in map.keys.enumerated() where runtimeValuesEqual(mapKey, key) {
        guard idx < map.values.count else { return defaultValue }
        return map.values[idx]
    }
    return defaultValue
}

@_cdecl("kk_map_withDefault")
public func kk_map_withDefault(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(
            keys: [],
            values: [],
            defaultValueFnPtr: fnPtr,
            defaultValueClosureRaw: closureRaw
        ))
    }
    return registerRuntimeObject(RuntimeMapBox(
        keys: map.keys,
        values: map.values,
        defaultValueFnPtr: fnPtr,
        defaultValueClosureRaw: closureRaw
    ))
}

@_cdecl("kk_map_contains_key")
public func kk_map_contains_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(map.keys.contains(where: { runtimeValuesEqual($0, key) }) ? 1 : 0)
}

@_cdecl("kk_map_contains_value")
public func kk_map_contains_value(_ mapRaw: Int, _ value: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(map.values.contains(where: { runtimeValuesEqual($0, value) }) ? 1 : 0)
}

@_cdecl("kk_map_is_empty")
public func kk_map_is_empty(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(map.keys.isEmpty ? 1 : 0)
}

@_cdecl("kk_map_keys")
public func kk_map_keys(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(map.keys)))
}

@_cdecl("kk_map_values")
public func kk_map_values(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: map.values))
}

@_cdecl("kk_map_entries")
public func kk_map_entries(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    let entries = zip(map.keys, map.values).map { key, value in
        runtimeMapEntryNew(key: key, value: value)
    }
    return registerRuntimeObject(RuntimeSetBox(elements: entries))
}

@_cdecl("kk_map_iterator")
public func kk_map_iterator(_ mapRaw: Int) -> Int {
    let (keys, values): ([Int], [Int]) = if let map = runtimeMapBox(from: mapRaw) {
        (map.keys, map.values)
    } else {
        ([], [])
    }
    return registerRuntimeObject(RuntimeMapIteratorBox(keys: keys, values: values))
}

@_cdecl("kk_map_iterator_hasNext")
public func kk_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

/// Returns the key at the current position, matching the C preamble behavior.
@_cdecl("kk_map_iterator_next")
public func kk_map_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMapIteratorBox(from: iterRaw) else {
        return 0
    }
    guard iter.index < iter.keys.count else {
        return 0
    }
    let key = iter.keys[iter.index]
    iter.index += 1
    return key
}

@_cdecl("kk_map_to_string")
public func kk_map_to_string(_ mapRaw: Int) -> UnsafeMutableRawPointer {
    guard let map = runtimeMapBox(from: mapRaw) else {
        let str = "{}"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = zip(map.keys, map.values).map { key, value -> String in
        let keyStr = runtimeElementToString(key)
        let valStr = runtimeElementToString(value)
        return "\(keyStr)=\(valStr)"
    }
    let str = "{" + parts.joined(separator: ", ") + "}"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_map_plus")
public func kk_map_plus(_ mapRaw: Int, _ pairRaw: Int) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if let map = runtimeMapBox(from: mapRaw) {
        (keys, values) = runtimeNormalizeMapEntries(keys: map.keys, values: map.values)
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
       let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    {
        let key = pairBox.first
        let value = pairBox.second
        if let index = keys.firstIndex(where: { runtimeValuesEqual($0, key) }) {
            values[index] = value
        } else {
            keys.append(key)
            values.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_map_minus")
public func kk_map_minus(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let (normalizedKeys, normalizedValues) = runtimeNormalizeMapEntries(keys: map.keys, values: map.values)
    var keys: [Int] = []
    var values: [Int] = []
    for (idx, mapKey) in normalizedKeys.enumerated() {
        if !runtimeValuesEqual(mapKey, key) {
            keys.append(mapKey)
            if idx < normalizedValues.count {
                values.append(normalizedValues[idx])
            }
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_map_to_mutable_map")
public func kk_map_to_mutable_map(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    return registerRuntimeObject(RuntimeMapBox(keys: map.keys, values: map.values))
}

