/// `Collection` -> `Iterable` supertype edge, registered once so that boxes
/// tagged as `List`/`Set` answer `is Collection<*>` / `is Iterable<*>` (and the
/// erased `as Iterable<T>` cast) through the ordinary assignability walk.
private let collectionRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.Collection")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
    )
    return id
}()

let listRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.List")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

let setRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.Set")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

/// Nominal identity for source-backed `kotlin.collections.HashSet` instances.
/// Ordinary Set factories keep using `setRuntimeTypeID`; only HashSet
/// constructors opt into this more specific identity.
let hashSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.HashSet")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    )
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.AbstractMutableSet")
    )
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

// User-defined subclasses of LinkedHashSet are allocated as RuntimeObjectBox
// instances. Keep the nominal ID available so runtimeSetBox can lazily attach
// their storage even when library superclass initializers are not emitted.
let linkedHashSetRuntimeTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.LinkedHashSet"
)

private let mapEntryRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.Map.Entry".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

private let comparableRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")

private let mapRuntimeTypeIDs: (map: Int64, mutableMap: Int64, hashMap: Int64) = {
    let mapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map")
    let mutableMapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableMap")
    let hashMapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.HashMap")
    runtimeRegisterTypeEdge(childTypeID: mutableMapID, parentTypeID: mapID)
    runtimeRegisterTypeEdge(childTypeID: hashMapID, parentTypeID: mutableMapID)
    return (mapID, mutableMapID, hashMapID)
}()

let mapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.map
let mutableMapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.mutableMap
let hashMapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.hashMap

private let runtimeCollectionSizeInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Collection"
)
private let runtimeMapSizeInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Map"
)
// These slots are the generated interface property getter slots in the current
// bundled layout: `size`'s slot is `Collection`/`Map`'s own vtableSize (its
// method-slot count), since KIRInterfacePropertyDispatch.swift lays property
// getters out right after an interface's own method slots.
//
// Collection's own vtable methods are isEmpty/contains/iterator/containsAll
// (4 slots) -- KSP-960 (source-backing Collection.random/randomOrNull as
// top-level extensions in Collections.kt) removed the two synthetic
// Collection.random/randomOrNull member registrations that previously
// contributed 2 more vtable slots here, so this dropped from 6 to 4. Map's
// own vtable method count (2 slots) is untouched by KSP-960, which only
// changes Collection's synthetic member registration.
private let runtimeCollectionSizeGetterSlot = 4
private let runtimeMapSizeGetterSlot = 2

/// Source-defined Collection/Map implementations expose `size` through the
/// same dynamic interface-property getter table used by ordinary Kotlin code.
/// Built-in list/set/map boxes continue to use their direct fast paths.
@inline(__always)
func runtimeSourceCollectionSize(_ rawValue: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeCollectionSizeInterfaceTypeID),
        runtimeCollectionSizeGetterSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Collection.size dispatch threw exception handle \(thrown)")
    }
    return result
}

@inline(__always)
func runtimeSourceMapSize(_ rawValue: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMapSizeInterfaceTypeID),
        runtimeMapSizeGetterSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map.size dispatch threw exception handle \(thrown)")
    }
    return result
}

@inline(__always)
func runtimeMapEntryNew(key: Int, value: Int) -> Int {
    let raw = kk_pair_new(key, value)
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    return raw
}

@inline(__always)
func runtimeMutableMapEntryNew(mapRaw: Int, key: Int, value: Int) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(first: key, second: value))
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       let pairBox = tryCast(pointer, to: RuntimePairBox.self) {
        pairBox.mutableMapRaw = mapRaw
        pairBox.mutableMapKey = key
    }
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    return raw
}

@inline(__always)
func runtimeIsMapEntry(rawValue: Int) -> Bool {
    runtimeObjectTypeID(rawValue: rawValue) == mapEntryRuntimeTypeID
}

func runtimeListBox(from rawValue: Int) -> RuntimeListBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListBox.self)
}

func runtimeMapBox(from rawValue: Int) -> RuntimeMapBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapBox.self)
}

func runtimeSetBox(from rawValue: Int) -> RuntimeSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        return setBox
    }
    if let objectBox = tryCast(ptr, to: RuntimeObjectBox.self) {
        if let backingSetBox = objectBox.backingSetBox {
            return backingSetBox
        }
        if let objectTypeID = runtimeObjectTypeID(rawValue: rawValue),
           runtimeIsAssignable(
               sourceTypeID: objectTypeID,
               targetTypeID: linkedHashSetRuntimeTypeID
           ) {
            let backingSetBox = RuntimeSetBox(elements: [])
            objectBox.backingSetBox = backingSetBox
            return backingSetBox
        }
    }
    return nil
}

func runtimeArrayDequeBox(from rawValue: Int) -> RuntimeArrayDequeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeArrayDequeBox.self)
}

func runtimeCollectionElements(from rawValue: Int) -> [Int]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.elements
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.elements
    }
    return nil
}

func runtimeCollectionValues(from rawValue: Int) -> [RuntimeValue]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.values
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.values
    }
    return nil
}

func runtimeCollectionOrArrayElements(from rawValue: Int) -> [Int]? {
    if let elements = runtimeCollectionElements(from: rawValue) {
        return elements
    }
    // runtimeSequenceSourceElements covers RuntimeSequenceBox, source Sequence
    // objects (RuntimeObjectBox), List, Set, and arrays, while excluding
    // RuntimeObjectBox instances that are not actually arrays.
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    return nil
}

func runtimeCollectionOrArrayValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    return nil
}

func runtimeIterableValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let indexingIterable = runtimeIndexingIterableBox(from: rawValue),
       let list = runtimeListBox(from: indexingIterable.listRaw)
    {
        return list.values.enumerated().map { index, element in
            RuntimeValue(raw: runtimeIndexedValueNew(index: index, value: element))
        }
    }
    // runtimeSequenceSourceValues handles RuntimeSequenceBox, source Sequence
    // objects, List, Set, and arrays without misclassifying RuntimeObjectBox.
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    // Kotlin source implementations of Iterable (for example
    // `String.asIterable()`) are ordinary objects with an Iterable itable, not
    // runtime collection boxes or Sequence objects. Drive their iterator
    // through the same dynamic interface used by generic for-loops.
    if let iteratorRaw = runtimeSourceIterableIterator(rawValue) {
        var values: [RuntimeValue] = []
        while kk_iterator_hasNext(iteratorRaw, nil) != 0 {
            let element = kk_iterator_next(iteratorRaw, nil)
            values.append(runtimeSourceIteratorValue(element, iteratorRaw: iteratorRaw))
        }
        return values
    }
    return nil
}

private let charSequenceIteratorTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.text.CharSequenceCharIterator"
)
private let charIteratorTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.CharIterator"
)

/// Source-backed `CharIterator` returns its concrete Char representation at
/// the iterator ABI boundary. Preserve that type when a generic runtime bridge
/// materializes the iterator as `RuntimeValue`.
func runtimeSourceIteratorValue(_ rawValue: Int, iteratorRaw: Int) -> RuntimeValue {
    let isCharSequenceIterator: Bool = if let iteratorTypeID = runtimeObjectTypeID(rawValue: iteratorRaw) {
        iteratorTypeID == charSequenceIteratorTypeID
            || runtimeIsAssignable(sourceTypeID: iteratorTypeID, targetTypeID: charIteratorTypeID)
    } else {
        false
    }
    if isCharSequenceIterator {
        return RuntimeValue(charScalar: kk_unbox_char(rawValue))
    }
    return RuntimeValue(raw: rawValue)
}

func runtimeIterableElements(from rawValue: Int) -> [Int]? {
    runtimeIterableValues(from: rawValue)?.map(\.legacyRawValue)
}

func runtimeListIteratorBox(from rawValue: Int) -> RuntimeListIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListIteratorBox.self)
}

func runtimeIndexingIterableBox(from rawValue: Int) -> RuntimeIndexingIterableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeIndexingIterableBox.self)
}

func runtimeMapIteratorBox(from rawValue: Int) -> RuntimeMapIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapIteratorBox.self)
}

func runtimeMutableMapIteratorBox(from rawValue: Int) -> RuntimeMutableMapIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMutableMapIteratorBox.self)
}

func runtimeIndexingIteratorBox(from rawValue: Int) -> RuntimeIndexingIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeIndexingIteratorBox.self)
}

func runtimeMapArrayPair(
    keysRaw: Int,
    valuesRaw: Int
) -> (keys: [Int], values: [Int])? {
    guard let keysArray = runtimeArrayBox(from: keysRaw),
          let valuesArray = runtimeArrayBox(from: valuesRaw)
    else {
        return nil
    }
    return (keysArray.elements, valuesArray.elements)
}

func registerRuntimeObject(_ box: AnyObject) -> Int {
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    let raw = Int(bitPattern: opaque)
    maybeRegisterCollectionIterableItable(raw: raw, box: box)
    if box is RuntimeStringBox {
        runtimeRegisterCharSequenceItable(raw)
    }
    return raw
}

func registerRuntimeObject(_ box: AnyObject, typeID: Int64) -> Int {
    let raw = registerRuntimeObject(box)
    runtimeRegisterObjectType(rawValue: raw, classID: typeID)
    return raw
}

func registerRuntimeObject(_ box: RuntimeMapBox) -> Int {
    registerRuntimeObject(box, typeID: mapRuntimeTypeID)
}

private let runtimeIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")
private let runtimeListIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.ListIterator")
private let runtimeMutableIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterator")
private let runtimeIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
private let runtimeMutableIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterable")
private let runtimeSequenceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")

/// Register the `kotlin.collections.Iterator` itable on a raw object handle.
func registerIteratorItable(
    raw: Int,
    hasNext: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    next: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    remove: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int)? = nil,
    mutableIterator: Bool = false
) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeIteratorInterfaceTypeID), 0)
    let hasNextPtr = unsafeBitCast(hasNext, to: Int.self)
    _ = kk_object_register_itable_method(raw, 0, 0, hasNextPtr)
    let nextPtr = unsafeBitCast(next, to: Int.self)
    _ = kk_object_register_itable_method(raw, 0, 1, nextPtr)
    if let remove {
        let removePtr = unsafeBitCast(remove, to: Int.self)
        _ = kk_object_register_itable_method(raw, 0, 2, removePtr)
        if mutableIterator {
            // MutableIterator declares remove as its direct method at slot 0.
            _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIteratorInterfaceTypeID), 1)
            _ = kk_object_register_itable_method(raw, 1, 0, removePtr)
        }
    }
}

/// Register the four `ListIterator` methods on a runtime-backed list iterator.
/// The inherited `Iterator` methods occupy slots 0 and 1, so the source-backed
/// `ListIterator` members begin at slots 2 through 5.
func registerListIteratorItable(raw: Int) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeListIteratorInterfaceTypeID), 1)
    let hasPreviousPtr = unsafeBitCast(runtimeListIteratorHasPreviousThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 2, hasPreviousPtr)
    let previousPtr = unsafeBitCast(runtimeListIteratorPreviousThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 3, previousPtr)
    let nextIndexPtr = unsafeBitCast(runtimeListIteratorNextIndexThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 4, nextIndexPtr)
    let previousIndexPtr = unsafeBitCast(runtimeListIteratorPreviousIndexThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 5, previousIndexPtr)
}

private let runtimeListIteratorHasPreviousThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_hasPrevious(raw)
}

private let runtimeListIteratorPreviousThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    guard let iter = runtimeListIteratorBox(from: raw), listIteratorCanGoBack(iter) else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "List iterator has no previous element."))
        return 0
    }
    return kk_list_iterator_previous(raw)
}

private let runtimeListIteratorNextIndexThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_nextIndex(raw)
}

private let runtimeListIteratorPreviousIndexThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_previousIndex(raw)
}

/// Register the `kotlin.collections.MutableIterator` itable on a raw object handle.
private func registerMutableIteratorItable(
    raw: Int,
    remove: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    ifaceSlot: Int = 1
) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIteratorInterfaceTypeID), ifaceSlot)
    let removePtr = unsafeBitCast(remove, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, removePtr)
}

/// Register the `kotlin.collections.Iterable` itable on a raw object handle.
private func registerIterableItable(raw: Int, ifaceSlot: Int = 0) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeIterableInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

/// Register the `kotlin.collections.MutableIterable` itable on a raw object handle.
private func registerMutableIterableItable(raw: Int, ifaceSlot: Int = 2) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIterableInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

/// Register the `kotlin.sequences.Sequence` itable on a raw object handle.
private func registerSequenceItable(raw: Int, ifaceSlot: Int = 1) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeSequenceInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

private let runtimeIterableIteratorThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterableRaw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator(iterableRaw)
}

private func maybeRegisterCollectionIterableItable(raw: Int, box: AnyObject) {
    // Runtime-backed collection boxes may be passed as `Iterable<T>` from
    // source-implemented `Sequence` wrappers (e.g. a `List` returned by a
    // `flatMap` lambda typed as `Iterable`). Register `Iterable.iterator()`
    // so interface dispatch works on those boxes.
    //
    // Some source-implemented `Sequence` HOF overloads are resolved to the
    // `Sequence` variant even when the lambda returns a `List`/`Set`/array
    // (which is `Iterable` but not actually `Sequence`); registering the
    // `Sequence` itable lets the generated `Sequence.iterator()` dispatch
    // reach the same runtime-backed iterator. `is` checks still consult the
    // nominal class hierarchy, so this does not make `List`/`Set` report as
    // `Sequence`.
    if box is RuntimeListBox {
        runtimeRegisterObjectType(rawValue: raw, classID: listRuntimeTypeID)
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
        registerMutableIterableItable(raw: raw, ifaceSlot: 2)
    } else if box is RuntimeSetBox {
        runtimeRegisterObjectType(rawValue: raw, classID: setRuntimeTypeID)
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
        registerMutableIterableItable(raw: raw, ifaceSlot: 2)
    } else if type(of: box) == RuntimeArrayBox.self {
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
    }
}

// MARK: - Iterator box itable registration

// Runtime-backed iterator boxes are returned by `iterator()` calls resolved
// through the synthetic collection fallback (e.g. `List.iterator()`). When a
// source-implemented `Sequence`/`Iterator` wrapper stores such an iterator as
// an `Iterator<T>` interface value, subsequent `hasNext()`/`next()` calls use
// itable dispatch and need the box to advertise those methods.

let runtimeListIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_hasNext(iterRaw)
}

let runtimeListIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    guard let iter = runtimeListIteratorBox(from: iterRaw), iter.index < iter.elements.count else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "List iterator has no next element."))
        return 0
    }
    return kk_list_iterator_next(iterRaw)
}

private let runtimeListIteratorRemoveThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return runtimeListIteratorRemove(iterRaw)
}

func registerRuntimeObject(_ box: RuntimeListIteratorBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject)
    registerIteratorItable(raw: raw, hasNext: runtimeListIteratorHasNextThunk, next: runtimeListIteratorNextThunk)
    if box.removeAction != nil {
        registerMutableIteratorItable(raw: raw, remove: runtimeListIteratorRemoveThunk)
    }
    return raw
}

private let runtimeRangeIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_range_hasNext(iterRaw)
}

private let runtimeRangeIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_range_next(iterRaw)
}

func registerRuntimeObject(_ box: RuntimeRangeIteratorBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject)
    registerIteratorItable(raw: raw, hasNext: runtimeRangeIteratorHasNextThunk, next: runtimeRangeIteratorNextThunk)
    return raw
}

private let runtimeMapIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_map_iterator_hasNext(iterRaw)
}

private let runtimeMapIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_map_iterator_next(iterRaw)
}

private let runtimeMutableMapIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_mutable_map_iterator_hasNext(iterRaw)
}

private let runtimeMutableMapIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_mutable_map_iterator_next(iterRaw)
}

private let runtimeMutableMapIteratorRemoveThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    kk_mutable_map_iterator_remove(iterRaw, outThrown)
}

func registerRuntimeObject(_ box: RuntimeMapIteratorBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject)
    registerIteratorItable(raw: raw, hasNext: runtimeMapIteratorHasNextThunk, next: runtimeMapIteratorNextThunk)
    return raw
}

func registerRuntimeObject(_ box: RuntimeMutableMapIteratorBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject)
    registerIteratorItable(
        raw: raw,
        hasNext: runtimeMutableMapIteratorHasNextThunk,
        next: runtimeMutableMapIteratorNextThunk,
        remove: runtimeMutableMapIteratorRemoveThunk,
        mutableIterator: true
    )
    return raw
}

func maybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return value
    }
    // Recognize string/sequence boxes first so unrelated primitive casts do
    // not trip on object pointers whose class metadata lives in libswiftCore.
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        _ = stringBox
        return value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return longBox.value
    }
    if let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
        return ulongBox.value
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return value
}

func runtimeNormalizeNullableCollectionValue(_ raw: Int) -> Int? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    return maybeUnbox(raw)
}

