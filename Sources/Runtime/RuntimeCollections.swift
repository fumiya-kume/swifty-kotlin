import Foundation

/// Hashable wrapper around an opaque runtime value (`Int`) that uses
/// `kk_any_hashCode` / `runtimeValuesEqual` so value-equal objects (e.g.
/// two distinct String handles with the same content) are treated as
/// equal keys.  Used by Set deduplication, Map key lookup, and Sequence
/// terminal operations (toMap, groupBy).
internal struct RuntimeElementKey: Hashable {
    let value: Int

    func hash(into hasher: inout Hasher) {
        // Normalise ±0.0 so that IEEE-equal values (-0.0 == +0.0) produce
        // identical hashes, keeping the Hashable contract intact.
        var h = kk_any_hashCode(value, 0)
        if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
            let isObj = runtimeStorage.withLock { $0.objectPointers.contains(UInt(bitPattern: ptr)) }
            if isObj {
                if let fb = tryCast(ptr, to: RuntimeFloatBox.self), fb.value == 0 {
                    h = kk_float_to_bits(Float(0))
                } else if let db = tryCast(ptr, to: RuntimeDoubleBox.self), db.value == 0 {
                    let bits = Int64(bitPattern: UInt64(bitPattern: Int64(kk_double_to_bits(Double(0)))))
                    h = Int(truncatingIfNeeded: bits ^ (bits >> 32))
                }
            }
        }
        hasher.combine(h)
    }

    static func == (lhs: RuntimeElementKey, rhs: RuntimeElementKey) -> Bool {
        runtimeValuesEqual(lhs.value, rhs.value)
    }
}

/// Extracts elements from an opaque `otherRaw` handle that may be either a
/// set or a list box.  Used by intersect / union / subtract to avoid
/// duplicating the same unboxing logic.
private func runtimeUnboxCollectionElements(_ otherRaw: Int) -> [Int] {
    if let otherSet = runtimeSetBox(from: otherRaw) {
        return otherSet.elements
    }
    if let otherList = runtimeListBox(from: otherRaw) {
        return otherList.elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: unexpected runtime handle in runtimeUnboxCollectionElements – neither set nor list")
}

func runtimeDeduplicatePreservingOrder(_ elements: [Int]) -> [Int] {
    var seen = Set<RuntimeElementKey>()
    seen.reserveCapacity(elements.count)
    var unique: [Int] = []
    unique.reserveCapacity(elements.count)
    for element in elements {
        if seen.insert(RuntimeElementKey(value: element)).inserted {
            unique.append(element)
        }
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

@_cdecl("kk_list_of")
public func kk_list_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements), typeID: listRuntimeTypeID)
}

@_cdecl("kk_list_of_not_null")
public func kk_list_of_not_null(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        for element in array.elements.prefix(count) {
            if element != runtimeNullSentinelInt {
                elements.append(element)
            }
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

// STDLIB-410: emptyList<T>() - allocates a fresh empty list each call to avoid
// aliasing with mutable collection operations (e.g., kk_mutable_list_add).
@_cdecl("kk_emptyList")
public func kk_emptyList() -> Int {
    return registerRuntimeObject(RuntimeListBox(elements: []), typeID: listRuntimeTypeID)
}

@_cdecl("kk_list_size")
public func kk_list_size(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    return list.elements.count
}

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

// STDLIB-183: List destructuring component1() ~ component5()
@_cdecl("kk_list_component1")
public func kk_list_component1(_ listRaw: Int) -> Int {
    kk_list_get(listRaw, 0)
}

@_cdecl("kk_list_component2")
public func kk_list_component2(_ listRaw: Int) -> Int {
    kk_list_get(listRaw, 1)
}

@_cdecl("kk_list_component3")
public func kk_list_component3(_ listRaw: Int) -> Int {
    kk_list_get(listRaw, 2)
}

@_cdecl("kk_list_component4")
public func kk_list_component4(_ listRaw: Int) -> Int {
    kk_list_get(listRaw, 3)
}

@_cdecl("kk_list_component5")
public func kk_list_component5(_ listRaw: Int) -> Int {
    kk_list_get(listRaw, 4)
}

@_cdecl("kk_list_contains")
public func kk_list_contains(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(list.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0)
}

@_cdecl("kk_list_is_empty")
public func kk_list_is_empty(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(list.elements.isEmpty ? 1 : 0)
}

@_cdecl("kk_list_iterator")
public func kk_list_iterator(_ listRaw: Int) -> Int {
    let elements: [Int] = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else if let set = runtimeSetBox(from: listRaw) {
        set.elements
    } else {
        []
    }
    return registerRuntimeObject(RuntimeListIteratorBox(elements: elements))
}

@_cdecl("kk_list_iterator_hasNext")
public func kk_list_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.elements.count ? 1 : 0
}

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

/// Whether the iterator has a valid previous element.
/// The invariant maintained by `kk_list_iterator_next` guarantees
/// `index` is always in `0...elements.count`, but we defensively
/// also check the upper bound so that a corrupted/invalid index
/// cannot lead to an out-of-bounds access in `previous()`.
private func listIteratorCanGoBack(_ iter: RuntimeListIteratorBox) -> Bool {
    iter.index > 0 && iter.index <= iter.elements.count
}

@_cdecl("kk_list_iterator_hasPrevious")
public func kk_list_iterator_hasPrevious(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    return listIteratorCanGoBack(iter) ? 1 : 0
}

@_cdecl("kk_list_iterator_previous")
public func kk_list_iterator_previous(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    guard listIteratorCanGoBack(iter) else {
        return 0
    }
    // Always decrement index and return the element at the new position
    // This matches the standard ListIterator behavior
    iter.index -= 1
    return iter.elements[iter.index]
}

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
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_to_mutable_list")
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

// MARK: - List toMap (STDLIB-200)

@_cdecl("kk_list_toMap")
public func kk_list_toMap(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    var keys: [Int] = []
    var values: [Int] = []
    for element in list.elements {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: element) else {
            continue
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
        guard isObjectPointer, let pair = tryCast(pointer, to: RuntimePairBox.self) else {
            continue
        }
        var found = false
        for (idx, existingKey) in keys.enumerated() where runtimeValuesEqual(existingKey, pair.first) {
            values[idx] = pair.second
            found = true
            break
        }
        if !found {
            keys.append(pair.first)
            values.append(pair.second)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_list_to_set")
public func kk_list_to_set(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(list.elements)))
}

// MARK: - Set.toSet(), toMutableSet() (STDLIB-651)

@_cdecl("kk_set_to_set")
public func kk_set_to_set(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    // Return a defensive copy (Kotlin semantics: toSet() on Set returns a new Set)
    return registerRuntimeObject(RuntimeSetBox(elements: Array(set.elements)))
}

@_cdecl("kk_list_to_mutable_set")
public func kk_list_to_mutable_set(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(list.elements)))
}

