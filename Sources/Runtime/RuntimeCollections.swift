
/// Hashable wrapper around an opaque runtime value (`Int`) that uses
/// `kk_any_hashCode` / `runtimeValuesEqual` so value-equal objects (e.g.
/// two distinct String handles with the same content) are treated as
/// equal keys.  Used by Set deduplication, Map key lookup, and Sequence
/// terminal operations (toMap, groupBy).
internal struct RuntimeElementKey: Hashable {
    let value: Int

    func hash(into hasher: inout Hasher) {
        // Keep the runtime's floating-point hash normalization in one helper
        // so every indexed collection uses the same value-level hash.
        hasher.combine(runtimeValueHash(value))
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
        // swiftlint:disable:next for_where
        if seen.insert(RuntimeElementKey(value: element)).inserted {
            unique.append(element)
        }
    }
    return unique
}

func runtimeDeduplicatePreservingOrder(_ values: [RuntimeValue]) -> [RuntimeValue] {
    var seen = Set<RuntimeElementKey>()
    seen.reserveCapacity(values.count)
    var unique: [RuntimeValue] = []
    unique.reserveCapacity(values.count)
    for value in values {
        if seen.insert(RuntimeElementKey(value: value.legacyRawValue)).inserted {
            unique.append(value)
        }
    }
    return unique
}

func runtimeNormalizeMapEntries(keys: [Int], values: [Int]) -> ([Int], [Int]) {
    var normalizedKeys: [Int] = []
    var normalizedValues: [Int] = []
    var keyIndex: [RuntimeElementKey: Int] = [:]
    let count = min(keys.count, values.count)
    keyIndex.reserveCapacity(count)
    for index in 0 ..< count {
        let key = keys[index]
        let value = values[index]
        let runtimeKey = RuntimeElementKey(value: key)
        if let existing = keyIndex[runtimeKey] {
            normalizedValues[existing] = value
        } else {
            keyIndex[runtimeKey] = normalizedKeys.count
            normalizedKeys.append(key)
            normalizedValues.append(value)
        }
    }
    return (normalizedKeys, normalizedValues)
}

// MARK: - List Functions (STDLIB-001)

@_cdecl("__kk_list_of")
public func kk_list_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements), typeID: listRuntimeTypeID)
}

// STDLIB-410: emptyList<T>() - allocates a fresh empty list each call to avoid
// aliasing with mutable collection operations (e.g., kk_mutable_list_add).
@_cdecl("__kk_emptyList")
public func kk_emptyList() -> Int {
    return registerRuntimeObject(RuntimeListBox(elements: []), typeID: listRuntimeTypeID)
}

@_cdecl("__kk_list_size")
public func kk_list_size(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    return list.elements.count
}

@_cdecl("__kk_list_get")
public func kk_list_get(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    guard list.elements.indices.contains(index) else {
        return 0
    }
    return list.elements[index]
}

/// `EnumEntries.get` checks bounds and reports Kotlin's
/// `IndexOutOfBoundsException` instead of using the forgiving generic List
/// bridge, whose zero fallback is reserved for unchecked collection paths.
@_cdecl("__kk_enum_entries_get")
public func kk_enum_entries_get(
    _ listRaw: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw), list.elements.indices.contains(index) else {
        let size = runtimeListBox(from: listRaw)?.elements.count ?? 0
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "Index: \(index), size: \(size)"
        )
        return 0
    }
    return list.elements[index]
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
    if let list = runtimeListBox(from: listRaw) {
        let raw = registerRuntimeObject(
            RuntimeListIteratorBox(
                elements: list.elements,
                removeAction: { index in
                    guard list.elements.indices.contains(index) else { return }
                    list.elements.remove(at: index)
                }
            )
        )
        registerListIteratorItable(raw: raw)
        return raw
    }
    if let set = runtimeSetBox(from: listRaw) {
        let raw = registerRuntimeObject(
            RuntimeListIteratorBox(
                elements: set.elements,
                removeAction: { index in
                    guard set.elements.indices.contains(index) else { return }
                    set.elements.remove(at: index)
                }
            )
        )
        registerListIteratorItable(raw: raw)
        return raw
    }
    if let array = runtimeArrayBox(from: listRaw), type(of: array) == RuntimeArrayBox.self {
        let raw = registerRuntimeObject(RuntimeListIteratorBox(elements: array.elements))
        registerListIteratorItable(raw: raw)
        return raw
    }
    // BUG-231: `listRaw` is none of the native runtime boxes above when it is
    // a hand-written class implementing List/Set/MutableList/MutableSet
    // directly (Sema resolves their `iterator()` to this fast-path bridge —
    // see ControlFlowLowerer.concreteListIteratorFastPath's doc comment —
    // since List/Set are deliberately excluded from the generic dynamic-
    // dispatch iterator path). Without this fallback the object's own
    // `iterator()` override is silently skipped in favor of an iterator over
    // zero elements. Dispatch through the source `Iterable.iterator()` itable
    // slot, the same bridge `kk_iterable_iterator`/`kk_range_iterator` use for
    // the shapes they already handle.
    if let sourceIterator = runtimeSourceIterableIterator(listRaw) {
        return sourceIterator
    }
    let raw = registerRuntimeObject(RuntimeListIteratorBox(elements: []))
    registerListIteratorItable(raw: raw)
    return raw
}

