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
    var step: Int

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
    if rhs <= lhs {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1))
}

@_cdecl("kk_op_ulong_rangeUntil")
public func kk_op_ulong_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    let lhsUnsigned = UInt(bitPattern: lhs)
    let rhsUnsigned = UInt(bitPattern: rhs)
    if rhsUnsigned <= lhsUnsigned {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1))
}

@_cdecl("kk_op_downTo")
public func kk_op_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_op_step")
public func kk_op_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    // Validate step constraints (STDLIB-RANGE-039)
    guard stepValue > 0 else {
        return rangeRaw // Return unchanged for invalid step
    }
    guard stepValue != Int.min else {
        return rangeRaw // Return unchanged for invalid step
    }

    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return rangeRaw
    }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    // Align 'last' to the step like Kotlin's getProgressionLastElement:
    // last is the final value in the progression that stays within the range.
    // Guard empty ranges first — Kotlin returns 'last' unchanged for empty
    // progressions (positive step: first > last; negative step: first < last).
    // Use wrapping arithmetic (&-/&+) to avoid trapping on extreme Int ranges.
    let alignedLast: Int
    if nextStep > 0 {
        guard range.first <= range.last else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard range.first >= range.last else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

@_cdecl("kk_range_iterator")
public func kk_range_iterator(_ rangeRaw: Int) -> Int {
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

@_cdecl("kk_range_hasNext")
public func kk_range_hasNext(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return kk_iterator_builder_hasNext(iterRaw)
    }
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
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return kk_iterator_builder_next(iterRaw)
    }
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
        // Use wrapping arithmetic to avoid trapping on extreme ranges
        // (e.g., first == Int.min, last == Int.max).
        return (range.last &- range.first) / range.step &+ 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first &- range.last) / (0 &- range.step) &+ 1
    }
    return 0
}

@_cdecl("kk_range_isEmpty")
public func kk_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_isEmpty")
    }
    if range.step > 0 {
        return range.first > range.last ? 1 : 0
    } else if range.step < 0 {
        return range.first < range.last ? 1 : 0
    }
    return 1
}

@_cdecl("kk_range_sum")
public func kk_range_sum(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_sum")
    }
    var sum = 0
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            sum &+= current
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            sum &+= current
            current &+= range.step
        }
    }
    return sum
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

@_cdecl("kk_range_mapIndexed")
public func kk_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_mapIndexed")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
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
    var filtered: [Int] = []
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

// MARK: - CharRange HOFs (STDLIB-290)

@_cdecl("kk_char_range_toList")
public func kk_char_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    if range.step > 0 {
        var current = first
        while current <= last {
            elements.append(kk_box_char(current))
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            elements.append(kk_box_char(current))
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_char_range_forEach")
public func kk_char_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    if range.step > 0 {
        var current = first
        while current <= last {
            var thrown = 0
            // Pass raw char value (Unicode scalar) — the lambda expects Char-typed values
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            var thrown = 0
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            current &+= range.step
        }
    }
    return 0
}

// MARK: - Progression fromClosedRange (STDLIB-RANGE-039)

private func runtimeSignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
    if step > 0 {
        guard start <= end else { return end }
        let distance = end &- start
        return end &- (distance % step)
    }
    guard start >= end else { return end }
    let magnitude = 0 &- step
    let distance = start &- end
    return end &+ (distance % magnitude)
}

private func runtimeUnsignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
    let startUnsigned = UInt(bitPattern: start)
    let endUnsigned = UInt(bitPattern: end)
    if step > 0 {
        guard startUnsigned <= endUnsigned else { return end }
        let magnitude = UInt(step)
        let distance = endUnsigned &- startUnsigned
        return Int(bitPattern: endUnsigned &- (distance % magnitude))
    }
    guard startUnsigned >= endUnsigned else { return end }
    let magnitude = UInt((0 &- step))
    let distance = startUnsigned &- endUnsigned
    return Int(bitPattern: endUnsigned &+ (distance % magnitude))
}

@_cdecl("kk_int_progression_fromClosedRange")
public func kk_int_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("kk_long_progression_fromClosedRange")
public func kk_long_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // For LongProgression, we use the same RuntimeRangeBox but treat values as Long
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("kk_uint_progression_fromClosedRange")
public func kk_uint_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // UIntProgression uses signed Int for step, UInt for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("kk_ulong_progression_fromClosedRange")
public func kk_ulong_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // ULongProgression uses signed Int for step, ULong for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

// MARK: - UIntProgression operations (STDLIB-RANGE-039)

@_cdecl("kk_uint_rangeTo")
public func kk_uint_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_uint_downTo")
public func kk_uint_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_uint_step")
public func kk_uint_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    // Validate step constraints (STDLIB-RANGE-039)
    guard stepValue > 0 else {
        return rangeRaw // Return unchanged for invalid step
    }
    guard stepValue != Int.min else {
        return rangeRaw // Return unchanged for invalid step
    }

    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return rangeRaw
    }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue

    // For UInt ranges, use unsigned comparison logic
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)

    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

@_cdecl("kk_uint_range_reversed")
public func kk_uint_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

