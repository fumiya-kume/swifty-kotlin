import Foundation

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
    let box = RuntimeListBox(elements: elements)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    return kk_box_bool(list.elements.contains(element) ? 1 : 0)
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
    let box = RuntimeMapBox(keys: keys, values: values)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    for (idx, mapKey) in map.keys.enumerated() where mapKey == key {
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
    return kk_box_bool(map.keys.contains(key) ? 1 : 0)
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

// MARK: - Array Size (STDLIB-001)

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