@inline(__always)
func runtimeMutableCollectionExists(_ destRaw: Int) -> Bool {
    runtimeListBox(from: destRaw) != nil || runtimeSetBox(from: destRaw) != nil
}

@inline(__always)
func runtimeAppendToMutableCollection(_ destRaw: Int, _ element: Int) {
    if let list = runtimeListBox(from: destRaw) {
        list.elements.append(element)
        return
    }
    if let set = runtimeSetBox(from: destRaw) {
        if !set.elements.contains(where: { runtimeValuesEqual($0, element) }) {
            set.elements.append(element)
        }
        return
    }
    invalidContainerPanic(#function, "mutable collection")
}

@_cdecl("kk_collection_toCollection")
public func kk_collection_toCollection(_ collRaw: Int, _ destRaw: Int) -> Int {
    guard let elements = runtimeCollectionElements(from: collRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for element in elements {
        runtimeAppendToMutableCollection(destRaw, element)
    }
    return destRaw
}

@_cdecl("kk_set_to_mutable_set")
public func kk_set_to_mutable_set(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: Array(set.elements)))
}

// MARK: - List intersect / union / subtract / toHashSet (STDLIB-510)

@_cdecl("kk_list_intersect")
public func kk_list_intersect(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeListBox(from: listRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = runtimeDeduplicatePreservingOrder(selfElements).filter { elem in
        otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

@_cdecl("kk_list_union")
public func kk_list_union(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeListBox(from: listRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    let combined = selfElements + otherElements
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(combined)))
}

@_cdecl("kk_list_subtract")
public func kk_list_subtract(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeListBox(from: listRaw)?.elements ?? []
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = runtimeDeduplicatePreservingOrder(selfElements).filter { elem in
        !otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

// NOTE: This duplicates the logic in kk_list_to_set.  Kept as a separate
// entry point because Kotlin distinguishes toSet() and toHashSet() at the API
// level.  If deduplication/boxing logic changes, consider delegating to a
// shared helper to avoid drift.
@_cdecl("kk_list_toHashSet")
public func kk_list_toHashSet(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(list.elements)))
}

// MARK: - List getOrNull / elementAtOrNull (STDLIB-212)

@_cdecl("kk_list_getOrNull")
public func kk_list_getOrNull(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.elements.indices.contains(index)
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[index]
}

@_cdecl("kk_list_elementAtOrNull")
public func kk_list_elementAtOrNull(_ listRaw: Int, _ index: Int) -> Int {
    kk_list_getOrNull(listRaw, index)
}

// MARK: - List elementAt (STDLIB-212)

@_cdecl("kk_list_elementAt")
public func kk_list_elementAt(_ listRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_list_elementAt received invalid list handle")
    }
    guard list.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: Index \(index) out of bounds for length \(list.elements.count)"
        )
        return 0
    }
    return list.elements[index]
}

// MARK: - STDLIB-210: List.firstOrNull() / lastOrNull()

@_cdecl("kk_list_firstOrNull")
public func kk_list_firstOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[0]
}

@_cdecl("kk_list_lastOrNull")
public func kk_list_lastOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[list.elements.count - 1]
}

// MARK: - STDLIB-211: List.singleOrNull()

@_cdecl("kk_list_singleOrNull")
public func kk_list_singleOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.elements.count == 1
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[0]
}

// STDLIB-214: List.slice(indices: IntRange)
@_cdecl("kk_list_slice")
public func kk_list_slice(_ listRaw: Int, _ rangeRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let size = list.elements.count
    let first = range.first
    let last = range.last
    let step = range.step > 0 ? range.step : 1
    guard first <= last, first >= 0, first < size else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var result: [Int] = []
    var i = first
    while i <= last && i < size {
        result.append(list.elements[i])
        i += step
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

// STDLIB-214: List.slice(indices: Iterable<Int>)
@_cdecl("kk_list_slice_iterable")
public func kk_list_slice_iterable(_ listRaw: Int, _ indicesRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let size = list.elements.count
    let indexElements: [Int]
    if let indexList = runtimeListBox(from: indicesRaw) {
        indexElements = indexList.elements
    } else if let indexSet = runtimeSetBox(from: indicesRaw) {
        indexElements = indexSet.elements
    } else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var result: [Int] = []
    for rawIdx in indexElements {
        let idx = kk_unbox_int(rawIdx)
        if idx >= 0 && idx < size {
            result.append(list.elements[idx])
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

// STDLIB-213: List.subList(fromIndex, toIndex)
@_cdecl("kk_list_subList")
public func kk_list_subList(_ listRaw: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let size = list.elements.count
    let from = max(0, min(fromIndex, size))
    let to = max(from, min(toIndex, size))
    let subElements = Array(list.elements[from ..< to])
    return registerRuntimeObject(RuntimeListBox(elements: subElements))
}

@_cdecl("kk_list_containsAll")
public func kk_list_containsAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
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
        if !list.elements.contains(where: { runtimeValuesEqual($0, element) }) {
            return kk_box_bool(0)
        }
    }
    return kk_box_bool(1)
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

@_cdecl("kk_mutable_list_removeFirstOrNull")
public func kk_mutable_list_removeFirstOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements.removeFirst()
}

@_cdecl("kk_mutable_list_removeLastOrNull")
public func kk_mutable_list_removeLastOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements.removeLast()
}

@_cdecl("kk_mutable_list_clear")
public func kk_mutable_list_clear(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    list.elements.removeAll(keepingCapacity: false)
    return 0
}

@_cdecl("kk_mutable_list_fill")
public func kk_mutable_list_fill(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    for index in 0 ..< list.elements.count {
        list.elements[index] = element
    }
    return 0
}

@_cdecl("kk_mutable_list_add_at")
public func kk_mutable_list_add_at(_ listRaw: Int, _ index: Int, _ element: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MutableList reference is null.")
        return 0
    }
    guard (0...list.elements.count).contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MutableList index \(index) out of bounds for length \(list.elements.count)."
        )
        return 0
    }
    list.elements.insert(element, at: index)
    return 0
}