func runtimeMapNotNullResultValue(_ raw: Int) -> Int? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    // `raw` is a transform's return value, already boxed by KIR's ABILoweringPass
    // for its Any-typed return. Callers store or
    // forward this verbatim into a generically-typed collection/result, so it
    // must stay boxed here too — unboxing would strip the type tag a later
    // Boolean/Char render depends on.
    return raw
}

/// IEEE754 bit pattern of a boxed `Double`/`Float`, or nil when `raw` is not
/// one of those boxes. Unlike `maybeUnbox`, which leaves floating-point boxes
/// as pointers, this exposes the payload so a box can be compared against a
/// raw (never-boxed) floating-point word — the representation a `Double`
/// argument still has when it reaches a generic `T` parameter.
func runtimeFloatingBoxBitPattern(_ raw: Int) -> Int? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return Int(bitPattern: UInt(truncatingIfNeeded: doubleBox.value.bitPattern))
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return Int(floatBox.value.bitPattern)
    }
    return nil
}

func runtimeValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    if lhs == runtimeNullSentinelInt || rhs == runtimeNullSentinelInt {
        return lhs == rhs
    }
    let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs)
    let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhs)
    let lhsIsObjectPointer = runtimeStorage.withGCLock { state in
        lhsPtr.map { state.objectPointers.contains(UInt(bitPattern: $0)) } ?? false
    }
    let rhsIsObjectPointer = runtimeStorage.withGCLock { state in
        rhsPtr.map { state.objectPointers.contains(UInt(bitPattern: $0)) } ?? false
    }
    if lhsIsObjectPointer != rhsIsObjectPointer {
        // Boxed Double/Float vs a raw floating-point word: compare bit
        // patterns, matching Kotlin's boxed `equals` (NaN equals NaN,
        // -0.0 does not equal 0.0). maybeUnbox leaves those boxes as
        // pointers, so it would report every such pair unequal.
        let boxedSide = lhsIsObjectPointer ? lhs : rhs
        let rawSide = lhsIsObjectPointer ? rhs : lhs
        if let bitPattern = runtimeFloatingBoxBitPattern(boxedSide) {
            return bitPattern == rawSide
        }
        return maybeUnbox(lhs) == maybeUnbox(rhs)
    }
    if runtimeIsUnitBox(lhs) || runtimeIsUnitBox(rhs) {
        return runtimeIsUnitBox(lhs) && runtimeIsUnitBox(rhs)
    }
    if !lhsIsObjectPointer, !rhsIsObjectPointer {
        return lhs == rhs
    }
    guard let lhsPtr, let rhsPtr else {
        return lhs == rhs
    }
    if let lhsString = tryCast(lhsPtr, to: RuntimeStringBox.self),
       let rhsString = tryCast(rhsPtr, to: RuntimeStringBox.self)
    {
        return lhsString.value == rhsString.value
    }
    if let lhsInt = tryCast(lhsPtr, to: RuntimeIntBox.self),
       let rhsInt = tryCast(rhsPtr, to: RuntimeIntBox.self)
    {
        // Enum values are represented as boxed ordinals at Any boundaries.
        // Their nominal class is part of equals semantics: Direction.NORTH
        // must not equal Color.RED merely because both have ordinal zero.
        if lhsInt.enumClassID != nil || rhsInt.enumClassID != nil {
            return lhsInt.enumClassID == rhsInt.enumClassID
                && lhsInt.value == rhsInt.value
        }
        return lhsInt.value == rhsInt.value
    }
    if let lhsBool = tryCast(lhsPtr, to: RuntimeBoolBox.self),
       let rhsBool = tryCast(rhsPtr, to: RuntimeBoolBox.self)
    {
        return lhsBool.value == rhsBool.value
    }
    if let lhsLong = tryCast(lhsPtr, to: RuntimeLongBox.self),
       let rhsLong = tryCast(rhsPtr, to: RuntimeLongBox.self)
    {
        return lhsLong.value == rhsLong.value
    }
    if let lhsULong = tryCast(lhsPtr, to: RuntimeULongBox.self),
       let rhsULong = tryCast(rhsPtr, to: RuntimeULongBox.self)
    {
        return lhsULong.value == rhsULong.value
    }
    // Boxed floating-point equality follows Kotlin's `Double.equals`/
    // `Float.equals` (bit pattern), not IEEE `==`: NaN equals NaN and
    // -0.0 does not equal 0.0.
    if let lhsFloat = tryCast(lhsPtr, to: RuntimeFloatBox.self),
       let rhsFloat = tryCast(rhsPtr, to: RuntimeFloatBox.self)
    {
        return lhsFloat.value.bitPattern == rhsFloat.value.bitPattern
    }
    if let lhsDouble = tryCast(lhsPtr, to: RuntimeDoubleBox.self),
       let rhsDouble = tryCast(rhsPtr, to: RuntimeDoubleBox.self)
    {
        return lhsDouble.value.bitPattern == rhsDouble.value.bitPattern
    }
    if let lhsChar = tryCast(lhsPtr, to: RuntimeCharBox.self),
       let rhsChar = tryCast(rhsPtr, to: RuntimeCharBox.self)
    {
        return lhsChar.value == rhsChar.value
    }
    if let lhsDuration = tryCast(lhsPtr, to: RuntimeDurationBox.self),
       let rhsDuration = tryCast(rhsPtr, to: RuntimeDurationBox.self)
    {
        return lhsDuration.nanoseconds == rhsDuration.nanoseconds
    }
    if let lhsInstant = tryCast(lhsPtr, to: RuntimeInstantBox.self),
       let rhsInstant = tryCast(rhsPtr, to: RuntimeInstantBox.self)
    {
        return lhsInstant.epochSeconds == rhsInstant.epochSeconds
            && lhsInstant.nanoOfSecond == rhsInstant.nanoOfSecond
    }
    if let lhsList = tryCast(lhsPtr, to: RuntimeListBox.self),
       let rhsList = tryCast(rhsPtr, to: RuntimeListBox.self)
    {
        let lhsElems = lhsList.elements
        let rhsElems = rhsList.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for i in lhsElems.indices {
            // swiftlint:disable:next for_where
            if !runtimeValuesEqual(lhsElems[i], rhsElems[i]) {
                return false
            }
        }
        return true
    }
    if let lhsSet = tryCast(lhsPtr, to: RuntimeSetBox.self),
       let rhsSet = tryCast(rhsPtr, to: RuntimeSetBox.self)
    {
        let lhsElems = lhsSet.elements
        let rhsElems = rhsSet.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for elem in lhsElems {
            if !rhsSet.contains(rawValue: elem) {
                return false
            }
        }
        return true
    }
    if let lhsMap = tryCast(lhsPtr, to: RuntimeMapBox.self),
       let rhsMap = tryCast(rhsPtr, to: RuntimeMapBox.self)
    {
        guard lhsMap.keys.count == rhsMap.keys.count else { return false }
        for (i, lhsKey) in lhsMap.keys.enumerated() {
            guard let rhsIdx = rhsMap.index(ofRawKey: lhsKey),
                  let lhsValue = lhsMap.rawValue(at: i),
                  let rhsValue = rhsMap.rawValue(at: rhsIdx)
            else {
                return false
            }
            if !runtimeValuesEqual(lhsValue, rhsValue) {
                return false
            }
        }
        return true
    }
    // Only boxes tagged as kotlin.Pair/kotlin.Triple compare structurally:
    // RuntimePairBox also backs untyped internal 2-tuples (see kk_pair_new),
    // which keep reference equality.
    if runtimeObjectTypeID(rawValue: lhs) == runtimePairNominalTypeID,
       runtimeObjectTypeID(rawValue: rhs) == runtimePairNominalTypeID,
       let lhsPair = tryCast(lhsPtr, to: RuntimePairBox.self),
       let rhsPair = tryCast(rhsPtr, to: RuntimePairBox.self)
    {
        return runtimeValuesEqual(lhsPair.firstValue, rhsPair.firstValue)
            && runtimeValuesEqual(lhsPair.secondValue, rhsPair.secondValue)
    }
    if runtimeObjectTypeID(rawValue: lhs) == runtimeTripleNominalTypeID,
       runtimeObjectTypeID(rawValue: rhs) == runtimeTripleNominalTypeID,
       let lhsTriple = tryCast(lhsPtr, to: RuntimeTripleBox.self),
       let rhsTriple = tryCast(rhsPtr, to: RuntimeTripleBox.self)
    {
        return runtimeValuesEqual(lhsTriple.firstValue, rhsTriple.firstValue)
            && runtimeValuesEqual(lhsTriple.secondValue, rhsTriple.secondValue)
            && runtimeValuesEqual(lhsTriple.thirdValue, rhsTriple.thirdValue)
    }
    if let lhsLocale = tryCast(lhsPtr, to: RuntimeLocaleBox.self),
       let rhsLocale = tryCast(rhsPtr, to: RuntimeLocaleBox.self)
    {
        return lhsLocale.language == rhsLocale.language &&
            lhsLocale.country == rhsLocale.country &&
            lhsLocale.variant == rhsLocale.variant
    }
    // Data class / user-defined object structural equality: compare classID and elements.
    if let lhsObj = tryCast(lhsPtr, to: RuntimeObjectBox.self),
       let rhsObj = tryCast(rhsPtr, to: RuntimeObjectBox.self)
    {
        guard lhsObj.classID == rhsObj.classID else { return false }
        let lhsElems = lhsObj.elements
        let rhsElems = rhsObj.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for i in lhsElems.indices {
            // swiftlint:disable:next for_where
            if !runtimeValuesEqual(lhsElems[i], rhsElems[i]) {
                return false
            }
        }
        return true
    }
    return lhs == rhs
}