/// Backs both `List.listIterator(index)` and `MutableList.listIterator(index)`
/// (Sema registers the same external link name for both, matching the
/// zero-arg `kk_list_iterator` convention above): a list iterator positioned
/// so the next `next()` call returns the element at `index`.
@_cdecl("kk_list_iterator_at")
public func kk_list_iterator_at(_ listRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        let raw = registerRuntimeObject(RuntimeListIteratorBox(elements: []))
        registerListIteratorItable(raw: raw)
        return raw
    }
    guard (0...list.elements.count).contains(index) else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "Index: \(index), Size: \(list.elements.count)"
        )
        return 0
    }
    let iter = RuntimeListIteratorBox(
        elements: list.elements,
        removeAction: { removedIndex in
            guard list.elements.indices.contains(removedIndex) else { return }
            list.elements.remove(at: removedIndex)
        }
    )
    iter.index = index
    let raw = registerRuntimeObject(iter)
    registerListIteratorItable(raw: raw)
    return raw
}

@_cdecl("kk_list_iterator_hasNext")
public func kk_list_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        // BUG-231: `iterRaw` came from the source-iterator fallback in
        // `kk_list_iterator` above rather than a native `RuntimeListIteratorBox`
        // (e.g. the user's `iterator()` returned its own Iterator object, not
        // one backed by a native list/set). Fall back to the generic
        // kk_iterator_* dispatcher, which knows how to drive it via itable.
        return kk_iterator_hasNext(iterRaw)
    }
    return iter.index < iter.elements.count ? 1 : 0
}

@_cdecl("kk_list_iterator_next")
public func kk_list_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        // BUG-231: see kk_list_iterator_hasNext above.
        return kk_iterator_next(iterRaw)
    }
    guard iter.index < iter.elements.count else {
        return 0
    }
    let value = iter.elements[iter.index]
    iter.index += 1
    return value
}

func runtimeListIteratorRemove(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    _ = iter.removeLastReturned()
    return 0
}

