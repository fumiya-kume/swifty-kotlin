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
func runtimeUnboxCollectionElements(_ otherRaw: Int) -> [Int] {
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

@_cdecl("kk_list_indices")
public func kk_list_indices(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_op_rangeTo(0, -1)
    }
    return kk_op_rangeTo(0, list.elements.count - 1)
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

@_cdecl("kk_list_lastIndex")
public func kk_list_lastIndex(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return -1
    }
    return list.elements.count - 1
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

@_cdecl("kk_list_is_not_empty")
public func kk_list_is_not_empty(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(list.elements.isEmpty ? 0 : 1)
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

@_cdecl("kk_iterable_joinTo")
public func kk_iterable_joinTo(
    _ iterableRaw: Int,
    _ destinationRaw: Int,
    _ separatorRaw: Int,
    _ prefixRaw: Int,
    _ postfixRaw: Int
) -> Int {
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let elements = runtimeCollectionElements(from: iterableRaw) ?? []
    let rendered = elements.map(runtimeElementToString).joined(separator: separator)
    let stringValue = prefix + rendered + postfix
    let utf8 = Array(stringValue.utf8)
    let stringRaw = utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
    return kk_string_builder_append_obj(destinationRaw, Int(bitPattern: stringRaw))
}

@_cdecl("kk_iterable_joinToString")
public func kk_iterable_joinToString(
    _ iterableRaw: Int,
    _ separatorRaw: Int,
    _ prefixRaw: Int,
    _ postfixRaw: Int
) -> UnsafeMutableRawPointer {
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let elements = runtimeCollectionElements(from: iterableRaw) ?? []
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

@_cdecl("kk_list_single")
public func kk_list_single(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard list.elements.count == 1 else {
        let message = list.elements.isEmpty
            ? "Collection is empty."
            : "Collection has more than one element."
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: message))
        return 0
    }
    return list.elements[0]
}

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

@_cdecl("kk_mutable_list_remove")
public func kk_mutable_list_remove(_ listRaw: Int, _ elem: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          let index = list.elements.firstIndex(where: { runtimeValuesEqual($0, elem) })
    else {
        return kk_box_bool(0)
    }
    list.elements.remove(at: index)
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

@_cdecl("kk_mutable_list_removeFirst")
public func kk_mutable_list_removeFirst(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "List is empty.")
        return 0
    }
    return list.elements.removeFirst()
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

@_cdecl("kk_mutable_list_removeLast")
public func kk_mutable_list_removeLast(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "List is empty.")
        return 0
    }
    return list.elements.removeLast()
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
    let elements = runtimeCollectionElements(from: listRaw) ?? runtimeArrayBox(from: listRaw)?.elements ?? []
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

/// Generic `Iterable<T>.last()` that accepts any collection handle (List, Set, etc.).
@_cdecl("kk_iterable_last")
public func kk_iterable_last(_ iterableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let elements = runtimeCollectionElements(from: iterableRaw) ?? runtimeArrayBox(from: iterableRaw)?.elements ?? []
    guard let last = elements.last else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "Collection is empty."))
        return 0
    }
    return last
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