/// Kotlin stdlib bridge for structural equality of raw runtime values.
@_cdecl("__kk_values_equal")
public func __kk_values_equal(_ lhs: Int, _ rhs: Int) -> Int {
    kk_box_bool(runtimeValuesEqual(lhs, rhs) ? 1 : 0)
}

/// Applies Kotlin's reference-equality default to RuntimeObjectBox values while
/// retaining structural equality for data classes and collection/value boxes.
/// Returns nil when either operand is not a nominal runtime object, allowing
/// callers to fall back to `runtimeValuesEqual` for the other runtime types.
func runtimeAnyObjectEquality(_ lhs: Int, _ rhs: Int) -> Bool? {
    guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs),
          let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhs)
    else {
        return nil
    }
    let areRegisteredObjects = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: lhsPtr))
            && state.objectPointers.contains(UInt(bitPattern: rhsPtr))
    }
    guard areRegisteredObjects,
          let lhsObject = tryCast(lhsPtr, to: RuntimeObjectBox.self),
          let rhsObject = tryCast(rhsPtr, to: RuntimeObjectBox.self)
    else {
        return nil
    }

    guard lhsObject.classID == rhsObject.classID else {
        return false
    }
    guard runtimeIsDataClass(classID: lhsObject.classID) else {
        return lhs == rhs
    }
    return runtimeValuesEqual(lhs, rhs)
}