@_cdecl("kk_mutable_list_set")
public func kk_mutable_list_set(_ listRaw: Int, _ index: Int, _ element: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MutableList reference is null.")
        return 0
    }
    guard list.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MutableList index \(index) out of bounds for length \(list.elements.count)."
        )
        return 0
    }
    let old = list.elements[index]
    list.elements[index] = element
    return old
}

// MARK: - MutableList shuffle/reverse (STDLIB-206)

@_cdecl("kk_mutable_list_shuffle")
public func kk_mutable_list_shuffle(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    // Fisher-Yates shuffle
    let count = list.elements.count
    if count > 1 {
        var rng = SystemRandomNumberGenerator()
        for i in stride(from: count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0 ... i, using: &rng)
            list.elements.swapAt(i, j)
        }
    }
    return 0
}

@_cdecl("kk_mutable_list_reverse")
public func kk_mutable_list_reverse(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    list.elements.reverse()
    return 0
}

// MARK: - MutableList bulk operations (STDLIB-207)

@_cdecl("kk_mutable_list_addAll")
public func kk_mutable_list_addAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
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
    if collectionElements.isEmpty {
        return kk_box_bool(0)
    }
    list.elements.append(contentsOf: collectionElements)
    return kk_box_bool(1)
}

@_cdecl("kk_mutable_list_removeAll")
public func kk_mutable_list_removeAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
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
    let originalCount = list.elements.count
    list.elements.removeAll { elem in
        collectionElements.contains(where: { runtimeValuesEqual($0, elem) })
    }
    return kk_box_bool(list.elements.count != originalCount ? 1 : 0)
}

@_cdecl("kk_mutable_list_retainAll")
public func kk_mutable_list_retainAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
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
    let originalCount = list.elements.count
    list.elements.removeAll { elem in
        !collectionElements.contains(where: { runtimeValuesEqual($0, elem) })
    }
    return kk_box_bool(list.elements.count != originalCount ? 1 : 0)
}

@_cdecl("kk_mutable_list_replaceAll")
public func kk_mutable_list_replaceAll(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for index in 0 ..< list.elements.count {
        var thrown = 0
        let result = lambda(closureRaw, list.elements[index], &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        list.elements[index] = maybeUnbox(result)
    }
    return 0
}

@_cdecl("kk_mutable_list_removeIf")
public func kk_mutable_list_removeIf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var changed = false
    var index = 0
    while index < list.elements.count {
        var thrown = 0
        let result = lambda(closureRaw, list.elements[index], &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if maybeUnbox(result) != 0 {
            list.elements.remove(at: index)
            changed = true
        } else {
            index += 1
        }
    }
    return kk_box_bool(changed ? 1 : 0)
}

// MARK: - List binarySearch (STDLIB-214)

@_cdecl("kk_list_binarySearch")
public func kk_list_binarySearch(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return -1
    }
    return runtimeBinarySearch(
        elements: list.elements,
        element: element,
        fromIndex: 0,
        toIndex: list.elements.count,
        compare: runtimeCompareValues
    )
}

// MARK: - List plus/minus operators (STDLIB-345)

@_cdecl("kk_list_plus_element")
public func kk_list_plus_element(_ listRaw: Int, _ element: Int) -> Int {
    let elements: [Int] = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else {
        []
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements + [element]))
}

@_cdecl("kk_list_plus_collection")
public func kk_list_plus_collection(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let lhsElements: [Int] = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else {
        []
    }
    let rhsElements: [Int]
    if let other = runtimeListBox(from: otherRaw) {
        rhsElements = other.elements
    } else if let other = runtimeSetBox(from: otherRaw) {
        rhsElements = other.elements
    } else {
        rhsElements = []
    }
    return registerRuntimeObject(RuntimeListBox(elements: lhsElements + rhsElements))
}

