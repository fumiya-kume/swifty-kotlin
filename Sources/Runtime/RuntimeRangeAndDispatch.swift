import Foundation

final class RuntimeRangeBox {
    let first: Int
    let last: Int
    let step: Int

    init(first: Int, last: Int, step: Int) {
        self.first = first
        self.last = last
        self.step = step
    }
}

private final class RuntimeRangeIteratorBox {
    var current: Int
    let last: Int
    let step: Int

    init(current: Int, last: Int, step: Int) {
        self.current = current
        self.last = last
        self.step = step
    }
}

@_cdecl("kk_op_notnull")
public func kk_op_notnull(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if value == runtimeNullSentinelInt {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NullPointerException")
        return 0
    }
    return value
}

@_cdecl("kk_op_elvis")
public func kk_op_elvis(_ lhs: Int, _ rhs: Int) -> Int {
    lhs == runtimeNullSentinelInt ? rhs : lhs
}

@_cdecl("kk_op_rangeTo")
public func kk_op_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_op_rangeUntil")
public func kk_op_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1))
}

@_cdecl("kk_op_downTo")
public func kk_op_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_op_step")
public func kk_op_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    guard stepValue > 0, let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    let nextStep = range.step < 0 ? -stepValue : stepValue
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
}

@_cdecl("kk_range_iterator")
public func kk_range_iterator(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_range_hasNext")
public func kk_range_hasNext(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    if iterator.step > 0 {
        return iterator.current <= iterator.last ? 1 : 0
    }
    if iterator.step < 0 {
        return iterator.current >= iterator.last ? 1 : 0
    }
    return 0
}

@_cdecl("kk_range_next")
public func kk_range_next(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    iterator.current = iterator.current &+ iterator.step
    return current
}

// MARK: - IntRange properties (STDLIB-092)

@_cdecl("kk_range_first")
public func kk_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_first")
    }
    return range.first
}

@_cdecl("kk_range_last")
public func kk_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_last")
    }
    return range.last
}

@_cdecl("kk_range_count")
public func kk_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_count")
    }
    if range.step > 0 {
        guard range.first <= range.last else { return 0 }
        return (range.last - range.first) / range.step + 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first - range.last) / (-range.step) + 1
    }
    return 0
}

// MARK: - IntRange HOFs (STDLIB-091)

@_cdecl("kk_range_toList")
public func kk_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_toList")
    }
    var elements: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            elements.append(current)
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            elements.append(current)
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_range_forEach")
public func kk_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                             _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    }
    return 0
}

@_cdecl("kk_range_map")
public func kk_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

// MARK: - IntRange reversed (STDLIB-093)

@_cdecl("kk_range_reversed")
public func kk_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: -range.step))
}

@_cdecl("kk_vtable_lookup")
public func kk_vtable_lookup(_ receiver: Int, _ slot: Int) -> Int {
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
        let registered = runtimeStorage.withLock { state in
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

@_cdecl("kk_kxmini_run_loop")
public func kk_kxmini_run_loop(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
}

func runtimeRangeBox(from rawValue: Int) -> RuntimeRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeBox.self)
}

private func runtimeRangeIteratorBox(from rawValue: Int) -> RuntimeRangeIteratorBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeIteratorBox.self)
}

@_cdecl("kk_dispatch_error")
public func kk_dispatch_error() -> Int {
    fatalError("KSWIFTK-RT-0001: Virtual dispatch failed: method not found in vtable/itable")
}

private func runtimeTypeInfo(from receiver: Int) -> UnsafePointer<KTypeInfo>? {
    guard receiver != 0,
          receiver != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: receiver)
    else {
        return nil
    }
    let isHeapObject = runtimeStorage.withLock { state in
        state.heapObjects[UInt(bitPattern: pointer)] != nil
    }
    guard isHeapObject else {
        return nil
    }
    return pointer.assumingMemoryBound(to: KKObjHeader.self).pointee.typeInfo
}
