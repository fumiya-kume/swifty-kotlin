import Foundation

func runtimeDeduplicatePreservingOrder(_ elements: [Int]) -> [Int] {
    var seen: [Int] = []
    var unique: [Int] = []
    unique.reserveCapacity(elements.count)
    for element in elements where !seen.contains(where: { runtimeValuesEqual($0, element) }) {
        seen.append(element)
        unique.append(element)
    }
    return unique
}

func runtimeNormalizeMapEntries(keys: [Int], values: [Int]) -> ([Int], [Int]) {
    var normalizedKeys: [Int] = []
    var normalizedValues: [Int] = []
    let count = min(keys.count, values.count)
    for index in 0 ..< count {
        let key = keys[index]
        let value = values[index]
        if let existing = normalizedKeys.firstIndex(where: { runtimeValuesEqual($0, key) }) {
            normalizedValues[existing] = value
        } else {
            normalizedKeys.append(key)
            normalizedValues.append(value)
        }
    }
    return (normalizedKeys, normalizedValues)
}

// MARK: - List Functions (STDLIB-001)

/// Creates a new immutable list from an array of elements.
/// - Parameters:
///   - arrayRaw: intptr_t handle to a RuntimeArrayBox containing the elements.
///   - count: Number of elements in the array.
/// - Returns: Opaque handle (Int) to a `RuntimeListBox`.
@_cdecl("kk_list_of")
public func kk_list_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

/// Returns the size of a list.
/// - Parameter listRaw: Opaque handle to a `RuntimeListBox`.
/// - Returns: The number of elements in the list.
@_cdecl("kk_list_size")
public func kk_list_size(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    return list.elements.count
}

/// Returns the element at the given index in a list.
/// - Parameters:
///   - listRaw: Opaque handle to a `RuntimeListBox`.
///   - index: Zero-based index of the element.
/// - Returns: The element at the given index.
@_cdecl("kk_list_get")
public func kk_list_get(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    guard list.elements.indices.contains(index) else {
        return 0
    }
    return list.elements[index]
}

/// Checks if a list contains the given element.
/// - Parameters:
///   - listRaw: Opaque handle to a `RuntimeListBox`.
///   - element: The element to search for.
/// - Returns: Boxed boolean handle via `kk_box_bool`.
@_cdecl("kk_list_contains")
public func kk_list_contains(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(list.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0)
}

/// Checks if a list is empty.
/// - Parameter listRaw: Opaque handle to a `RuntimeListBox`.
/// - Returns: Boxed boolean handle via `kk_box_bool`.
@_cdecl("kk_list_is_empty")
public func kk_list_is_empty(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(list.elements.isEmpty ? 1 : 0)
}

/// Creates an iterator over a list.
/// - Parameter listRaw: Opaque handle to a `RuntimeListBox`.
/// - Returns: Opaque handle (Int) to a `RuntimeListIteratorBox`.
@_cdecl("kk_list_iterator")
public func kk_list_iterator(_ listRaw: Int) -> Int {
    let elements: [Int] = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else {
        []
    }
    let box = RuntimeListIteratorBox(elements: elements)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Checks if a list iterator has more elements.
/// - Parameter iterRaw: Opaque handle to a `RuntimeListIteratorBox`.
/// - Returns: 1 if there are more elements, 0 otherwise.
@_cdecl("kk_list_iterator_hasNext")
public func kk_list_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.elements.count ? 1 : 0
}

/// Returns the next element from a list iterator.
/// - Parameter iterRaw: Opaque handle to a `RuntimeListIteratorBox`.
/// - Returns: The next element.
@_cdecl("kk_list_iterator_next")
public func kk_list_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    guard iter.index < iter.elements.count else {
        return 0
    }
    let value = iter.elements[iter.index]
    iter.index += 1
    return value
}