/// Whether the iterator has a valid previous element.
/// The invariant maintained by `kk_list_iterator_next` guarantees
/// `index` is always in `0...elements.count`, but we defensively
/// also check the upper bound so that a corrupted/invalid index
/// cannot lead to an out-of-bounds access in `previous()`.
func listIteratorCanGoBack(_ iter: RuntimeListIteratorBox) -> Bool {
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

@_cdecl("kk_list_iterator_nextIndex")
public func kk_list_iterator_nextIndex(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index
}

@_cdecl("kk_list_iterator_previousIndex")
public func kk_list_iterator_previousIndex(_ iterRaw: Int) -> Int {
    guard let iter = runtimeListIteratorBox(from: iterRaw) else {
        return -1
    }
    return iter.index - 1
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
    let parts = list.values.map { elem -> String in
        runtimeElementToString(elem)
    }
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - List toMap (STDLIB-200)

@inline(__always)
func runtimeMutableCollectionExists(_ destRaw: Int) -> Bool {
    runtimeListBox(from: destRaw) != nil || runtimeSetBox(from: destRaw) != nil
}

@inline(__always)
func runtimeAppendToMutableCollection(_ destRaw: Int, _ element: Int) {
    runtimeAppendToMutableCollection(destRaw, RuntimeValue(raw: element))
}

@inline(__always)
func runtimeAppendToMutableCollection(_ destRaw: Int, _ element: RuntimeValue) {
    if let list = runtimeListBox(from: destRaw) {
        list.values.append(element)
        return
    }
    if let set = runtimeSetBox(from: destRaw) {
        _ = set.insert(rawValue: element.legacyRawValue)
        return
    }
    invalidContainerPanic(#function, "mutable collection")
}

@_cdecl("__kk_mutable_collection_add")
public func kk_mutable_collection_add(_ collectionRaw: Int, _ elem: Int) -> Int {
    if let list = runtimeListBox(from: collectionRaw) {
        var values = list.values
        values.append(runtimeMutableListInsertedValue(for: values, rawValue: elem))
        list.values = values
        return kk_box_bool(1)
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        return kk_box_bool(set.insert(rawValue: elem) ? 1 : 0)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_collection_remove")
public func kk_mutable_collection_remove(_ collectionRaw: Int, _ elem: Int) -> Int {
    if let list = runtimeListBox(from: collectionRaw) {
        guard let index = list.values.firstIndex(where: { runtimeValuesEqual($0.legacyRawValue, elem) }) else {
            return kk_box_bool(0)
        }
        var values = list.values
        values.remove(at: index)
        list.values = values
        return kk_box_bool(1)
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        return kk_box_bool(set.remove(rawValue: elem) ? 1 : 0)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_collection_clear")
public func kk_mutable_collection_clear(_ collectionRaw: Int) -> Int {
    if let list = runtimeListBox(from: collectionRaw) {
        list.values = []
        return 0
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        _ = set.removeAll()
        return 0
    }
    return 0
}

@_cdecl("__kk_mutable_collection_removeAll")
public func kk_mutable_collection_removeAll(_ collectionRaw: Int, _ elementsRaw: Int) -> Int {
    if runtimeListBox(from: collectionRaw) != nil {
        return kk_mutable_list_removeAll(collectionRaw, elementsRaw)
    }
    if runtimeSetBox(from: collectionRaw) != nil {
        return kk_mutable_set_removeAll(collectionRaw, elementsRaw)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_collection_retainAll")
public func kk_mutable_collection_retainAll(_ collectionRaw: Int, _ elementsRaw: Int) -> Int {
    if runtimeListBox(from: collectionRaw) != nil {
        return kk_mutable_list_retainAll(collectionRaw, elementsRaw)
    }
    if runtimeSetBox(from: collectionRaw) != nil {
        return kk_mutable_set_retainAll(collectionRaw, elementsRaw)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_collection_addAll")
public func kk_mutable_collection_addAll(_ collectionRaw: Int, _ elementsRaw: Int) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: elementsRaw) else {
        return kk_box_bool(0)
    }
    if let list = runtimeListBox(from: collectionRaw) {
        if elements.isEmpty {
            return kk_box_bool(0)
        }
        list.elements.append(contentsOf: elements)
        return kk_box_bool(1)
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        var modified = false
        for element in elements {
            if set.insert(rawValue: element) {
                modified = true
            }
        }
        return kk_box_bool(modified ? 1 : 0)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_collection_toCollection")
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

private func runtimeMutableListInsertedValue(for currentValues: [RuntimeValue], rawValue: Int) -> RuntimeValue {
    let isObjectPointer: Bool = if let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) {
        runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
    } else {
        false
    }
    if isObjectPointer,
       let pointer = UnsafeMutableRawPointer(bitPattern: rawValue),
       let charBox = tryCast(pointer, to: RuntimeCharBox.self)
    {
        return RuntimeValue(charScalar: charBox.value)
    }
    if !currentValues.isEmpty,
       currentValues.allSatisfy({ $0.tag == RuntimeValue.charTag })
    {
        return RuntimeValue(charScalar: maybeUnbox(rawValue))
    }
    return RuntimeValue(raw: rawValue)
}

@_cdecl("__kk_mutable_list_add")
public func kk_mutable_list_add(
    _ listRaw: Int,
    _ elem: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    guard !list.isReadOnly else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: nil)
        return kk_box_bool(0)
    }
    var values = list.values
    values.append(runtimeMutableListInsertedValue(for: values, rawValue: elem))
    list.values = values
    return kk_box_bool(1)
}

@_cdecl("__kk_mutable_list_remove")
public func kk_mutable_list_remove(_ listRaw: Int, _ elem: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          let index = list.values.firstIndex(where: { runtimeValuesEqual($0.legacyRawValue, elem) })
    else {
        return kk_box_bool(0)
    }
    var values = list.values
    values.remove(at: index)
    list.values = values
    return kk_box_bool(1)
}

@_cdecl("__kk_mutable_list_removeAt")
public func kk_mutable_list_removeAt(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.values.indices.contains(index)
    else {
        return runtimeNullSentinelInt
    }
    var values = list.values
    let removed = values.remove(at: index)
    list.values = values
    return removed.legacyRawValue
}

@_cdecl("__kk_mutable_list_removeFirst")
public func kk_mutable_list_removeFirst(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw),
          !list.values.isEmpty
    else {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "List is empty.")
        return 0
    }
    var values = list.values
    let removed = values.removeFirst()
    list.values = values
    return removed.legacyRawValue
}

@_cdecl("__kk_mutable_list_removeFirstOrNull")
public func kk_mutable_list_removeFirstOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.values.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    var values = list.values
    let removed = values.removeFirst()
    list.values = values
    return removed.legacyRawValue
}

@_cdecl("__kk_mutable_list_removeLast")
public func kk_mutable_list_removeLast(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw),
          !list.values.isEmpty
    else {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "List is empty.")
        return 0
    }
    var values = list.values
    let removed = values.removeLast()
    list.values = values
    return removed.legacyRawValue
}

@_cdecl("__kk_mutable_list_removeLastOrNull")
public func kk_mutable_list_removeLastOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.values.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    var values = list.values
    let removed = values.removeLast()
    list.values = values
    return removed.legacyRawValue
}

@_cdecl("__kk_mutable_list_clear")
public func kk_mutable_list_clear(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    list.values = []
    return 0
}


@_cdecl("__kk_mutable_list_add_at")
public func kk_mutable_list_add_at(_ listRaw: Int, _ index: Int, _ element: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MutableList reference is null.")
        return 0
    }
    var values = list.values
    guard (0...values.count).contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MutableList index \(index) out of bounds for length \(values.count)."
        )
        return 0
    }
    values.insert(runtimeMutableListInsertedValue(for: values, rawValue: element), at: index)
    list.values = values
    return 0
}