func runtimeValuesEqual(_ lhs: RuntimeValue, _ rhs: RuntimeValue) -> Bool {
    if lhs.tag == rhs.tag {
        switch lhs.tag {
        case RuntimeValue.charTag:
            return lhs.payload0 == rhs.payload0
        case RuntimeValue.stringTag:
            guard let lhsData = UnsafePointer<UInt8>(bitPattern: lhs.payload0),
                  let rhsData = UnsafePointer<UInt8>(bitPattern: rhs.payload0)
            else {
                return lhs.payload0 == rhs.payload0
            }
            return runtimeStringFromFlatFields(
                data: lhsData,
                length: lhs.payload1,
                byteCount: lhs.payload2,
                hash: lhs.payload3
            ) == runtimeStringFromFlatFields(
                data: rhsData,
                length: rhs.payload1,
                byteCount: rhs.payload2,
                hash: rhs.payload3
            )
        default:
            return runtimeValuesEqual(lhs.payload0, rhs.payload0)
        }
    }
    return runtimeValuesEqual(lhs.legacyRawValue, rhs.legacyRawValue)
}

/// Equality for `==` on runtime reference values.
/// Collection/value boxes remain structural, while ordinary nominal objects use Any.equals semantics.
/// Returns a boxed Bool (via kk_box_bool) so it matches the ABI of other kk_op_* functions.
@_cdecl("kk_structural_eq")
public func kk_structural_eq(_ lhs: Int, _ rhs: Int) -> Int {
    (runtimeAnyObjectEquality(lhs, rhs) ?? runtimeValuesEqual(lhs, rhs)) ? 1 : 0
}

/// Inequality for `!=` on runtime reference values.
@_cdecl("kk_structural_ne")
public func kk_structural_ne(_ lhs: Int, _ rhs: Int) -> Int {
    (runtimeAnyObjectEquality(lhs, rhs) ?? runtimeValuesEqual(lhs, rhs)) ? 0 : 1
}

func runtimeElementToString(_ elem: Int) -> String {
    if elem == runtimeNullSentinelInt {
        return "null"
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: elem) else {
        return "\(elem)"
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return "\(elem)"
    }
    if runtimeIsUnitBox(elem) {
        return "kotlin.Unit"
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.enumEntryName ?? "\(intBox.value)"
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return "\(longBox.value)"
    }
    if let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
        return "\(UInt(bitPattern: ulongBox.value))"
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return runtimeFormatFloatingPoint(floatBox.value)
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return runtimeFormatFloatingPoint(doubleBox.value)
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return UnicodeScalar(charBox.value).map(String.init) ?? "?"
    }
    if let throwableString = runtimeThrowableToString(elem) {
        return throwableString
    }
    if let instantBox = tryCast(ptr, to: RuntimeInstantBox.self) {
        return runtimeInstantToString(instantBox)
    }
    if let listBox = tryCast(ptr, to: RuntimeListBox.self) {
        let parts = listBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        let parts = setBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let parts = zip(mapBox.keyValues, mapBox.entryValues).map { key, value in
            "\(runtimeElementToString(key))=\(runtimeElementToString(value))"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
    if let pairBox = tryCast(ptr, to: RuntimePairBox.self) {
        let first = runtimeElementToString(pairBox.firstValue)
        let second = runtimeElementToString(pairBox.secondValue)
        if runtimeIsMapEntry(rawValue: elem) {
            return "\(first)=\(second)"
        }
        if runtimeObjectTypeID(rawValue: elem) == indexedValueRuntimeTypeID {
            return "IndexedValue(index=\(first), value=\(second))"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(ptr, to: RuntimeTripleBox.self) {
        let first = runtimeElementToString(tripleBox.firstValue)
        let second = runtimeElementToString(tripleBox.secondValue)
        let third = runtimeElementToString(tripleBox.thirdValue)
        return "(\(first), \(second), \(third))"
    }
    if let rangeBox = tryCast(ptr, to: RuntimeRangeBox.self) {
        let first = runtimeElementToString(rangeBox.first)
        let last = runtimeElementToString(rangeBox.last)
        if rangeBox.step == 1 {
            return "\(first)..\(last)"
        } else if rangeBox.step == -1 {
            return "\(first) downTo \(last) step 1"
        } else if rangeBox.step < 0 {
            return "\(first) downTo \(last) step \(-rangeBox.step)"
        } else {
            return "\(first)..\(last) step \(rangeBox.step)"
        }
    }
    if let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        let parts = arrayBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let sbBox = tryCast(ptr, to: RuntimeStringBuilderBox.self) {
        return sbBox.value
    }
    if let ktypeProjectionBox = tryCast(ptr, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionToString(ktypeProjectionBox)
    }
    if let ktypeBox = tryCast(ptr, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    if let rendered = runtimeRenderIndexedValueObject(elem, render: runtimeElementToString) {
        return rendered
    }
    // Registered object of a type this renderer does not know: keep it
    // recognisable as an object instead of leaking its address as a number,
    // matching `runtimeRenderAnyForPrint`.  Non-object handles already
    // returned their numeric value above.
    return "<object \(ptr)>"
}

func runtimeElementToString(_ value: RuntimeValue) -> String {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return "null"
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.charTag:
        return UnicodeScalar(value.payload0).map(String.init) ?? "?"
    default:
        return runtimeElementToString(value.payload0)
    }
}

// MARK: - Collection HOF Helpers (STDLIB-005)

typealias RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda4 = @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
/// Writes a thrown payload when the caller provided an out-thrown slot.
func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, _ value: Int) {
    outThrown?.pointee = value
}

/// Normalizes truthiness for predicates from raw/boxed Boolean values.
func runtimeCollectionBool(_ value: Int) -> Bool {
    kk_unbox_bool(value) != 0
}

@inline(__always)
func runtimeInvokeCollectionLambda1(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(maybeUnbox(closureRaw), maybeUnbox(value), outThrown)
}

/// Like `runtimeInvokeCollectionLambda1`, but tolerates `fnPtr` arriving as a
/// `kk_function_create_1`-wrapped function-value handle instead of a raw,
/// directly-callable function pointer.
///
/// `Sequence<T>.chunked(size, transform)` / `.windowed(..., transform)` have
/// real Kotlin-source declarations (SequenceWindowChunk.kt) so their
/// `require()`-style validation runs; because they take a function-typed
/// parameter, KIRLoweringDriver's auto-inline heuristic
/// (`hasLambdaParam && !isSuspend`) always inlines their body at the call
/// site. `materializeSourceBackedFunctionValueArguments` wraps the caller's
/// lambda via `kk_function_create_1` before that inlining substitutes it in,
/// since from the *caller's* perspective this looks like an ordinary
/// function-value parameter. The inlined body then forwards that already-
/// wrapped handle straight to this native bridge via
/// `splitCallableLambdaArgument`, whose fallback (no compile-time
/// `callableValueInfo` exists for a plain forwarded parameter) assumes an
/// unrecognized value is already a raw callable and pairs it with a literal
/// `0` closureRaw. Unwrapping here — the same `RuntimeFunctionValueBox`
/// detection `kk_function_invoke` already relies on — makes the lazy/eager
/// invocation robust to either calling convention without having to teach
/// every KIR argument-adaptation path about this one forwarding pattern.
@inline(__always)
func runtimeInvokeCollectionLambda1MaybeWrapped(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: fnPtr) {
        return runtimeInvokeCollectionLambda1(
            fnPtr: box.fnPtr,
            closureRaw: box.closureRaw,
            value: value,
            outThrown: outThrown
        )
    }
    return runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: value,
        outThrown: outThrown
    )
}