/// Converts a list to its string representation (e.g. "[1, 2, 3]").
/// - Parameter listRaw: Opaque handle to a `RuntimeListBox`.
/// - Returns: Opaque handle (Int) to a `RuntimeStringBox` containing the string.
@_cdecl("kk_list_to_string")
public func kk_list_to_string(_ listRaw: Int) -> UnsafeMutableRawPointer {
    guard let list = runtimeListBox(from: listRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = list.elements.map { elem -> String in
        runtimeElementToString(elem)
    }
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_list_to_mutable_list")
public func kk_list_to_mutable_list(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: list.elements))
}

@_cdecl("kk_list_joinToString")
public func kk_list_joinToString(
    _ listRaw: Int,
    _ separatorRaw: Int,
    _ prefixRaw: Int,
    _ postfixRaw: Int
) -> UnsafeMutableRawPointer {
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let rendered = elements.map(runtimeElementToString).joined(separator: separator)
    let stringValue = prefix + rendered + postfix
    let utf8 = Array(stringValue.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_list_to_set")
public func kk_list_to_set(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(list.elements)))
}

@_cdecl("kk_mutable_list_add")
public func kk_mutable_list_add(_ listRaw: Int, _ elem: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    list.elements.append(elem)
    return kk_box_bool(1)
}

@_cdecl("kk_mutable_list_removeAt")
public func kk_mutable_list_removeAt(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.elements.indices.contains(index)
    else {
        return runtimeNullSentinelInt
    }
    return list.elements.remove(at: index)
}

@_cdecl("kk_mutable_list_clear")
public func kk_mutable_list_clear(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    list.elements.removeAll(keepingCapacity: false)
    return 0
}

// MARK: - Set Functions (STDLIB-022)

@_cdecl("kk_set_of")
public func kk_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
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

// MARK: - Map Functions (STDLIB-001)

/// Creates a new immutable map from parallel key and value arrays.
/// - Parameters:
///   - keysArrayRaw: intptr_t handle to a RuntimeArrayBox containing the keys.
///   - valuesArrayRaw: intptr_t handle to a RuntimeArrayBox containing the values.
///   - count: Number of key-value pairs.
/// - Returns: Opaque handle (Int) to a `RuntimeMapBox`.
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
    let box = RuntimeMapBox(keys: keys, values: values)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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

/// Returns the size of a map.
/// - Parameter mapRaw: Opaque handle to a `RuntimeMapBox`.
/// - Returns: The number of key-value pairs in the map.
@_cdecl("kk_map_size")
public func kk_map_size(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return 0
    }
    return map.keys.count
}

/// Returns the value associated with the given key in a map.
/// - Parameters:
///   - mapRaw: Opaque handle to a `RuntimeMapBox`.
///   - key: The key to look up.
/// - Returns: The associated value, or the null sentinel if not found.
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

/// Checks if a map contains the given key.
/// - Parameters:
///   - mapRaw: Opaque handle to a `RuntimeMapBox`.
///   - key: The key to search for.
/// - Returns: Boxed boolean handle via `kk_box_bool`.
@_cdecl("kk_map_contains_key")
public func kk_map_contains_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(map.keys.contains(where: { runtimeValuesEqual($0, key) }) ? 1 : 0)
}

/// Checks if a map is empty.
/// - Parameter mapRaw: Opaque handle to a `RuntimeMapBox`.
/// - Returns: Boxed boolean handle via `kk_box_bool`.
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