@_cdecl("kk_list_minus_element")
public func kk_list_minus_element(_ listRaw: Int, _ element: Int) -> Int {
    let elements = runtimeCollectionElements(from: listRaw) ?? runtimeArrayBox(from: listRaw)?.elements ?? []
    var result = elements
    if let index = result.firstIndex(where: { runtimeValuesEqual($0, element) }) {
        result.remove(at: index)
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_minus_collection")
public func kk_list_minus_collection(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let elements: [Int] = if let list = runtimeListBox(from: listRaw) {
        list.elements
    } else {
        []
    }
    let otherElements: [Int]
    if let other = runtimeListBox(from: otherRaw) {
        otherElements = other.elements
    } else if let other = runtimeSetBox(from: otherRaw) {
        otherElements = other.elements
    } else {
        otherElements = []
    }
    let result = elements.filter { element in
        !otherElements.contains(where: { runtimeValuesEqual($0, element) })
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

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
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    guard let elements = runtimeCollectionElements(from: collectionRaw) else {
        return kk_box_bool(0)
    }
    var modified = false
    for elem in elements {
        if !set.elements.contains(where: { runtimeValuesEqual($0, elem) }) {
            set.elements.append(elem)
            modified = true
        }
    }
    return kk_box_bool(modified ? 1 : 0)
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

@_cdecl("kk_empty_array")
public func kk_empty_array() -> Int {
    return kk_array_new(0)
}

@_cdecl("kk_array_of_nulls")
public func kk_array_of_nulls(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    box.elements = Array(repeating: runtimeNullSentinelInt, count: max(0, length))
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_size")
public func kk_array_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

@_cdecl("kk_array_is_empty")
public func kk_array_is_empty(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        // Gracefully return true (empty) for invalid handles, consistent with
        // kk_array_size returning 0.  Avoids crashing on invalid input per
        // the project's "never crash on invalid input" design principle.
        return kk_box_bool(1)
    }
    return kk_box_bool(array.elements.isEmpty ? 1 : 0)
}

// MARK: - Pair Functions (FUNC-002)

@_cdecl("kk_pair_new")
public func kk_pair_new(_ first: Int, _ second: Int) -> Int {
    registerRuntimeObject(RuntimePairBox(first: first, second: second))
}

@_cdecl("kk_pair_first")
public func kk_pair_first(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_first")
    }
    return pairBox.first
}

@_cdecl("component1")
public func component1(_ pairRaw: Int) -> Int {
    kk_pair_first(pairRaw)
}

@_cdecl("kk_pair_second")
public func kk_pair_second(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_second")
    }
    return pairBox.second
}

@_cdecl("component2")
public func component2(_ pairRaw: Int) -> Int {
    kk_pair_second(pairRaw)
}

@_cdecl("kk_map_entry_to_pair")
public func kk_map_entry_to_pair(_ entryRaw: Int) -> Int {
    if entryRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: entryRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Map.Entry handle in kk_map_entry_to_pair")
    }
    return kk_pair_new(pairBox.first, pairBox.second)
}

@_cdecl("kk_pair_to_string")
public func kk_pair_to_string(_ pairRaw: Int) -> UnsafeMutableRawPointer {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_to_string")
    }
    let firstStr = runtimeElementToString(pairBox.first)
    let secondStr = runtimeElementToString(pairBox.second)
    let str = "(\(firstStr), \(secondStr))"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Triple Functions (STDLIB-120)

@_cdecl("kk_triple_new")
public func kk_triple_new(_ first: Int, _ second: Int, _ third: Int) -> Int {
    let box = RuntimeTripleBox(first: first, second: second, third: third)
    return registerRuntimeObject(box)
}

@_cdecl("kk_triple_first")
public func kk_triple_first(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_first")
    }
    return tripleBox.first
}

@_cdecl("kk_triple_second")
public func kk_triple_second(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_second")
    }
    return tripleBox.second
}

@_cdecl("kk_triple_third")
public func kk_triple_third(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_third")
    }
    return tripleBox.third
}

@_cdecl("kk_triple_to_string")
public func kk_triple_to_string(_ tripleRaw: Int) -> UnsafeMutableRawPointer {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_to_string")
    }
    let firstStr = runtimeElementToString(tripleBox.first)
    let secondStr = runtimeElementToString(tripleBox.second)
    let thirdStr = runtimeElementToString(tripleBox.third)
    let str = "(\(firstStr), \(secondStr), \(thirdStr))"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Pair/Triple toList (STDLIB-121)

@_cdecl("kk_pair_toList")
public func kk_pair_toList(_ pairRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: [pairBox.first, pairBox.second]))
}

@_cdecl("kk_triple_toList")
public func kk_triple_toList(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: [tripleBox.first, tripleBox.second, tripleBox.third]))
}

// MARK: - Array conversion functions (STDLIB-087)

@_cdecl("kk_array_toList")
public func kk_array_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

@_cdecl("kk_array_toMutableList")
public func kk_array_toMutableList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_toMutableList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

@_cdecl("kk_list_toTypedArray")
public func kk_list_toTypedArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toTypedArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

// MARK: - List to primitive array conversions (STDLIB-LIST-PRIM-ARRAY)

