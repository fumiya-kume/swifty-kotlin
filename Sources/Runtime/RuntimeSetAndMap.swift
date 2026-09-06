
// Set / Map runtime functions (STDLIB-001 + STDLIB-266 set operations).
//
// Split out from `RuntimeCollections.swift`.

// MARK: - Set Functions (STDLIB-001)

@_cdecl("__kk_set_of")
public func kk_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

/// HashSet constructor storage. Keep ordinary Set factories on the shared Set
/// identity; HashSet constructors need their own nominal tag for `is` checks.
@_cdecl("__kk_hash_set_of")
public func kk_hash_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(
        RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)),
        typeID: hashSetRuntimeTypeID
    )
}

@_cdecl("__kk_set_of_not_null")
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
@_cdecl("__kk_emptySet")
public func kk_emptySet() -> Int {
    return registerRuntimeObject(RuntimeSetBox(elements: []))
}

// BUG-196: Source-backed LinkedHashSet instances (and user subclasses) are
// allocated as ordinary RuntimeObjectBox objects. Attach a backing RuntimeSetBox
// during construction so MutableSet member calls operate on real storage.
@_cdecl("__kk_linked_hash_set_init")
public func kk_linked_hash_set_init(_ setRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw),
          let objectBox = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return 0
    }
    objectBox.backingSetBox = RuntimeSetBox(elements: [])
    return 0
}

@_cdecl("__kk_set_size")
public func kk_set_size(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return 0
    }
    return set.count
}

@_cdecl("__kk_set_contains")
public func kk_set_contains(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(set.contains(rawValue: element) ? 1 : 0)
}

@_cdecl("__kk_set_is_empty")
public func kk_set_is_empty(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(set.isEmpty ? 1 : 0)
}

@_cdecl("__kk_set_to_string")
public func kk_set_to_string(_ setRaw: Int) -> UnsafeMutableRawPointer {
    guard let set = runtimeSetBox(from: setRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = set.values.map(runtimeElementToString)
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("__kk_collection_toList")
public func kk_collection_toList(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: list.elements))
    }
    if let set = runtimeSetBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: set.elements))
    }
    if let array = runtimeArrayBoxExcludingObjects(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(values: Array(array.values)))
    }
    // Delegate to sequence collection when the handle is a runtime-backed or
    // source-implemented Sequence box. This can happen when Collection.toList()
    // is resolved on a sequence receiver via the synthetic Collection stub.
    if let elements = runtimeSequenceSourceElements(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

@_cdecl("__kk_collection_size")
public func kk_collection_size(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.elements.count
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.count
    }
    if let sourceSize = runtimeSourceCollectionSize(collRaw) {
        return sourceSize
    }
    return 0
}

@_cdecl("__kk_collection_isEmpty")
public func kk_collection_isEmpty(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.elements.isEmpty ? 1 : 0
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.isEmpty ? 1 : 0
    }
    if let sourceSize = runtimeSourceCollectionSize(collRaw) {
        return sourceSize == 0 ? 1 : 0
    }
    return 1
}

@_cdecl("__kk_collection_containsAll")
public func kk_collection_containsAll(_ collRaw: Int, _ elementsRaw: Int) -> Int {
    let iteratorRaw = kk_list_iterator(elementsRaw)
    while kk_list_iterator_hasNext(iteratorRaw) != 0 {
        if kk_op_contains(collRaw, kk_list_iterator_next(iteratorRaw)) == 0 {
            return 0
        }
    }
    return 1
}

// MARK: - Mutable Set Operations

@_cdecl("__kk_mutable_set_add")
public func kk_mutable_set_add(
    _ setRaw: Int,
    _ elem: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    guard !set.isReadOnly else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: nil)
        return kk_box_bool(0)
    }
    return kk_box_bool(set.insert(rawValue: elem) ? 1 : 0)
}

@_cdecl("__kk_mutable_set_remove")
public func kk_mutable_set_remove(_ setRaw: Int, _ elem: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(set.remove(rawValue: elem) ? 1 : 0)
}

@_cdecl("__kk_mutable_set_clear")
public func kk_mutable_set_clear(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return 0
    }
    _ = set.removeAll(keepingCapacity: false)
    return 0
}

@_cdecl("__kk_mutable_set_addAll")
public func kk_mutable_set_addAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    kk_mutable_collection_addAll(setRaw, collectionRaw)
}

@_cdecl("__kk_mutable_set_addAll_sequence")
public func kk_mutable_set_addAll_sequence(_ setRaw: Int, _ sequenceRaw: Int) -> Int {
    return runtimeMutableSetAddAllSequence(setRaw: setRaw, sequenceRaw: sequenceRaw)
}