/// Creates an iterator over a map's entries.
/// - Parameter mapRaw: Opaque handle to a `RuntimeMapBox`.
/// - Returns: Opaque handle (Int) to a `RuntimeMapIteratorBox`.
@_cdecl("kk_map_iterator")
public func kk_map_iterator(_ mapRaw: Int) -> Int {
    let (keys, values): ([Int], [Int]) = if let map = runtimeMapBox(from: mapRaw) {
        (map.keys, map.values)
    } else {
        ([], [])
    }
    let box = RuntimeMapIteratorBox(keys: keys, values: values)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Checks if a map iterator has more entries.
/// - Parameter iterRaw: Opaque handle to a `RuntimeMapIteratorBox`.
/// - Returns: 1 if there are more entries, 0 otherwise.
@_cdecl("kk_map_iterator_hasNext")
public func kk_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

/// Returns the next entry from a map iterator.
/// Returns the key at the current position, matching the C preamble behavior.
/// - Parameter iterRaw: Opaque handle to a `RuntimeMapIteratorBox`.
/// - Returns: The next entry key.
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

/// Converts a map to its string representation (e.g. "{1=a, 2=b}").
/// - Parameter mapRaw: Opaque handle to a `RuntimeMapBox`.
/// - Returns: Opaque handle (Int) to a `RuntimeStringBox` containing the string.
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

@_cdecl("kk_map_to_mutable_map")
public func kk_map_to_mutable_map(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    return registerRuntimeObject(RuntimeMapBox(keys: map.keys, values: map.values))
}

// MARK: - Array Functions (STDLIB-001)

/// Creates a new array from existing elements (identity/tagging operation).
/// The array is already allocated by `kk_array_new`; this function simply
/// returns the handle so that the Swift runtime handles it consistently
/// instead of falling through to the C preamble stub.
/// - Parameters:
///   - arrayRaw: Opaque handle to a `RuntimeArrayBox` containing the elements.
///   - count: Number of elements in the array.
/// - Returns: Opaque handle (Int) to the array (passed through).
@_cdecl("kk_array_of")
public func kk_array_of(_ arrayRaw: Int, _: Int) -> Int {
    arrayRaw
}

/// Returns the size of an array.
/// - Parameter arrayRaw: Opaque handle to a `RuntimeArrayBox`.
/// - Returns: The number of elements in the array.
@_cdecl("kk_array_size")
public func kk_array_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

// MARK: - Pair Functions (FUNC-002)

/// Creates a new Pair from two elements.
/// - Parameters:
///   - first: The first element of the pair.
///   - second: The second element of the pair.
/// - Returns: Opaque handle (Int) to a `RuntimeArrayBox` containing 2 elements.
@_cdecl("kk_pair_new")
public func kk_pair_new(_ first: Int, _ second: Int) -> Int {
    let box = RuntimeArrayBox(length: 2)
    box.elements[0] = first
    box.elements[1] = second
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        let key = UInt(bitPattern: opaque)
        state.objectPointers.insert(key)
        state.pairPointers.insert(key)
    }
    return Int(bitPattern: opaque)
}

/// Returns the first element of a Pair.
/// - Parameter pairRaw: Opaque handle to a Pair (2-element RuntimeArrayBox).
/// - Returns: The first element.
@_cdecl("kk_pair_first")
public func kk_pair_first(_ pairRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: pairRaw),
          array.elements.count >= 2 else { return runtimeNullSentinelInt }
    return array.elements[0]
}

/// Returns the second element of a Pair.
/// - Parameter pairRaw: Opaque handle to a Pair (2-element RuntimeArrayBox).
/// - Returns: The second element.
@_cdecl("kk_pair_second")
public func kk_pair_second(_ pairRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: pairRaw),
          array.elements.count >= 2 else { return runtimeNullSentinelInt }
    return array.elements[1]
}

/// Converts a Pair to its string representation (e.g. "(1, one)").
/// - Parameter pairRaw: Opaque handle to a Pair (2-element RuntimeArrayBox).
/// - Returns: Opaque handle to a RuntimeStringBox containing the string.
@_cdecl("kk_pair_to_string")
public func kk_pair_to_string(_ pairRaw: Int) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: pairRaw),
          array.elements.count >= 2
    else {
        let str = "(null, null)"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let firstStr = runtimeElementToString(array.elements[0])
    let secondStr = runtimeElementToString(array.elements[1])
    let str = "(\(firstStr), \(secondStr))"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}