/// Like `runtimeInvokeCollectionLambda1`, but leaves `value` boxed for statically-`Any` lambda parameters (LambdaLowerer unboxes concrete-primitive ones itself).
@inline(__always)
func runtimeInvokeCollectionLambda1PreservingBox(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(maybeUnbox(closureRaw), value, outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda2(
    fnPtr: Int,
    closureRaw: Int,
    lhs: Int,
    rhs: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda2.self)
    return fn(maybeUnbox(closureRaw), maybeUnbox(lhs), maybeUnbox(rhs), outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda3(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda3.self)
    return fn(
        maybeUnbox(closureRaw),
        maybeUnbox(arg1),
        maybeUnbox(arg2),
        maybeUnbox(arg3),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeCollectionLambda4(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    arg4: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda4.self)
    return fn(
        maybeUnbox(closureRaw),
        maybeUnbox(arg1),
        maybeUnbox(arg2),
        maybeUnbox(arg3),
        maybeUnbox(arg4),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeClosureThunk(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: KKClosureThunkEntryPoint.self)
    return fn(closureRaw, outThrown)
}

func runtimeCompareValues(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    if let lhsString = runtimeStringFromRawValue(lhs),
       let rhsString = runtimeStringFromRawValue(rhs)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }
    if let lhsScalar = runtimeComparableScalarValue(from: lhs),
       let rhsScalar = runtimeComparableScalarValue(from: rhs)
    {
        switch (lhsScalar, rhsScalar) {
        case let (.floating(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, rhsValue)
        case let (.floating(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.floating(lhsValue), .unsignedInteger(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.integer(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.unsignedInteger(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.integer(lhsValue), .integer(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
        case let (.unsignedInteger(lhsValue), .unsignedInteger(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
        // Mixed signed/unsigned integers only arise when comparing values of
        // statically-incompatible Kotlin types (e.g. Long vs ULong through a
        // type-erased Comparable); there is no principled ordering, so fall
        // back to a Double approximation rather than crashing.
        case let (.integer(lhsValue), .unsignedInteger(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), Double(rhsValue))
        case let (.unsignedInteger(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), Double(rhsValue))
        }
    }
    if let comparableResult = runtimeCompareComparableValues(lhs: lhs, rhs: rhs) {
        return comparableResult
    }
    let lhsRendered = runtimeElementToString(lhs)
    let rhsRendered = runtimeElementToString(rhs)
    if lhsRendered == rhsRendered {
        return 0
    }
    return lhsRendered < rhsRendered ? -1 : 1
}

func runtimeCompareValues(_ lhs: RuntimeValue, _ rhs: RuntimeValue) -> Int {
    if lhs.tag == RuntimeValue.rawTag, rhs.tag == RuntimeValue.rawTag {
        return runtimeCompareValues(lhs.payload0, rhs.payload0)
    }
    if let lhsString = runtimeStringFromRuntimeValue(lhs),
       let rhsString = runtimeStringFromRuntimeValue(rhs)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }
    if lhs.tag == RuntimeValue.charTag, rhs.tag == RuntimeValue.charTag {
        return runtimeCompareIntegers(lhs.payload0, rhs.payload0)
    }
    if lhs.tag != RuntimeValue.stringTag, rhs.tag != RuntimeValue.stringTag {
        return runtimeCompareValues(lhs.legacyRawValue, rhs.legacyRawValue)
    }
    return runtimeCompareStrings(
        runtimeElementToString(lhs),
        runtimeElementToString(rhs)
    )
}

@inline(__always)
private func runtimeCompareIntegers(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeStringFromRuntimeValue(_ value: RuntimeValue) -> String? {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return nil
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.rawTag:
        return runtimeStringFromRawValue(value.payload0)
    default:
        return nil
    }
}

@inline(__always)
func runtimeBinarySearch(
    elements: [Int],
    element: Int,
    fromIndex: Int,
    toIndex: Int,
    compare: (Int, Int) -> Int
) -> Int {
    let lowerBound = max(0, min(fromIndex, elements.count))
    let upperBound = max(lowerBound, min(toIndex, elements.count))
    var low = lowerBound
    var high = upperBound - 1
    while low <= high {
        let mid = (low + high) / 2
        let cmp = compare(elements[mid], element)
        if cmp < 0 {
            low = mid + 1
        } else if cmp > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@inline(__always)
func runtimeCompareComparableValues(lhs: Int, rhs: Int) -> Int? {
    guard let lhsTypeID = runtimeObjectTypeID(rawValue: lhs),
          let rhsTypeID = runtimeObjectTypeID(rawValue: rhs),
          runtimeIsAssignable(sourceTypeID: lhsTypeID, targetTypeID: comparableRuntimeTypeID),
          runtimeIsAssignable(sourceTypeID: rhsTypeID, targetTypeID: comparableRuntimeTypeID),
          runtimeComparableOperandsAreCompatible(
              lhsTypeID: lhsTypeID,
              rhsTypeID: rhsTypeID,
              comparableTypeID: comparableRuntimeTypeID
          )
    else {
        return nil
    }

    // Comparable has a single compareTo method (method slot 0). Resolve the
    // interface slot from the object's own registration so classes that
    // implement several interfaces dispatch to the right table; hand-built
    // runtime objects without that registration keep using slot 0.
    var compareToFnPtr = kk_itable_lookup_dynamic(lhs, Int(comparableRuntimeTypeID), 0)
    if compareToFnPtr == 0 {
        compareToFnPtr = kk_itable_lookup(lhs, 0, 0)
    }
    guard compareToFnPtr != 0 else {
        return nil
    }
    // Compiler-emitted members follow the (receiver, args..., outThrown) ABI
    // and may return a boxed Int, so pass the thrown channel explicitly and
    // normalize the result instead of treating it as a bare Int.
    let compareToFn = unsafeBitCast(
        compareToFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = compareToFn(lhs, rhs, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Comparable.compareTo threw during a runtime comparison")
    }
    return maybeUnbox(result)
}

enum RuntimePrimitiveCompareKind {
    case int
    case long
    case uint
    case ulong
    case boolean
    case char
    case float
    case double
}

private enum RuntimeComparableScalarValue {
    case integer(Int)
    case unsignedInteger(UInt)
    case floating(Double)
}

private func runtimeCompareFloatingValues(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs.isNaN {
        return rhs.isNaN ? 0 : 1
    }
    if rhs.isNaN {
        return -1
    }
    if lhs == rhs {
        // IEEE equality treats -0.0 == 0.0, but Kotlin's `compareTo` follows
        // the `Double.compare` total order where -0.0 sorts before 0.0.
        if lhs.sign == rhs.sign {
            return 0
        }
        return lhs.sign == .minus ? -1 : 1
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeComparableScalarValue(from raw: Int) -> RuntimeComparableScalarValue? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return .integer(raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return .integer(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return .floating(Double(floatBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return .floating(doubleBox.value)
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return .integer(intBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return .integer(boolBox.value ? 1 : 0)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return .integer(longBox.value)
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return .unsignedInteger(UInt(bitPattern: ulongBox.value))
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return .integer(charBox.value)
    }
    return nil
}

@inline(__always)
private func runtimePrimitiveIntValue(_ raw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return raw
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return raw
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return longBox.value
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return ulongBox.value
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return raw
}

@inline(__always)
private func runtimePrimitiveFloatValue(_ raw: Int, kind: RuntimePrimitiveCompareKind) -> Double {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return Double(floatBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return doubleBox.value
    }
    return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
}

@inline(__always)
func runtimeComparePrimitiveValues(_ lhs: Int, _ rhs: Int, kind: RuntimePrimitiveCompareKind) -> Int {
    switch kind {
    case .int, .long, .boolean, .char:
        let lhsValue = runtimePrimitiveIntValue(lhs)
        let rhsValue = runtimePrimitiveIntValue(rhs)
        if lhsValue == rhsValue { return 0 }
        return lhsValue < rhsValue ? -1 : 1
    case .uint, .ulong:
        let lhsValue = UInt(bitPattern: runtimePrimitiveIntValue(lhs))
        let rhsValue = UInt(bitPattern: runtimePrimitiveIntValue(rhs))
        if lhsValue == rhsValue { return 0 }
        return lhsValue < rhsValue ? -1 : 1
    case .float, .double:
        return runtimeCompareFloatingValues(
            runtimePrimitiveFloatValue(lhs, kind: kind),
            runtimePrimitiveFloatValue(rhs, kind: kind)
        )
    }
}

/// Explicit `T.compareTo(other)` member call on a primitive `Comparable`
/// receiver (Int/Long/UInt/ULong/Boolean/Float/Double — and the signed
/// Byte/Short and unsigned UByte/UShort that share the Int ABI).
///
/// The desugared comparison operators (`<`, `>`, …) compute the comparison
/// directly via machine compare in lowering, but the *explicit* member call
/// has no per-type runtime mapping, so this entry point routes it to the same
/// `runtimeComparePrimitiveValues` helper used by primitive comparators.
/// `kindRaw` is a `PrimitiveCompareABIKind` raw value (which aligns with the
/// `RuntimePrimitiveCompareKind` ordering) selecting signed / unsigned / IEEE
/// floating semantics. The result is the sign of the comparison (-1/0/1),
/// matching `Integer.compare` / `Long.compare` / `Double.compare` — i.e.
/// Kotlin's `Comparable<T>.compareTo` contract. (Char keeps its own
/// `kk_char_compareTo` entry point, which returns the raw codepoint
/// difference to mirror `Character.compare`.)
@_cdecl("kk_primitive_compareTo")
public func kk_primitive_compareTo(_ lhsRaw: Int, _ rhsRaw: Int, _ kindRaw: Int32) -> Int {
    runtimeComparePrimitiveValues(lhsRaw, rhsRaw, kind: runtimePrimitiveCompareKind(from: kindRaw))
}

private func runtimeStringFromRawValue(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: pointer)
}