@_cdecl("__kk_mutable_set_addAll_iterable")
public func kk_mutable_set_addAll_iterable(_ setRaw: Int, _ iterableRaw: Int) -> Int {
    kk_mutable_collection_addAll_iterable(setRaw, iterableRaw)
}

@_cdecl("__kk_mutable_set_removeAll")
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
    let originalCount = set.count
    _ = set.removeAll { elem in
        collectionElements.contains(where: { runtimeValuesEqual($0, elem.legacyRawValue) })
    }
    return kk_box_bool(set.count != originalCount ? 1 : 0)
}

@_cdecl("__kk_mutable_set_retainAll")
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
    let originalCount = set.count
    _ = set.removeAll { elem in
        !collectionElements.contains(where: { runtimeValuesEqual($0, elem.legacyRawValue) })
    }
    return kk_box_bool(set.count != originalCount ? 1 : 0)
}

// MARK: - Map Functions (STDLIB-001)

private func runtimeMapOf(
    keysArrayRaw: Int,
    valuesArrayRaw: Int,
    count: Int,
    typeID: Int64
) -> Int {
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
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values), typeID: typeID)
}

@_cdecl("__kk_map_of")
public func kk_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOf(
        keysArrayRaw: keysArrayRaw,
        valuesArrayRaw: valuesArrayRaw,
        count: count,
        typeID: mutableMapRuntimeTypeID
    )
}

@_cdecl("__kk_hash_map_of")
public func kk_hash_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOf(
        keysArrayRaw: keysArrayRaw,
        valuesArrayRaw: valuesArrayRaw,
        count: count,
        typeID: hashMapRuntimeTypeID
    )
}

/// Builds a mutable map from a vararg Pair array, including a spread argument.
/// The compiler packs spread varargs before calling this bridge.
@_cdecl("__kk_map_of_pairs")
public func kk_map_of_pairs(_ pairsArrayRaw: Int, _ count: Int) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if count > 0, let pairs = runtimeArrayBox(from: pairsArrayRaw) {
        for pairRaw in pairs.elements.prefix(count) {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
                  let pairBox = tryCast(pointer, to: RuntimePairBox.self)
            else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in __kk_map_of_pairs")
            }
            keys.append(pairBox.first)
            values.append(pairBox.second)
        }
    }
    (keys, values) = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values), typeID: mutableMapRuntimeTypeID)
}

// STDLIB-410: emptyMap<K,V>() - allocates a fresh empty map each call to avoid
// aliasing with mutable collection operations (e.g., kk_mutable_map_put).
@_cdecl("__kk_emptyMap")
public func kk_emptyMap() -> Int {
    return registerRuntimeObject(RuntimeMapBox(keys: [], values: []), typeID: mutableMapRuntimeTypeID)
}

@_cdecl("__kk_mutable_map_put")
public func kk_mutable_map_put(
    _ mapRaw: Int,
    _ key: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeNullSentinelInt
    }
    guard !map.isReadOnly else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: nil)
        return runtimeNullSentinelInt
    }
    return map.put(key: key, value: value) ?? runtimeNullSentinelInt
}

@_cdecl("__kk_mutable_map_remove")
public func kk_mutable_map_remove(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeNullSentinelInt
    }
    return map.remove(key: key) ?? runtimeNullSentinelInt
}

@_cdecl("__kk_mutable_map_clear")
public func kk_mutable_map_clear(_ mapRaw: Int) -> Int {
    if let map = runtimeMapBox(from: mapRaw) {
        map.removeAll()
    }
    return 0
}

@_cdecl("__kk_mutable_map_putAll")
public func kk_mutable_map_putAll(_ mapRaw: Int, _ otherMapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let other = runtimeMapBox(from: otherMapRaw) else { return 0 }
    let otherKeys = other.keys
    let otherValues = other.values
    for (idx, key) in otherKeys.enumerated() {
        guard idx < otherValues.count else { break }
        _ = map.put(key: key, value: otherValues[idx])
    }
    return 0
}

@_cdecl("__kk_mutable_map_plusAssign_pair")
public func kk_mutable_map_plusAssign_pair(_ mapRaw: Int, _ pairRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        return 0
    }
    _ = kk_mutable_map_put(mapRaw, pairBox.first, pairBox.second, nil)
    return 0
}

@_cdecl("kk_map_size")
public func kk_map_size(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMapSize(mapRaw) ?? 0
    }
    return map.count
}

@_cdecl("__kk_map_get")
public func kk_map_get(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeNullSentinelInt
    }
    guard let index = map.index(ofRawKey: key) else {
        return runtimeNullSentinelInt
    }
    return map.rawValue(at: index) ?? runtimeNullSentinelInt
}

