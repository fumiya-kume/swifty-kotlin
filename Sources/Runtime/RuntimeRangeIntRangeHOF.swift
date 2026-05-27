import Foundation

// swiftlint:disable file_length

/// IntRange higher-order / aggregation / search / partitioning
/// runtime entry points (STDLIB-091, STDLIB-RANGE-038).
///
/// Split out from `RuntimeRangeAndDispatch.swift`.

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
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_forEach")
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

@_cdecl("kk_range_map")
public func kk_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    
    // Pre-calculate range size for memory efficiency
    let count = kk_range_count(rangeRaw)
    var mapped: [Int] = []
    mapped.reserveCapacity(count)
    
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

@_cdecl("kk_range_mapIndexed")
public func kk_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_mapIndexed")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    
    // Pre-calculate range size for memory efficiency
    let count = kk_range_count(rangeRaw)
    var mapped: [Int] = []
    mapped.reserveCapacity(count)
    
    var current = range.first
    var index = 0
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, index, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            current &+= range.step
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, index, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            mapped.append(result)
            current &+= range.step
            index &+= 1
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_range_mapNotNull")
public func kk_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_mapNotNull")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != runtimeNullSentinelInt {
                mapped.append(result)
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != runtimeNullSentinelInt {
                mapped.append(result)
            }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_range_filter")
public func kk_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filter")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    
    // Pre-calculate range size for memory efficiency (worst case all elements match)
    let count = kk_range_count(rangeRaw)
    var filtered: [Int] = []
    filtered.reserveCapacity(count)
    
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != 0 {
                filtered.append(current)
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != 0 {
                filtered.append(current)
            }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_range_filterIndexed")
public func kk_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filterIndexed")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    var current = range.first
    var index = 0
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, index, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != 0 {
                filtered.append(current)
            }
            current &+= range.step
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, index, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result != 0 {
                filtered.append(current)
            }
            current &+= range.step
            index &+= 1
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_range_filterNot")
public func kk_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filterNot")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result == 0 {
                filtered.append(current)
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
            if result == 0 {
                filtered.append(current)
            }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

// MARK: - IntRange Aggregation HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_reduce")
public func kk_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_reduce")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)

    // Check if range is empty
    if range.step > 0 && range.first > range.last {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    if range.step < 0 && range.first < range.last {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }

    var accumulator = range.first
    var current = range.first &+ range.step
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    }
    return accumulator
}

@_cdecl("kk_range_reduceIndexed")
public func kk_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_reduceIndexed")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)

    // Check if range is empty
    if range.step > 0 && range.first > range.last {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    if range.step < 0 && range.first < range.last {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }

    var accumulator = range.first
    var current = range.first &+ range.step
    var index = 1
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
            index &+= 1
        }
    }
    return accumulator
}

@_cdecl("kk_range_fold")
public func kk_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_fold")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)

    var accumulator = initialValue
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    }
    return accumulator
}

@_cdecl("kk_range_foldIndexed")
public func kk_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_foldIndexed")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)

    var accumulator = initialValue
    var current = range.first
    var index = 0
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
            index &+= 1
        }
    }
    return accumulator
}

// MARK: - IntRange Search and Predicate HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_find")
public func kk_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_find")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_range_findLast")
public func kk_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                             _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_findLast")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.last
    if range.step > 0 {
        while current >= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    } else if range.step < 0 {
        while current <= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_range_first_predicate")
public func kk_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_first_predicate")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: No element matching the predicate was found.")
    return 0
}

@_cdecl("kk_range_firstOrNull_predicate")
public func kk_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_firstOrNull_predicate")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &+= range.step
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_range_firstOrNull")
public func kk_range_firstOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_firstOrNull")
    }
    if range.step == 0 {
        return runtimeNullSentinelInt
    }
    if range.step > 0 {
        return range.first <= range.last ? range.first : runtimeNullSentinelInt
    }
    return range.first >= range.last ? range.first : runtimeNullSentinelInt
}

@_cdecl("kk_range_randomOrNull")
public func kk_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_randomOrNull")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_range_randomOrNull_random")
public func kk_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_randomOrNull_random")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_range_last_predicate")
public func kk_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_last_predicate")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.last
    if range.step > 0 {
        while current >= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    } else if range.step < 0 {
        while current <= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: No element matching the predicate was found.")
    return 0
}

@_cdecl("kk_range_lastOrNull_predicate")
public func kk_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_lastOrNull_predicate")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.last
    if range.step > 0 {
        while current >= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    } else if range.step < 0 {
        while current <= range.first {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
            if result != 0 {
                return current
            }
            current &-= range.step
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_range_lastOrNull")
public func kk_range_lastOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_lastOrNull")
    }
    if range.step == 0 {
        return runtimeNullSentinelInt
    }
    if range.step > 0 {
        return range.first <= range.last ? range.last : runtimeNullSentinelInt
    }
    return range.first >= range.last ? range.last : runtimeNullSentinelInt
}

@_cdecl("kk_range_random")
public func kk_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_random")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: 0,
        outThrown: outThrown
    )
}

@_cdecl("kk_range_random_random")
public func kk_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_random_random")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: randomRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_random_nextInt_rangeObject")
public func kk_random_nextInt_rangeObject(_ randomRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_random_nextInt_rangeObject")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: randomRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_range_any")
public func kk_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_any")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return 1
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return 1
            }
            current &+= range.step
        }
    }
    return 0
}

@_cdecl("kk_range_all")
public func kk_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_all")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result == 0 {
                return 0
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result == 0 {
                return 0
            }
            current &+= range.step
        }
    }
    return 1
}

@_cdecl("kk_range_none")
public func kk_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_none")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return 0
            }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            var thrown = 0
            let result = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if result != 0 {
                return 0
            }
            current &+= range.step
        }
    }
    return 1
}

// MARK: - IntRange Partitioning HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_chunked")
public func kk_range_chunked(_ rangeRaw: Int, _ size: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_chunked")
    }
    guard size > 0 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    var chunks: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current <= range.last {
                chunkElements.append(current)
                current &+= range.step
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    } else if range.step < 0 {
        while current >= range.last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current >= range.last {
                chunkElements.append(current)
                current &+= range.step
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: chunks))
}

@_cdecl("kk_range_windowed")
public func kk_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_windowed")
    }
    guard size > 0, step > 0 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    var windows: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent <= range.last {
                windowElements.append(windowCurrent)
                windowCurrent &+= range.step
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            current &+= (range.step * step)
        }
    } else if range.step < 0 {
        while current >= range.last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent >= range.last {
                windowElements.append(windowCurrent)
                windowCurrent &+= range.step
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            current &+= (range.step * step)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}