@_cdecl("__kk_mutable_list_addAll_at")
public func kk_mutable_list_addAll_at(
    _ listRaw: Int,
    _ index: Int,
    _ collectionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
    guard let newElements = runtimeCollectionOrArrayElements(from: collectionRaw), !newElements.isEmpty else {
        return kk_box_bool(0)
    }
    list.elements.insert(contentsOf: newElements, at: index)
    return kk_box_bool(1)
}

@_cdecl("__kk_mutable_list_set")
public func kk_mutable_list_set(_ listRaw: Int, _ index: Int, _ element: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MutableList reference is null.")
        return 0
    }
    var values = list.values
    guard values.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MutableList index \(index) out of bounds for length \(values.count)."
        )
        return 0
    }
    let old = values[index]
    values[index] = runtimeMutableListInsertedValue(for: values, rawValue: element)
    list.values = values
    return old.legacyRawValue
}

// MARK: - MutableList shuffle/reverse (STDLIB-206)

@_cdecl("__kk_mutable_list_shuffle")
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

@_cdecl("__kk_mutable_list_reverse")
public func kk_mutable_list_reverse(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return 0
    }
    list.elements.reverse()
    return 0
}

// MARK: - MutableList bulk operations (STDLIB-207)

@_cdecl("__kk_mutable_list_addAll")
public func kk_mutable_list_addAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    kk_mutable_collection_addAll(listRaw, collectionRaw)
}

private func runtimeMutableListAddAllSequence(list: RuntimeListBox, sequenceRaw: Int) -> Int {
    guard let elements = runtimeSequenceSourceElements(from: sequenceRaw) else {
        return kk_box_bool(0)
    }
    if elements.isEmpty {
        return kk_box_bool(0)
    }
    list.elements.append(contentsOf: elements)
    return kk_box_bool(1)
}

private func runtimeMutableSetAddAllSequence(set: RuntimeSetBox, sequenceRaw: Int) -> Int {
    guard let elements = runtimeSequenceSourceElements(from: sequenceRaw) else {
        return kk_box_bool(0)
    }
    var modified = false
    for elem in elements {
        if set.insert(rawValue: elem) {
            modified = true
        }
    }
    return kk_box_bool(modified ? 1 : 0)
}

func runtimeMutableListAddAllSequence(listRaw: Int, sequenceRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    return runtimeMutableListAddAllSequence(list: list, sequenceRaw: sequenceRaw)
}

func runtimeMutableSetAddAllSequence(setRaw: Int, sequenceRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return kk_box_bool(0)
    }
    return runtimeMutableSetAddAllSequence(set: set, sequenceRaw: sequenceRaw)
}