@_cdecl("kk_uint_range_toList")
public func kk_uint_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_toList")
    }
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    var elements: [Int] = []
    var current = firstUnsigned

    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= lastUnsigned {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= lastUnsigned {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

// MARK: - UIntRange properties and HOFs (STDLIB-RANGE-036)

@_cdecl("kk_uint_range_contains")
public func kk_uint_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_contains")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let uValue = UInt(bitPattern: value)
    let rawStep = range.step
    if rawStep > 0 {
        let uStep = UInt(bitPattern: rawStep)
        guard first <= uValue && uValue <= last else { return 0 }
        return (uValue - first) % uStep == 0 ? 1 : 0
    } else if rawStep < 0 {
        let uStep = UInt(bitPattern: -rawStep)
        guard last <= uValue && uValue <= first else { return 0 }
        return (first - uValue) % uStep == 0 ? 1 : 0
    }
    return 0
}

@_cdecl("kk_uint_range_isEmpty")
public func kk_uint_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_isEmpty")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        return first > last ? 1 : 0
    } else if range.step < 0 {
        return first < last ? 1 : 0
    }
    return 1
}

@_cdecl("kk_uint_range_first")
public func kk_uint_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_first")
    }
    return range.first
}

@_cdecl("kk_uint_range_last")
public func kk_uint_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_last")
    }
    return range.last
}

@_cdecl("kk_uint_range_step")
public func kk_uint_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_step")
    }
    return range.step
}

@_cdecl("kk_uint_range_count")
public func kk_uint_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_count")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        guard first <= last else { return 0 }
        let uStep = UInt(bitPattern: range.step)
        return Int(bitPattern: (last - first) / uStep + 1)
    } else if range.step < 0 {
        guard first >= last else { return 0 }
        let uStep = UInt(range.step.magnitude)
        return Int(bitPattern: (first - last) / uStep + 1)
    }
    return 0
}

@_cdecl("kk_uint_range_sum")
public func kk_uint_range_sum(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_sum")
    }
    var sum = UInt(0)
    var current = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= last {
            sum &+= current
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= last {
            sum &+= current
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return Int(bitPattern: sum)
}

@_cdecl("kk_uint_range_toUIntArray")
public func kk_uint_range_toUIntArray(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_toUIntArray")
    }
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    var elements: [Int] = []
    var current = firstUnsigned

    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= lastUnsigned {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= lastUnsigned {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_uint_range_forEach")
public func kk_uint_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_forEach")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var current = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
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

@_cdecl("kk_uint_range_map")
public func kk_uint_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    var current = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= last {
            var thrown = 0
            let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeListBox(elements: []))
            }
            mapped.append(result)
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= last {
            var thrown = 0
            let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeListBox(elements: []))
            }
            mapped.append(result)
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

// MARK: - ULongProgression operations (STDLIB-RANGE-039)

@_cdecl("kk_ulong_rangeTo")
public func kk_ulong_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_ulong_downTo")
public func kk_ulong_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_ulong_step")
public func kk_ulong_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    // Validate step constraints (STDLIB-RANGE-039)
    guard stepValue > 0 else {
        return rangeRaw // Return unchanged for invalid step
    }
    guard stepValue != Int.min else {
        return rangeRaw // Return unchanged for invalid step
    }

    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return rangeRaw
    }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue

    // For ULong ranges, use unsigned comparison logic
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)

    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

@_cdecl("kk_ulong_range_reversed")
public func kk_ulong_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

// MARK: - ULongRange toList (STDLIB-524)

@_cdecl("kk_ulong_range_toList")
public func kk_ulong_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_toList")
    }
    // Reinterpret signed Int fields as UInt for correct unsigned comparison
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let step = range.step
    var elements: [Int] = []
    var current = first
    if step > 0 {
        let uStep = UInt(bitPattern: step)
        while current <= last {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if step < 0 {
        // Use magnitude to avoid trapping on Int.min negation
        let uStep = UInt(step.magnitude)
        while current >= last {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_range_step")
public func kk_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_step")
    }
    return range.step
}

// MARK: - ULongRange properties (STDLIB-RANGE-037)

@_cdecl("kk_ulong_range_contains")
public func kk_ulong_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_contains")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let uValue = UInt(bitPattern: value)
    return (first <= uValue && uValue <= last) ? 1 : 0
}

@_cdecl("kk_ulong_range_first")
public func kk_ulong_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_first")
    }
    return range.first
}

@_cdecl("kk_ulong_range_last")
public func kk_ulong_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_last")
    }
    return range.last
}

@_cdecl("kk_ulong_range_step")
public func kk_ulong_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_step")
    }
    return range.step
}

@_cdecl("kk_ulong_range_isEmpty")
public func kk_ulong_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_isEmpty")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        return first > last ? 1 : 0
    } else if range.step < 0 {
        return first < last ? 1 : 0
    }
    return 1
}

@_cdecl("kk_ulong_range_toULongArray")
public func kk_ulong_range_toULongArray(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_toULongArray")
    }
    // Reinterpret signed Int fields as UInt for correct unsigned comparison
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let step = range.step
    var elements: [Int] = []
    var current = first
    if step > 0 {
        let uStep = UInt(bitPattern: step)
        while current <= last {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if step < 0 {
        // Use magnitude to avoid trapping on Int.min negation
        let uStep = UInt(step.magnitude)
        while current >= last {
            elements.append(Int(bitPattern: current))
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

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