/// Collection<Boolean>.toBooleanArray(): BooleanArray
@_cdecl("kk_list_toBooleanArray")
public func kk_list_toBooleanArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toBooleanArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_bool(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Short>.toShortArray(): ShortArray
@_cdecl("kk_list_toShortArray")
public func kk_list_toShortArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toShortArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Double>.toDoubleArray(): DoubleArray
@_cdecl("kk_list_toDoubleArray")
public func kk_list_toDoubleArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toDoubleArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_double(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Float>.toFloatArray(): FloatArray
@_cdecl("kk_list_toFloatArray")
public func kk_list_toFloatArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toFloatArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_float(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Int>.toIntArray(): IntArray
@_cdecl("kk_list_toIntArray")
public func kk_list_toIntArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toIntArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Long>.toLongArray(): LongArray
@_cdecl("kk_list_toLongArray")
public func kk_list_toLongArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toLongArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_long(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Byte>.toByteArray(): ByteArray
@_cdecl("kk_list_toByteArray")
public func kk_list_toByteArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toByteArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        // Byte values are stored as Int8-range integers (unboxed or raw);
        // preserve the sign-extended bit pattern as Kotlin Byte semantics require.
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UByte>.toUByteArray(): UByteArray
@_cdecl("kk_list_toUByteArray")
public func kk_list_toUByteArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUByteArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UShort>.toUShortArray(): UShortArray
@_cdecl("kk_list_toUShortArray")
public func kk_list_toUShortArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUShortArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UInt>.toUIntArray(): UIntArray
@_cdecl("kk_list_toUIntArray")
public func kk_list_toUIntArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUIntArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<ULong>.toULongArray(): ULongArray
@_cdecl("kk_list_toULongArray")
public func kk_list_toULongArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toULongArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_long(elem)
    }
    return registerRuntimeObject(box)
}

// MARK: - Primitive array to List conversions

/// IntArray.toList(): List<Int>
@_cdecl("kk_intArray_toList")
public func kk_intArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_intArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// LongArray.toList(): List<Long>
@_cdecl("kk_longArray_toList")
public func kk_longArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_longArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ByteArray.toList(): List<Byte>
@_cdecl("kk_byteArray_toList")
public func kk_byteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ShortArray.toList(): List<Short>
@_cdecl("kk_shortArray_toList")
public func kk_shortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_shortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UIntArray.toList(): List<UInt>
@_cdecl("kk_uIntArray_toList")
public func kk_uIntArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ULongArray.toList(): List<ULong>
@_cdecl("kk_uLongArray_toList")
public func kk_uLongArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// DoubleArray.toList(): List<Double>
@_cdecl("kk_doubleArray_toList")
public func kk_doubleArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_doubleArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// FloatArray.toList(): List<Float>
@_cdecl("kk_floatArray_toList")
public func kk_floatArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_floatArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// BooleanArray.toList(): List<Boolean>
@_cdecl("kk_booleanArray_toList")
public func kk_booleanArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_booleanArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// CharArray.toList(): List<Char>
@_cdecl("kk_charArray_toList")
public func kk_charArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_charArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UByteArray.toList(): List<UByte>
@_cdecl("kk_uByteArray_toList")
public func kk_uByteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UShortArray.toList(): List<UShort>
@_cdecl("kk_uShortArray_toList")
public func kk_uShortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ByteArray.asUByteArray(): UByteArray view
@_cdecl("kk_byteArray_asUByteArray")
public func kk_byteArray_asUByteArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_asUByteArray")
    }
    return arrayRaw
}

/// ShortArray.asUShortArray(): UShortArray view
@_cdecl("kk_shortArray_asUShortArray")
public func kk_shortArray_asUShortArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_shortArray_asUShortArray")
    }
    return arrayRaw
}

/// IntArray.asUIntArray(): UIntArray view
@_cdecl("kk_intArray_asUIntArray")
public func kk_intArray_asUIntArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_intArray_asUIntArray")
    }
    return arrayRaw
}

/// LongArray.asULongArray(): ULongArray view
@_cdecl("kk_longArray_asULongArray")
public func kk_longArray_asULongArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_longArray_asULongArray")
    }
    return arrayRaw
}

/// UByteArray.asList(): List<UByte>
@_cdecl("kk_uByteArray_asList")
public func kk_uByteArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// UShortArray.asList(): List<UShort>
@_cdecl("kk_uShortArray_asList")
public func kk_uShortArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// UIntArray.asList(): List<UInt>
@_cdecl("kk_uIntArray_asList")
public func kk_uIntArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// ULongArray.asList(): List<ULong>
@_cdecl("kk_uLongArray_asList")
public func kk_uLongArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

// MARK: - Unsigned primitive array to signed primitive array views
//
// Kotlin `asByteArray` / `asShortArray` (and the other width-matched pairs below) are
// *views* on the same storage: the signed and unsigned array types re-use the same
// underlying runtime array; mutations are shared and bit patterns are not reencoded.

/// UByteArray.asByteArray(): ByteArray
@_cdecl("kk_uByteArray_asByteArray")
public func kk_uByteArray_asByteArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_asByteArray")
    }
    return arrayRaw
}

/// UShortArray.asShortArray(): ShortArray
@_cdecl("kk_uShortArray_asShortArray")
public func kk_uShortArray_asShortArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_asShortArray")
    }
    return arrayRaw
}

/// UIntArray.asIntArray(): IntArray view
@_cdecl("kk_uIntArray_asIntArray")
public func kk_uIntArray_asIntArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_asIntArray")
    }
    return arrayRaw
}

/// ULongArray.asLongArray(): LongArray view
@_cdecl("kk_uLongArray_asLongArray")
public func kk_uLongArray_asLongArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_asLongArray")
    }
    return arrayRaw
}

// MARK: - Primitive array size property

/// IntArray.size: Int
@_cdecl("kk_intArray_size")
public func kk_intArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// LongArray.size: Int
@_cdecl("kk_longArray_size")
public func kk_longArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ByteArray.size: Int
@_cdecl("kk_byteArray_size")
public func kk_byteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ShortArray.size: Int
@_cdecl("kk_shortArray_size")
public func kk_shortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UIntArray.size: Int
@_cdecl("kk_uIntArray_size")
public func kk_uIntArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ULongArray.size: Int
@_cdecl("kk_uLongArray_size")
public func kk_uLongArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// DoubleArray.size: Int
@_cdecl("kk_doubleArray_size")
public func kk_doubleArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// FloatArray.size: Int
@_cdecl("kk_floatArray_size")
public func kk_floatArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// BooleanArray.size: Int
@_cdecl("kk_booleanArray_size")
public func kk_booleanArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// CharArray.size: Int
@_cdecl("kk_charArray_size")
public func kk_charArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UByteArray.size: Int
@_cdecl("kk_uByteArray_size")
public func kk_uByteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UShortArray.size: Int
@_cdecl("kk_uShortArray_size")
public func kk_uShortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

// MARK: - Array binarySearch overloads (TYPE-103)

@inline(__always)
private func runtimeArrayBinarySearch(
    _ arrayRaw: Int,
    element: Int,
    fromIndex: Int,
    toIndex: Int,
    compare: (Int, Int) -> Int,
    functionName: String
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    return runtimeBinarySearch(
        elements: array.elements,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: compare
    )
}