@_cdecl("__kk_mutable_collection_addAll_sequence")
public func kk_mutable_collection_addAll_sequence(_ collectionRaw: Int, _ sequenceRaw: Int) -> Int {
    if let list = runtimeListBox(from: collectionRaw) {
        return runtimeMutableListAddAllSequence(list: list, sequenceRaw: sequenceRaw)
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        return runtimeMutableSetAddAllSequence(set: set, sequenceRaw: sequenceRaw)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_list_addAll_sequence")
public func kk_mutable_list_addAll_sequence(_ listRaw: Int, _ sequenceRaw: Int) -> Int {
    return runtimeMutableListAddAllSequence(listRaw: listRaw, sequenceRaw: sequenceRaw)
}

@_cdecl("__kk_mutable_collection_addAll_iterable")
public func kk_mutable_collection_addAll_iterable(_ collectionRaw: Int, _ iterableRaw: Int) -> Int {
    guard let values = runtimeIterableValues(from: iterableRaw) else {
        return kk_box_bool(0)
    }
    if let list = runtimeListBox(from: collectionRaw) {
        if values.isEmpty {
            return kk_box_bool(0)
        }
        list.values.append(contentsOf: values)
        return kk_box_bool(1)
    }
    if let set = runtimeSetBox(from: collectionRaw) {
        var modified = false
        for value in values {
            if set.insert(rawValue: value.legacyRawValue) {
                modified = true
            }
        }
        return kk_box_bool(modified ? 1 : 0)
    }
    return kk_box_bool(0)
}

@_cdecl("__kk_mutable_list_addAll_iterable")
public func kk_mutable_list_addAll_iterable(_ listRaw: Int, _ iterableRaw: Int) -> Int {
    kk_mutable_collection_addAll_iterable(listRaw, iterableRaw)
}

@_cdecl("__kk_mutable_list_removeAll")
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

@_cdecl("__kk_mutable_list_retainAll")
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
// KSP-428: Keep asReversed lazy so mutations of a MutableList are visible
// through the returned view.
@_cdecl("__kk_list_as_reversed")
public func kk_list_as_reversed(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    return registerRuntimeObject(
        RuntimeListBox(reversedViewOf: list),
        typeID: listRuntimeTypeID
    )
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
    // `list.values` (a Swift Array value) at the point of call, so later
    // mutations to the original list are NOT reflected in the sequence.
    // This is an intentional simplification for the current runtime; a future
    // version may store the list reference and obtain an iterator lazily.
    let seq = RuntimeSequenceBox(steps: [.valueSource(values: list.values)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_array_asSequence")
public func kk_array_asSequence(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_asSequence")
    }
    // Same COW-snapshot semantics (known Kotlin deviation) as kk_list_asSequence above.
    let seq = RuntimeSequenceBox(steps: [.valueSource(values: array.values)])
    return registerRuntimeObject(seq)
}

// MARK: - Iterable / Collection mutable conversion APIs (STDLIB-021)

/// Generic `Iterable<T>.toMutableSet()` that accepts any collection handle (List, Set, etc.).
@_cdecl("__kk_iterable_toMutableSet")
public func kk_iterable_toMutableSet(_ iterableRaw: Int) -> Int {
    if let values = runtimeIterableValues(from: iterableRaw) {
        return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: []))
}

/// HashSet copy-constructor storage with an independent backing box.
@_cdecl("__kk_iterable_toHashSet")
public func kk_iterable_toHashSet(_ iterableRaw: Int) -> Int {
    let values = runtimeIterableValues(from: iterableRaw) ?? []
    return registerRuntimeObject(
        RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)),
        typeID: hashSetRuntimeTypeID
    )
}

/// Generic `Iterable<T>.last()` that accepts any collection handle (List, Set, etc.).
@_cdecl("__kk_iterable_last")
public func kk_iterable_last(_ iterableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let values = runtimeIterableValues(from: iterableRaw) ?? []
    guard let last = values.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Collection is empty."))
        return 0
    }
    return last.legacyRawValue
}

/// Generic `Collection<T>.toMutableList()` that accepts any collection handle
/// (List, Set, Array, and the generic iterable handles such as
/// `String.asIterable()`).
@_cdecl("__kk_collection_toMutableList")
public func kk_collection_toMutableList(_ collRaw: Int) -> Int {
    if let values = runtimeCollectionOrArrayValues(from: collRaw) ?? runtimeIterableValues(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(values: values))
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

@_cdecl("__kk_collection_toTypedArray")
public func kk_collection_toTypedArray(_ collRaw: Int) -> Int {
    let values = runtimeCollectionOrArrayValues(from: collRaw) ?? runtimeIterableValues(from: collRaw) ?? []
    let box = RuntimeArrayBox(length: values.count)
    box.values = values
    return registerRuntimeObject(box)
}
