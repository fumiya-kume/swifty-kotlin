// LongRange runtime entry points (STDLIB-RANGE-035) plus IntRange
// `toIntArray` (STDLIB-RANGE-034) and ULongRange iterator/forEach/map.
//
// HOF logic and range-handle validation live in RuntimeRangeSharedHOF.swift.
// These @_cdecl functions are thin ABI entry points.

// MARK: - LongRange (STDLIB-RANGE-035)

@_cdecl("kk_long_rangeTo")
public func kk_long_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_long_range_step")
public func kk_long_range_step(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_step") { range in
        range.step
    }
}

@_cdecl("kk_long_range_iterator")
public func kk_long_range_iterator(_ rangeRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil {
        return rangeRaw
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_long_range_toList")
public func kk_long_range_toList(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_toList") { range in
        RuntimeSignedRangeHOFKind.toList(range)
    }
}

@_cdecl("kk_long_range_toLongArray")
public func kk_long_range_toLongArray(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_toLongArray") { range in
        runtimeSignedRangeToArray(range)
    }
}

@_cdecl("__kk_long_range_randomOrNull")
public func __kk_long_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "__kk_long_range_randomOrNull")
}

@_cdecl("__kk_long_range_randomOrNull_random")
public func __kk_long_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "__kk_long_range_randomOrNull_random")
}

@_cdecl("kk_long_range_firstOrNull")
public func kk_long_range_firstOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_firstOrNull") { range in
        RuntimeSignedRangeHOFKind.firstOrNull(range)
    }
}

@_cdecl("kk_long_range_lastOrNull")
public func kk_long_range_lastOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_lastOrNull") { range in
        RuntimeSignedRangeHOFKind.lastOrNull(range)
    }
}

@_cdecl("kk_long_range_forEach")
public func kk_long_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_long_range_forEach", operation: RuntimeSignedRangeHOFKind.forEach)
}

@_cdecl("kk_long_range_map")
public func kk_long_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_long_range_map", operation: RuntimeSignedRangeHOFKind.map)
}

@_cdecl("__kk_long_range_random")
public func __kk_long_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "__kk_long_range_random")
}

@_cdecl("__kk_long_range_random_random")
public func __kk_long_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "__kk_long_range_random_random")
}

@_cdecl("__kk_random_nextLong_rangeObject")
public func __kk_random_nextLong_rangeObject(_ randomRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "__kk_random_nextLong_rangeObject") { range in
        if RuntimeSignedRangeHOFKind.isEmpty(range) {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Random range is empty: \(range.first)..\(range.last)."
            )
            return 0
        }
        return RuntimeSignedRangeHOFKind.random(range, randomRaw: randomRaw, outThrown: outThrown)
    }
}

@_cdecl("kk_long_range_take")
public func kk_long_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_take") { range in
        RuntimeSignedRangeHOFKind.take(range, n)
    }
}

@_cdecl("kk_long_range_drop")
public func kk_long_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_drop") { range in
        RuntimeSignedRangeHOFKind.drop(range, n)
    }
}

@_cdecl("kk_long_range_average")
public func kk_long_range_average(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_average") { range in
        RuntimeSignedRangeHOFKind.average(range)
    }
}

@_cdecl("kk_long_range_sorted")
public func kk_long_range_sorted(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_long_range_sorted") { range in
        RuntimeSignedRangeHOFKind.sorted(range)
    }
}

// MARK: - IntRange toIntArray (STDLIB-RANGE-034)

@_cdecl("kk_range_toIntArray")
public func kk_range_toIntArray(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_toIntArray") { range in
        runtimeSignedRangeToArray(range)
    }
}

// MARK: - ULongRange count, iterator, hasNext, next (STDLIB-RANGE-037)

@_cdecl("kk_ulong_range_count")
public func kk_ulong_range_count(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_count") { range in
        runtimeUnsignedRangeCount(range)
    }
}

@_cdecl("kk_ulong_range_iterator")
public func kk_ulong_range_iterator(_ rangeRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil {
        return rangeRaw
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_ulong_range_hasNext")
public func kk_ulong_range_hasNext(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return __kk_iterator_builder_hasNext(iterRaw)
    }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = UInt(bitPattern: iterator.current)
    let last = UInt(bitPattern: iterator.last)
    if iterator.step > 0 { return current <= last ? 1 : 0 }
    if iterator.step < 0 { return current >= last ? 1 : 0 }
    return 0
}

@_cdecl("kk_ulong_range_next")
public func kk_ulong_range_next(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return __kk_iterator_builder_next(iterRaw)
    }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    let uCurrent = UInt(bitPattern: current)
    if iterator.step > 0 {
        let uStep = UInt(bitPattern: iterator.step)
        let (next, overflow) = uCurrent.addingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    } else if iterator.step < 0 {
        let uStep = UInt(iterator.step.magnitude)
        let (next, overflow) = uCurrent.subtractingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    }
    return current
}

@_cdecl("kk_ulong_range_forEach")
public func kk_ulong_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_forEach", operation: RuntimeUnsignedRangeHOFKind.forEach)
}

@_cdecl("kk_ulong_range_map")
public func kk_ulong_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_map", operation: RuntimeUnsignedRangeHOFKind.map)
}