@_cdecl("kk_array_binarySearch")
public func kk_array_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: runtimeCompareValues,
        functionName: "kk_array_binarySearch"
    )
}

@_cdecl("kk_intArray_binarySearch")
public func kk_intArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_intArray_binarySearch"
    )
}

@_cdecl("kk_longArray_binarySearch")
public func kk_longArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .long) },
        functionName: "kk_longArray_binarySearch"
    )
}

@_cdecl("kk_byteArray_binarySearch")
public func kk_byteArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_byteArray_binarySearch"
    )
}

@_cdecl("kk_shortArray_binarySearch")
public func kk_shortArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_shortArray_binarySearch"
    )
}

@_cdecl("kk_uIntArray_binarySearch")
public func kk_uIntArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uIntArray_binarySearch"
    )
}

@_cdecl("kk_uLongArray_binarySearch")
public func kk_uLongArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .ulong) },
        functionName: "kk_uLongArray_binarySearch"
    )
}

@_cdecl("kk_doubleArray_binarySearch")
public func kk_doubleArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .double) },
        functionName: "kk_doubleArray_binarySearch"
    )
}

@_cdecl("kk_floatArray_binarySearch")
public func kk_floatArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .float) },
        functionName: "kk_floatArray_binarySearch"
    )
}

@_cdecl("kk_booleanArray_binarySearch")
public func kk_booleanArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .boolean) },
        functionName: "kk_booleanArray_binarySearch"
    )
}

@_cdecl("kk_charArray_binarySearch")
public func kk_charArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .char) },
        functionName: "kk_charArray_binarySearch"
    )
}

@_cdecl("kk_uByteArray_binarySearch")
public func kk_uByteArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uByteArray_binarySearch"
    )
}

@_cdecl("kk_uShortArray_binarySearch")
public func kk_uShortArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uShortArray_binarySearch"
    )
}

// MARK: - ArrayDeque Functions (STDLIB-240)

@_cdecl("kk_arraydeque_new")
public func kk_arraydeque_new() -> Int {
    registerRuntimeObject(RuntimeArrayDequeBox(elements: []))
}

@_cdecl("kk_arraydeque_addFirst")
public func kk_arraydeque_addFirst(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.elements.insert(element, at: 0)
    return 0
}

@_cdecl("kk_arraydeque_addLast")
public func kk_arraydeque_addLast(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.elements.append(element)
    return 0
}

@_cdecl("kk_arraydeque_removeFirst")
public func kk_arraydeque_removeFirst(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements.removeFirst()
}

@_cdecl("kk_arraydeque_removeLast")
public func kk_arraydeque_removeLast(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements.removeLast()
}

@_cdecl("kk_arraydeque_first")
public func kk_arraydeque_first(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements[0]
}

@_cdecl("kk_arraydeque_last")
public func kk_arraydeque_last(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements[deque.elements.count - 1]
}

@_cdecl("kk_arraydeque_size")
public func kk_arraydeque_size(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    return deque.elements.count
}

@_cdecl("kk_arraydeque_isEmpty")
public func kk_arraydeque_isEmpty(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(deque.elements.isEmpty ? 1 : 0)
}

@_cdecl("kk_arraydeque_toString")
public func kk_arraydeque_toString(_ dequeRaw: Int) -> UnsafeMutableRawPointer {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = deque.elements.map { elem -> String in
        runtimeElementToString(elem)
    }
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Array utility functions (STDLIB-089)

@_cdecl("kk_array_copyOf")
public func kk_array_copyOf(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf")
    }
    let box = RuntimeArrayBox(length: array.elements.count)
    for (i, elem) in array.elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOf_newSize")
public func kk_array_copyOf_newSize(_ arrayRaw: Int, _ newSize: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf_newSize")
    }
    let targetSize = max(0, newSize)
    let box = RuntimeArrayBox(length: targetSize)
    let copiedCount = min(array.elements.count, targetSize)
    for i in 0 ..< copiedCount {
        box.elements[i] = array.elements[i]
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOf_newSize_init")
public func kk_array_copyOf_newSize_init(
    _ arrayRaw: Int,
    _ newSize: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf_newSize_init")
    }
    let targetSize = max(0, newSize)
    let box = RuntimeArrayBox(length: targetSize)
    let copiedCount = min(array.elements.count, targetSize)
    for i in 0 ..< copiedCount {
        box.elements[i] = array.elements[i]
    }
    if copiedCount < targetSize {
        for index in copiedCount ..< targetSize {
            var thrown = 0
            let value = runtimeInvokeCollectionLambda1(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                value: index,
                outThrown: &thrown
            )
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            box.elements[index] = maybeUnbox(value)
        }
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOfRange")
public func kk_array_copyOfRange(_ arrayRaw: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOfRange")
    }
    // Kotlin semantics: validate boundaries
    let size = array.elements.count
    let from = max(0, min(fromIndex, size))
    let to = max(from, min(toIndex, size))
    let count = to - from
    let box = RuntimeArrayBox(length: count)
    for i in 0 ..< count {
        box.elements[i] = array.elements[from + i]
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_reversedArray")
public func kk_array_reversedArray(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_reversedArray")
    }
    let box = RuntimeArrayBox(length: array.elements.count)
    for (index, element) in array.elements.reversed().enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_sortedArray")
public func kk_array_sortedArray(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_sortedArray")
    }
    let sorted = array.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let box = RuntimeArrayBox(length: sorted.count)
    for (index, element) in sorted.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_sortedArrayDescending")
public func kk_array_sortedArrayDescending(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_sortedArrayDescending")
    }
    let sorted = array.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison > 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let box = RuntimeArrayBox(length: sorted.count)
    for (index, element) in sorted.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyInto")
public func kk_array_copyInto(
    _ arrayRaw: Int,
    _ destinationRaw: Int,
    _ destinationOffset: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    guard let source = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyInto")
    }
    guard let destination = runtimeArrayBox(from: destinationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid destination handle in kk_array_copyInto")
    }

    let sourceSize = source.elements.count
    let start = max(0, min(startIndex, sourceSize))
    let end = max(start, min(endIndex, sourceSize))
    let destinationStart = max(0, min(destinationOffset, destination.elements.count))
    let count = min(end - start, destination.elements.count - destinationStart)
    guard count > 0 else {
        return destinationRaw
    }

    let copied = Array(source.elements[start ..< start + count])
    for index in 0 ..< count {
        destination.elements[destinationStart + index] = copied[index]
    }
    return destinationRaw
}

@_cdecl("kk_array_fill")
public func kk_array_fill(_ arrayRaw: Int, _ value: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_fill")
    }
    for i in 0 ..< array.elements.count {
        array.elements[i] = value
    }
    return 0
}

@_cdecl("kk_array_contentEquals")
public func kk_array_contentEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return kk_box_bool(0)
    }
    guard let other = runtimeArrayBox(from: otherRaw) else {
        return kk_box_bool(0)
    }
    
    // Quick size check
    if array.elements.count != other.elements.count {
        return kk_box_bool(0)
    }
    
    // Element-by-element comparison
    for i in 0 ..< array.elements.count {
        if !runtimeValuesEqual(array.elements[i], other.elements[i]) {
            return kk_box_bool(0)
        }
    }
    
    return kk_box_bool(1)
}