@inline(__always)
private func runtimeMapDefaultValue(_ map: RuntimeMapBox, key: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int? {
    guard map.defaultValueFnPtr != 0 else {
        return nil
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1MaybeWrapped(
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

/// Returns the `withDefault` value for `key`, or the null sentinel when the map
/// carries no default. Kotlin's `Map.getValue` consults this after a plain
/// lookup miss (KSP-431).
@_cdecl("__kk_map_implicit_default")
public func kk_map_implicit_default(_ mapRaw: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw),
          let defaultValue = runtimeMapDefaultValue(map, key: key, outThrown: outThrown)
    else {
        return runtimeNullSentinelInt
    }
    return defaultValue
}

@_cdecl("__kk_map_has_default")
public func kk_map_has_default(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return 0
    }
    return map.defaultValueFnPtr == 0 ? 0 : 1
}
@_cdecl("__kk_map_withDefault")
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
        defaultValueClosureRaw: closureRaw,
        backingMap: map
    ))
}

@_cdecl("__kk_mutable_map_withDefault")
public func kk_mutable_map_withDefault(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(
            RuntimeMapBox(
                keys: [],
                values: [],
                defaultValueFnPtr: fnPtr,
                defaultValueClosureRaw: closureRaw
            ),
            typeID: mutableMapRuntimeTypeID
        )
    }
    return registerRuntimeObject(
        RuntimeMapBox(
            keys: map.keys,
            values: map.values,
            defaultValueFnPtr: fnPtr,
            defaultValueClosureRaw: closureRaw,
            backingMap: map
        ),
        typeID: mutableMapRuntimeTypeID
    )
}

@_cdecl("kk_map_is_empty")
public func kk_map_is_empty(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        if let sourceSize = runtimeSourceMapSize(mapRaw) {
            return kk_box_bool(sourceSize == 0 ? 1 : 0)
        }
        return kk_box_bool(1)
    }
    return kk_box_bool(map.isEmpty ? 1 : 0)
}

@_cdecl("__kk_map_entries")
public func kk_map_entries(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    let entries = zip(map.keys, map.values).map { key, value in
        runtimeMapEntryNew(key: key, value: value)
    }
    return registerRuntimeObject(RuntimeSetBox(elements: entries))
}

@_cdecl("__kk_map_iterator")
public func kk_map_iterator(_ mapRaw: Int) -> Int {
    let (keys, values): ([Int], [Int]) = if let map = runtimeMapBox(from: mapRaw) {
        (map.keys, map.values)
    } else {
        ([], [])
    }
    return registerRuntimeObject(RuntimeMapIteratorBox(keys: keys, values: values))
}

@_cdecl("__kk_map_iterator_hasNext")
public func kk_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

/// Returns the key at the current position, matching the C preamble behavior.
@_cdecl("__kk_map_iterator_next")
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

@_cdecl("__kk_mutable_map_iterator")
public func kk_mutable_map_iterator(_ mapRaw: Int) -> Int {
    let keys = runtimeMapBox(from: mapRaw)?.keys ?? []
    return registerRuntimeObject(RuntimeMutableMapIteratorBox(mapRaw: mapRaw, keys: keys))
}

@_cdecl("__kk_mutable_map_iterator_hasNext")
public func kk_mutable_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

@_cdecl("__kk_mutable_map_iterator_next")
public func kk_mutable_map_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw),
          iter.index < iter.keys.count
    else {
        return runtimeNullSentinelInt
    }
    let key = iter.keys[iter.index]
    iter.index += 1
    iter.lastKey = key
    return runtimeMutableMapEntryNew(
        mapRaw: iter.mapRaw,
        key: key,
        value: kk_map_get(iter.mapRaw, key)
    )
}

@_cdecl("__kk_mutable_map_iterator_remove")
public func kk_mutable_map_iterator_remove(
    _ iterRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw),
          let key = iter.lastKey
    else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalStateException(message: nil))
        return runtimeExceptionCaughtSentinel
    }
    _ = kk_mutable_map_remove(iter.mapRaw, key)
    iter.lastKey = nil
    return 0
}

@_cdecl("__kk_mutable_map_entry_setValue")
public func kk_mutable_map_entry_setValue(_ entryRaw: Int, _ value: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: entryRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self),
          pairBox.mutableMapRaw != 0
    else {
        return runtimeNullSentinelInt
    }
    let previous = kk_mutable_map_put(pairBox.mutableMapRaw, pairBox.mutableMapKey, value, nil)
    pairBox.secondValue = RuntimeValue(raw: value)
    return previous
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
