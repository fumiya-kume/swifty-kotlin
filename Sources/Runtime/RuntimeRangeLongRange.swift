import Foundation

/// LongRange runtime entry points (STDLIB-RANGE-035) plus IntRange
/// `toIntArray` (STDLIB-RANGE-034) and ULongRange iterator/forEach/map.
///
/// Split out from `RuntimeRangeAndDispatch.swift`.

// MARK: - LongRange (STDLIB-RANGE-035)

@_cdecl("kk_long_rangeTo")
public func kk_long_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_long_range_first")
public func kk_long_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_first")
    }
    return range.first
}

@_cdecl("kk_long_range_last")
public func kk_long_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_last")
    }
    return range.last
}

@_cdecl("kk_long_range_step")
public func kk_long_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_step")
    }
    return range.step
}

@_cdecl("kk_long_range_contains")
public func kk_long_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_contains")
    }
    if range.step > 0 {
        guard range.first <= value && value <= range.last else { return 0 }
        return (value &- range.first) % range.step == 0 ? 1 : 0
    } else if range.step < 0 {
        guard range.last <= value && value <= range.first else { return 0 }
        return (range.first &- value) % (0 &- range.step) == 0 ? 1 : 0
    }
    return 0
}

@_cdecl("kk_long_range_isEmpty")
public func kk_long_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_isEmpty")
    }
    if range.step > 0 {
        return range.first > range.last ? 1 : 0
    } else if range.step < 0 {
        return range.first < range.last ? 1 : 0
    }
    return 1
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

@_cdecl("kk_long_range_reversed")
public func kk_long_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

@_cdecl("kk_long_range_toList")
public func kk_long_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_toList")
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

@_cdecl("kk_long_range_toLongArray")
public func kk_long_range_toLongArray(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_toLongArray")
    }
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
    for (i, elem) in elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_long_range_count")
public func kk_long_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_count")
    }
    if range.step > 0 {
        guard range.first <= range.last else { return 0 }
        return (range.last &- range.first) / range.step &+ 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first &- range.last) / (0 &- range.step) &+ 1
    }
    return 0
}

@_cdecl("kk_long_range_randomOrNull")
public func kk_long_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_randomOrNull")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_long_range_randomOrNull_random")
public func kk_long_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_randomOrNull_random")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_long_range_firstOrNull")
public func kk_long_range_firstOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_firstOrNull")
    }
    if range.step == 0 {
        return runtimeNullSentinelInt
    }
    if range.step > 0 {
        return range.first <= range.last ? range.first : runtimeNullSentinelInt
    }
    return range.first >= range.last ? range.first : runtimeNullSentinelInt
}

@_cdecl("kk_long_range_lastOrNull")
public func kk_long_range_lastOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_lastOrNull")
    }
    if range.step == 0 {
        return runtimeNullSentinelInt
    }
    if range.step > 0 {
        return range.first <= range.last ? range.last : runtimeNullSentinelInt
    }
    return range.first >= range.last ? range.last : runtimeNullSentinelInt
}

@_cdecl("kk_long_range_forEach")
public func kk_long_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_forEach")
    }
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

@_cdecl("kk_long_range_map")
public func kk_long_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_map")
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

@_cdecl("kk_long_range_random")
public func kk_long_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_random")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: 0,
        outThrown: outThrown
    )
}

@_cdecl("kk_long_range_random_random")
public func kk_long_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_random_random")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: randomRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_random_nextLong_rangeObject")
public func kk_random_nextLong_rangeObject(_ randomRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_random_nextLong_rangeObject")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: randomRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_long_range_take")
public func kk_long_range_take(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_take")
    }
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var elements: [Int] = []
    var taken = 0
    var current = range.first
    if range.step > 0 {
        while current <= range.last && taken < n {
            elements.append(current)
            current &+= range.step
            taken += 1
        }
    } else if range.step < 0 {
        while current >= range.last && taken < n {
            elements.append(current)
            current &+= range.step
            taken += 1
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_long_range_drop")
public func kk_long_range_drop(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_drop")
    }
    var elements: [Int] = []
    var current = range.first
    var skipped = 0
    if range.step > 0 {
        while current <= range.last {
            if skipped >= n { elements.append(current) }
            else { skipped += 1 }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            if skipped >= n { elements.append(current) }
            else { skipped += 1 }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_long_range_average")
public func kk_long_range_average(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_average")
    }
    var sum: Double = 0.0
    var count: Double = 0.0
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            sum += Double(current)
            count += 1.0
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            sum += Double(current)
            count += 1.0
            current &+= range.step
        }
    }
    let result: Double = count > 0 ? sum / count : Double.nan
    return Int(bitPattern: UInt(truncatingIfNeeded: result.bitPattern))
}

@_cdecl("kk_long_range_sorted")
public func kk_long_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_range_sorted")
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
    elements.sort()
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

// MARK: - IntRange toIntArray (STDLIB-RANGE-034)

@_cdecl("kk_range_toIntArray")
public func kk_range_toIntArray(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_toIntArray")
    }
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
    for (i, elem) in elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

// MARK: - ULongRange count, iterator, forEach, map (STDLIB-RANGE-037)

@_cdecl("kk_ulong_range_count")
public func kk_ulong_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_count")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        guard first <= last else { return 0 }
        let uStep = UInt(bitPattern: range.step)
        return Int(bitPattern: (last &- first) / uStep &+ 1)
    } else if range.step < 0 {
        guard first >= last else { return 0 }
        let uStep = UInt(range.step.magnitude)
        return Int(bitPattern: (first &- last) / uStep &+ 1)
    }
    return 0
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
        return kk_iterator_builder_hasNext(iterRaw)
    }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = UInt(bitPattern: iterator.current)
    let last = UInt(bitPattern: iterator.last)
    if iterator.step > 0 {
        return current <= last ? 1 : 0
    }
    if iterator.step < 0 {
        return current >= last ? 1 : 0
    }
    return 0
}

@_cdecl("kk_ulong_range_next")
public func kk_ulong_range_next(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return kk_iterator_builder_next(iterRaw)
    }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    let uCurrent = UInt(bitPattern: current)
    if iterator.step > 0 {
        let uStep = UInt(bitPattern: iterator.step)
        let (next, overflow) = uCurrent.addingReportingOverflow(uStep)
        // On overflow (e.g. current == UInt64.max) mark iteration done by zeroing step
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
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_forEach")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = first
        while current <= last {
            var thrown = 0
            _ = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = first
        while current >= last {
            var thrown = 0
            _ = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return 0
}

@_cdecl("kk_ulong_range_map")
public func kk_ulong_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = first
        while current <= last {
            var thrown = 0
            let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = first
        while current >= last {
            var thrown = 0
            let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
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
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
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

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeIteratorBuilderBox.self)
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