private func runtimeCollectionStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buffer in
        kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count))
    }
}

private func runtimeArrayContentToString(
    _ arrayRaw: Int,
    renderElement: (Int) -> String
) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return runtimeCollectionStringPointer("[]")
    }
    let rendered = array.elements.map(renderElement).joined(separator: ", ")
    return runtimeCollectionStringPointer("[\(rendered)]")
}

@_cdecl("kk_array_contentToString")
public func kk_array_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw, renderElement: runtimeElementToString)
}

@_cdecl("kk_intArray_contentToString")
public func kk_intArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int32(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_longArray_contentToString")
public func kk_longArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int64($0)) }
}

@_cdecl("kk_byteArray_contentToString")
public func kk_byteArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int8(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_shortArray_contentToString")
public func kk_shortArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int16(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_uIntArray_contentToString")
public func kk_uIntArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt32(bitPattern: Int32(truncatingIfNeeded: $0))) }
}

@_cdecl("kk_uLongArray_contentToString")
public func kk_uLongArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt64(bitPattern: Int64($0))) }
}

@_cdecl("kk_doubleArray_contentToString")
public func kk_doubleArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { runtimeFormatFloatingPoint(kk_bits_to_double($0)) }
}

@_cdecl("kk_floatArray_contentToString")
public func kk_floatArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { runtimeFormatFloatingPoint(kk_bits_to_float($0)) }
}

@_cdecl("kk_booleanArray_contentToString")
public func kk_booleanArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { $0 != 0 ? "true" : "false" }
}

@_cdecl("kk_charArray_contentToString")
public func kk_charArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { UnicodeScalar($0).map(String.init) ?? "?" }
}

@_cdecl("kk_uByteArray_contentToString")
public func kk_uByteArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt8(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_uShortArray_contentToString")
public func kk_uShortArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt16(truncatingIfNeeded: $0)) }
}

private struct RuntimeArrayDeepEqualityPair: Hashable {
    let lhs: Int
    let rhs: Int
}

private func runtimePlainArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer,
          let box = tryCast(pointer, to: RuntimeArrayBox.self),
          type(of: box) == RuntimeArrayBox.self
    else {
        return nil
    }
    return box
}

private func runtimeArrayBoxesDeepEqual(
    lhsRaw: Int,
    rhsRaw: Int,
    lhs: RuntimeArrayBox,
    rhs: RuntimeArrayBox,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    guard lhs.elements.count == rhs.elements.count else {
        return false
    }
    let pair = RuntimeArrayDeepEqualityPair(lhs: lhsRaw, rhs: rhsRaw)
    guard visited.insert(pair).inserted else {
        return true
    }
    defer { visited.remove(pair) }

    for index in lhs.elements.indices {
        if !runtimeValuesDeepEqual(lhs.elements[index], rhs.elements[index], visited: &visited) {
            return false
        }
    }
    return true
}

private func runtimeValuesDeepEqual(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    if lhsRaw == rhsRaw {
        return true
    }
    if let lhs = runtimePlainArrayBox(from: lhsRaw),
       let rhs = runtimePlainArrayBox(from: rhsRaw)
    {
        return runtimeArrayBoxesDeepEqual(
            lhsRaw: lhsRaw,
            rhsRaw: rhsRaw,
            lhs: lhs,
            rhs: rhs,
            visited: &visited
        )
    }
    return runtimeValuesEqual(lhsRaw, rhsRaw)
}

@_cdecl("kk_array_contentDeepEquals")
public func kk_array_contentDeepEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return kk_box_bool(runtimeArrayBox(from: otherRaw) == nil ? 1 : 0)
    }
    guard let other = runtimeArrayBox(from: otherRaw) else {
        return kk_box_bool(0)
    }
    var visited: Set<RuntimeArrayDeepEqualityPair> = []
    return kk_box_bool(runtimeArrayBoxesDeepEqual(
        lhsRaw: arrayRaw,
        rhsRaw: otherRaw,
        lhs: array,
        rhs: other,
        visited: &visited
    ) ? 1 : 0)
}

@_cdecl("kk_array_contentHashCode")
public func kk_array_contentHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }

    var result: Int = 1
    for element in array.elements {
        result = 31 * result + kk_any_hashCode(element, 0)
    }

    return result
}