// MARK: - IntRange reversed (STDLIB-093)

@_cdecl("__kk_range_reversed")
public func kk_range_reversed(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_reversed") { range in
        registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
    }
}

@_cdecl("kk_vtable_lookup")
public func kk_vtable_lookup(_ receiver: Int, _ slot: Int) -> Int {
    if let pointer = UnsafeMutableRawPointer(bitPattern: receiver) {
        let objectKey = UInt(bitPattern: pointer)
        let registered = runtimeStorage.withMetadataLock { state in
            state.objectVtableMethods[objectKey]?[slot]
        }
        if let registered, registered != 0 {
            return registered
        }
    }
    if let throwableMethod = runtimeThrowableVtableMethodRaw(receiver, slot: slot) {
        return throwableMethod
    }
    guard slot >= 0,
          let typeInfo = runtimeTypeInfo(from: receiver)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: vtable lookup failed — invalid receiver (0x\(String(receiver, radix: 16))) or negative slot (\(slot))")
    }
    let descriptor = typeInfo.pointee
    guard slot < Int(descriptor.vtableSize) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: vtable lookup failed — slot \(slot) out of range (vtableSize=\(descriptor.vtableSize))")
    }
    return Int(bitPattern: descriptor.vtable[slot])
}

@_cdecl("kk_itable_lookup")
public func kk_itable_lookup(_ receiver: Int, _ ifaceSlot: Int, _ methodSlot: Int) -> Int {
    if let pointer = UnsafeMutableRawPointer(bitPattern: receiver) {
        let objectKey = UInt(bitPattern: pointer)
        let dispatchKey = (UInt64(UInt32(ifaceSlot)) << 32) | UInt64(UInt32(methodSlot))
        let registered = runtimeStorage.withMetadataLock { state in
            state.objectItableMethods[objectKey]?[dispatchKey]
        }
        if let registered {
            return registered
        }
    }
    guard ifaceSlot >= 0,
          methodSlot >= 0,
          let descriptor = runtimeTypeInfo(from: receiver)?.pointee,
          let itableBase = descriptor.itable?.assumingMemoryBound(to: UnsafeRawPointer?.self)
    else {
        return 0
    }
    guard let methodTable = itableBase[ifaceSlot] else {
        return 0
    }
    let methods = methodTable.assumingMemoryBound(to: UnsafeRawPointer?.self)
    guard let functionPointer = methods[methodSlot] else {
        return 0
    }
    return Int(bitPattern: functionPointer)
}

func runtimeRegisteredInterfaceSlot(objectRaw: Int, interfaceTypeID: Int64) -> Int? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: objectRaw) else {
        return nil
    }
    let objectKey = UInt(bitPattern: ptr)
    return runtimeStorage.withMetadataLock { state in
        state.objectInterfaceSlots[objectKey]?[interfaceTypeID]
    }
}

/// Like `kk_itable_lookup`, but for call sites where the receiver's static
/// type was the interface itself (e.g. a function parameter typed
/// `d: SomeInterface`) rather than a concrete class — the compiler doesn't
/// know which itable slot the eventual concrete class assigned to that
/// interface, so it's resolved here from the object's own registration
/// (recorded by kk_object_register_itable_iface at construction time) keyed
/// by the interface's stable type ID instead of a fixed slot index.
@_cdecl("kk_itable_lookup_dynamic")
public func kk_itable_lookup_dynamic(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int {
    guard let ifaceSlot = runtimeRegisteredInterfaceSlot(objectRaw: receiver, interfaceTypeID: Int64(interfaceTypeID)) else {
        return 0
    }
    return kk_itable_lookup(receiver, ifaceSlot, methodSlot)
}

func runtimeRangeBox(from rawValue: Int) -> RuntimeRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeBox.self)
}

private func runtimeSignedRangeToArray(_ range: RuntimeRangeBox) -> Int {
    var current = range.first
    var elements: [Int] = []
    if range.step > 0 {
        while current <= range.last {
            elements.append(current)
            let (next, overflow) = current.addingReportingOverflow(range.step)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        while current >= range.last {
            elements.append(current)
            let (next, overflow) = current.addingReportingOverflow(range.step)
            if overflow { break }
            current = next
        }
    }
    let box = RuntimeArrayBox(length: elements.count)
    for (index, element) in elements.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

private func runtimeRangeIteratorBox(from rawValue: Int) -> RuntimeRangeIteratorBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeIteratorBox.self)
}

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeIteratorBuilderBox.self)
}

@_cdecl("kk_dispatch_error")
public func kk_dispatch_error() -> Int {
    runtimeStructuredPanic("Virtual dispatch failed: method not found in vtable/itable")
}

private func runtimeTypeInfo(from receiver: Int) -> UnsafePointer<KTypeInfo>? {
    guard receiver != 0,
          receiver != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: receiver)
    else {
        return nil
    }
    let isHeapObject = runtimeStorage.withGCLock { state in
        state.heapObjects[UInt(bitPattern: pointer)] != nil
    }
    guard isHeapObject else {
        return nil
    }
    return pointer.assumingMemoryBound(to: KKObjHeader.self).pointee.typeInfo
}