private func runtimeArrayBoxDeepToString(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> String {
    guard visited.insert(raw).inserted else {
        return "[...]"
    }
    defer { visited.remove(raw) }

    let rendered = box.elements
        .map { runtimeValueDeepToString($0, visited: &visited) }
        .joined(separator: ", ")
    return "[\(rendered)]"
}

private func runtimeValueDeepToString(_ raw: Int, visited: inout Set<Int>) -> String {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepToString(raw: raw, box: array, visited: &visited)
    }
    return runtimeElementToString(raw)
}

private func runtimeArrayStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buffer in
        kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count))
    }
}

@_cdecl("kk_array_contentDeepToString")
public func kk_array_contentDeepToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return runtimeArrayStringPointer("null")
    }
    var visited: Set<Int> = []
    return runtimeArrayStringPointer(runtimeArrayBoxDeepToString(raw: arrayRaw, box: array, visited: &visited))
}

private func runtimeArrayBoxDeepHash(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> Int {
    guard visited.insert(raw).inserted else {
        return 0
    }
    defer { visited.remove(raw) }

    var result = 1
    for element in box.elements {
        result = 31 &* result &+ runtimeValueDeepHash(element, visited: &visited)
    }
    return result
}

private func runtimeValueDeepHash(_ raw: Int, visited: inout Set<Int>) -> Int {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepHash(raw: raw, box: array, visited: &visited)
    }
    return kk_any_hashCode(raw, 0)
}

@_cdecl("kk_array_contentDeepHashCode")
public func kk_array_contentDeepHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    var visited: Set<Int> = []
    return runtimeArrayBoxDeepHash(raw: arrayRaw, box: array, visited: &visited)
}

// MARK: - asSequence (STDLIB-471)

@_cdecl("kk_list_asSequence")
public func kk_list_asSequence(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_asSequence")
    }
    // KNOWN DEVIATION: Kotlin's `Iterable.asSequence()` is lazy and delegates
    // to `iterator()` at iteration time, so mutations between the call and
    // iteration are observable.  Our implementation captures a COW snapshot of
    // `list.elements` (a Swift Array value) at the point of call, so later
    // mutations to the original list are NOT reflected in the sequence.
    // This is an intentional simplification for the current runtime; a future
    // version may store the list reference and obtain an iterator lazily.
    let seq = RuntimeSequenceBox(steps: [.source(elements: list.elements)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_array_asSequence")
public func kk_array_asSequence(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_asSequence")
    }
    // Same COW-snapshot semantics (known Kotlin deviation) as kk_list_asSequence above.
    let seq = RuntimeSequenceBox(steps: [.source(elements: array.elements)])
    return registerRuntimeObject(seq)
}

// MARK: - STDLIB-533: List?.orEmpty()

/// Cached singleton handle for the empty list, allocated once on first use.
private let cachedEmptyListHandle: Int = registerRuntimeObject(RuntimeListBox(elements: []))

@_cdecl("kk_list_orEmpty")
public func kk_list_orEmpty(_ listRaw: Int) -> Int {
    if listRaw == runtimeNullSentinelInt || listRaw == 0 {
        return cachedEmptyListHandle
    }
    return listRaw
}

// MARK: - STDLIB-532: Map?.orEmpty()

/// Cached singleton handle for the empty map, allocated once on first use.
private let cachedEmptyMapHandle: Int = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

@_cdecl("kk_map_orEmpty")
public func kk_map_orEmpty(_ mapRaw: Int) -> Int {
    if mapRaw == runtimeNullSentinelInt || mapRaw == 0 {
        return cachedEmptyMapHandle
    }
    return mapRaw
}

// MARK: - Iterable / Collection mutable conversion APIs (STDLIB-021)

/// Generic `Iterable<T>.toMutableList()` that accepts any collection handle (List, Set, etc.).
@_cdecl("kk_iterable_toMutableList")
public func kk_iterable_toMutableList(_ iterableRaw: Int) -> Int {
    if let elements = runtimeCollectionElements(from: iterableRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    if let array = runtimeArrayBox(from: iterableRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: array.elements))
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

/// Generic `Iterable<T>.toMutableSet()` that accepts any collection handle (List, Set, etc.).
@_cdecl("kk_iterable_toMutableSet")
public func kk_iterable_toMutableSet(_ iterableRaw: Int) -> Int {
    if let elements = runtimeCollectionElements(from: iterableRaw) {
        return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
    }
    if let array = runtimeArrayBox(from: iterableRaw) {
        return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(array.elements)))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: []))
}

/// Generic `Iterable<T>.toHashSet()` that accepts any collection handle (List, Set, etc.).
/// Semantically equivalent to toMutableSet() at the runtime level.
@_cdecl("kk_iterable_toHashSet")
public func kk_iterable_toHashSet(_ iterableRaw: Int) -> Int {
    if let elements = runtimeCollectionElements(from: iterableRaw) {
        return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)))
    }
    if let array = runtimeArrayBox(from: iterableRaw) {
        return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(array.elements)))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: []))
}

/// Generic `Collection<T>.toMutableList()` that accepts any collection handle (List, Set, etc.).
@_cdecl("kk_collection_toMutableList")
public func kk_collection_toMutableList(_ collRaw: Int) -> Int {
    if let elements = runtimeCollectionElements(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    if let array = runtimeArrayBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: array.elements))
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

/// Generic `Iterable.asSequence()` that accepts any collection handle (List, Set, etc.).
/// Falls back to fatalError only when the handle is truly unrecognized.
@_cdecl("kk_iterable_asSequence")
public func kk_iterable_asSequence(_ iterableRaw: Int) -> Int {
    if let elements = runtimeCollectionElements(from: iterableRaw) {
        let seq = RuntimeSequenceBox(steps: [.source(elements: elements)])
        return registerRuntimeObject(seq)
    }
    if let array = runtimeArrayBox(from: iterableRaw) {
        let seq = RuntimeSequenceBox(steps: [.source(elements: array.elements)])
        return registerRuntimeObject(seq)
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid iterable handle in kk_iterable_asSequence")
}
