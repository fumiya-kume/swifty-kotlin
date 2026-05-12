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

final class RuntimeRangeIteratorBox {
    var current: Int
    let last: Int
    var step: Int

    init(current: Int, last: Int, step: Int) {
        self.current = current
        self.last = last
        self.step = step
    }
}

func runtimeUnsignedRangeIsEmpty(_ range: RuntimeRangeBox) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        return first > last
    } else if range.step < 0 {
        return first < last
    }
    return true
}

func runtimeUnsignedRangeTraverse(
    _ range: RuntimeRangeBox,
    _ body: (_ current: UInt, _ index: Int) -> Bool
) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    var index = 0
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = first
        while current <= last {
            if !body(current, index) {
                return false
            }
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
            index &+= 1
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = first
        while current >= last {
            if !body(current, index) {
                return false
            }
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
            index &+= 1
        }
    }
    return true
}

func runtimeUnsignedRangeTraverseReversed(
    _ range: RuntimeRangeBox,
    _ body: (_ current: UInt) -> Bool
) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = last
        while current >= first {
            if !body(current) {
                return false
            }
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = last
        while current <= first {
            if !body(current) {
                return false
            }
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return true
}

func runtimeUnsignedRangeFirstMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = runtimeNullSentinelInt
    var didThrow = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            didThrow = true
            return false
        }
        if result != 0 {
            found = true
            match = Int(bitPattern: current)
            return false
        }
        return true
    }
    if found {
        return match
    }
    if didThrow {
        return orNull ? runtimeNullSentinelInt : 0
    }
    if orNull {
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: No element matching the predicate was found.")
    return 0
}

func runtimeUnsignedRangeLastMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = runtimeNullSentinelInt
    var didThrow = false
    _ = runtimeUnsignedRangeTraverseReversed(range) { current in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            didThrow = true
            return false
        }
        if result != 0 {
            found = true
            match = Int(bitPattern: current)
            return false
        }
        return true
    }
    if found {
        return match
    }
    if didThrow {
        return orNull ? runtimeNullSentinelInt : 0
    }
    if orNull {
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: No element matching the predicate was found.")
    return 0
}

// MARK: - Range randomOrNull helpers

func runtimeRandomIndex(count: Int, randomRaw: Int?) -> Int {
    if let randomRaw {
        return kk_random_nextInt_until(randomRaw, count, nil)
    }
    return Int.random(in: 0 ..< count)
}

func runtimeSignedRangeCount(_ range: RuntimeRangeBox) -> Int {
    if range.step > 0 {
        guard range.first <= range.last else { return 0 }
        return (range.last &- range.first) / range.step &+ 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first &- range.last) / (0 &- range.step) &+ 1
    }
    return 0
}

func runtimeUnsignedRangeCount(_ range: RuntimeRangeBox) -> Int {
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

func runtimeCharRangeCount(_ range: RuntimeRangeBox) -> Int {
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    if range.step > 0 {
        guard first <= last else { return 0 }
        return (last &- first) / range.step &+ 1
    } else if range.step < 0 {
        guard first >= last else { return 0 }
        return (first &- last) / (0 &- range.step) &+ 1
    }
    return 0
}

func runtimeSignedRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    let count = runtimeSignedRangeCount(range)
    guard count > 0 else { return runtimeNullSentinelInt }
    let index = runtimeRandomIndex(count: count, randomRaw: randomRaw)
    return range.first &+ (range.step &* index)
}

func runtimeUnsignedRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    let count = runtimeUnsignedRangeCount(range)
    guard count > 0 else { return runtimeNullSentinelInt }
    let index = UInt(runtimeRandomIndex(count: count, randomRaw: randomRaw))
    let first = UInt(bitPattern: range.first)
    if range.step > 0 {
        let step = UInt(bitPattern: range.step)
        return Int(bitPattern: first &+ (step &* index))
    }
    let step = UInt(range.step.magnitude)
    return Int(bitPattern: first &- (step &* index))
}

func runtimeCharRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    let count = runtimeCharRangeCount(range)
    guard count > 0 else { return runtimeNullSentinelInt }
    let index = runtimeRandomIndex(count: count, randomRaw: randomRaw)
    let first = kk_unbox_char(range.first)
    let value = first &+ (range.step &* index)
    return kk_box_char(value)
}

// MARK: - Range.random(Random) helpers (rejection sampling; STDLIB-RANGE-RANDOM-002)

func runtimeRandomBits(from randomRaw: Int) -> UInt64 {
    UInt64(bitPattern: Int64(kk_random_nextLong(randomRaw)))
}

func runtimeRandomIndex(upperBound: UInt64, randomRaw: Int) -> UInt64 {
    precondition(upperBound > 0)
    if upperBound == 1 {
        return 0
    }
    // Rejection sampling keeps the index uniform without modulo bias.
    let rejectionLimit = UInt64.max - (UInt64.max % upperBound)
    var candidate = runtimeRandomBits(from: randomRaw)
    while candidate >= rejectionLimit {
        candidate = runtimeRandomBits(from: randomRaw)
    }
    return candidate % upperBound
}

func runtimeRangeRandomError(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: Range is empty.")
    return 0
}

func runtimeSignedRangeRandom(
    first: Int,
    last: Int,
    step: Int,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard step != 0 else {
        return runtimeRangeRandomError(outThrown)
    }
    let ascending = step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeRangeRandomError(outThrown)
    }
    let absStep = UInt64(step.magnitude)
    let signMask = UInt64(1) << 63
    let firstOrdered = UInt64(bitPattern: Int64(first)) ^ signMask
    let lastOrdered = UInt64(bitPattern: Int64(last)) ^ signMask
    if absStep == 1 {
        // A full-width range can use the raw 64-bit random value directly.
        if ascending && firstOrdered == 0 && lastOrdered == UInt64.max {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
        if !ascending && firstOrdered == UInt64.max && lastOrdered == 0 {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
    }
    let distance = ascending ? lastOrdered &- firstOrdered : firstOrdered &- lastOrdered
    let count = distance / absStep + 1
    let index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    let offset = index &* absStep
    let chosenOrdered = ascending ? firstOrdered &+ offset : firstOrdered &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosenOrdered ^ signMask))
}

func runtimeUnsignedRangeRandom(
    first: UInt,
    last: UInt,
    step: Int,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard step != 0 else {
        return runtimeRangeRandomError(outThrown)
    }
    let ascending = step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeRangeRandomError(outThrown)
    }
    let absStep = UInt64(step.magnitude)
    let first64 = UInt64(first)
    let last64 = UInt64(last)
    if absStep == 1 {
        // A full-width unsigned range can use the raw 64-bit random value directly.
        if ascending && first64 == 0 && last64 == UInt64.max {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
        if !ascending && first64 == UInt64.max && last64 == 0 {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
    }
    let distance = ascending ? last64 &- first64 : first64 &- last64
    let count = distance / absStep + 1
    let index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    let offset = index &* absStep
    let chosen = ascending ? first64 &+ offset : first64 &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosen))
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
public func kk_op_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    // Kotlin spec: step() requires a strictly positive argument (STDLIB-022).
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
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

@_cdecl("kk_iterator_hasNext")
public func kk_iterator_hasNext(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return kk_iterator_builder_hasNext(iterRaw)
    }
    if runtimeRangeIteratorBox(from: iterRaw) != nil {
        return kk_range_hasNext(iterRaw)
    }
    if runtimeListIteratorBox(from: iterRaw) != nil {
        return kk_list_iterator_hasNext(iterRaw)
    }
    if runtimeMapIteratorBox(from: iterRaw) != nil {
        return kk_map_iterator_hasNext(iterRaw)
    }
    if runtimeStringIteratorBox(from: iterRaw) != nil {
        return kk_string_iterator_hasNext(iterRaw)
    }
    if runtimeIndexingIteratorBox(from: iterRaw) != nil {
        return kk_indexing_iterable_hasNext(iterRaw)
    }
    return 0
}

@_cdecl("kk_iterator_next")
public func kk_iterator_next(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return kk_iterator_builder_next(iterRaw)
    }
    if runtimeRangeIteratorBox(from: iterRaw) != nil {
        return kk_range_next(iterRaw)
    }
    if runtimeListIteratorBox(from: iterRaw) != nil {
        return kk_list_iterator_next(iterRaw)
    }
    if runtimeMapIteratorBox(from: iterRaw) != nil {
        return kk_map_iterator_next(iterRaw)
    }
    if runtimeStringIteratorBox(from: iterRaw) != nil {
        return kk_string_iterator_next(iterRaw)
    }
    if runtimeIndexingIteratorBox(from: iterRaw) != nil {
        return kk_indexing_iterable_next(iterRaw)
    }
    return 0
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

@_cdecl("kk_range_contains")
public func kk_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_contains")
    }
    if range.step == 0 {
        return 0
    }
    if range.step > 0 {
        guard range.first <= value && value <= range.last else { return 0 }
        
        // Enhanced overflow protection: check if value is within reasonable bounds first
        // For extremely large ranges, use a more conservative approach
        if range.first == Int.min && range.last == Int.max {
            // Full range - all values are contained
            return 1
        }
        
        // Use Int128-style calculation through careful checking to prevent overflow
        let diff = value - range.first
        let step = range.step
        
        // Additional safety check for potential overflow cases
        if diff == 0 {
            return 1  // First element is always contained
        }
        
        // Check if diff and step have same sign (both positive or both negative)
        // This helps avoid overflow in modulo operation
        if (diff >= 0 && step > 0) || (diff <= 0 && step < 0) {
            return diff % step == 0 ? 1 : 0
        } else {
            // Different signs - use absolute values to avoid overflow
            let absDiff = diff < 0 ? -diff : diff
            let absStep = step < 0 ? -step : step
            return absDiff % absStep == 0 ? 1 : 0
        }
    } else {
        guard range.first >= value && value >= range.last else { return 0 }
        
        // Enhanced overflow protection for negative step ranges
        if range.first == Int.max && range.last == Int.min {
            // Full reverse range - all values are contained
            return 1
        }
        
        let diff = range.first - value
        let step = 0 &- range.step  // Make step positive
        
        // Additional safety check for potential overflow cases
        if diff == 0 {
            return 1  // First element is always contained
        }
        
        // Use Int64 for large differences but with additional bounds checking
        if diff > Int64.max || diff < Int64.min {
            // For extremely large differences, fall back to safer calculation
            let absDiff = diff < 0 ? -diff : diff
            let absStep = step < 0 ? -step : step
            return absDiff % absStep == 0 ? 1 : 0
        }
        
        let diff64 = Int64(diff)
        let step64 = Int64(step)
        return diff64 % step64 == 0 ? 1 : 0
    }
}

@_cdecl("kk_range_start")
public func kk_range_start(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_start")
    }
    return range.first
}

@_cdecl("kk_range_end")
public func kk_range_end(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_end")
    }
    return range.last
}

@_cdecl("kk_range_endExclusive")
public func kk_range_endExclusive(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_endExclusive")
    }
    return range.last &+ 1
}

// MARK: - IntRange take/drop/average/sorted (STDLIB-RANGE-TDS)

@_cdecl("kk_range_take")
public func kk_range_take(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_take")
    }
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var elements: [Int] = []
    var current = range.first
    var taken = 0
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

@_cdecl("kk_range_drop")
public func kk_range_drop(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_drop")
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

@_cdecl("kk_range_average")
public func kk_range_average(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_average")
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

@_cdecl("kk_range_sorted")
public func kk_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_sorted")
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

// MARK: - CharRange HOFs (STDLIB-290)

@_cdecl("kk_char_range_isEmpty")
public func kk_char_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_isEmpty")
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    if range.step > 0 {
        return first > last ? 1 : 0
    } else if range.step < 0 {
        return first < last ? 1 : 0
    }
    return 1
}

@_cdecl("kk_char_range_step")
public func kk_char_range_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return rangeRaw
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let alignedLast = runtimeSignedProgressionLast(start: first, end: last, step: nextStep)
    return registerRuntimeObject(RuntimeRangeBox(first: first, last: alignedLast, step: nextStep))
}

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

@_cdecl("kk_char_range_take")
public func kk_char_range_take(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_take")
    }
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    var taken = 0
    if range.step > 0 {
        var current = first
        while current <= last && taken < n {
            elements.append(kk_box_char(current))
            current &+= range.step
            taken += 1
        }
    } else if range.step < 0 {
        var current = first
        while current >= last && taken < n {
            elements.append(kk_box_char(current))
            current &+= range.step
            taken += 1
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_char_range_drop")
public func kk_char_range_drop(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_drop")
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    var skipped = 0
    if range.step > 0 {
        var current = first
        while current <= last {
            if skipped >= n { elements.append(kk_box_char(current)) }
            else { skipped += 1 }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            if skipped >= n { elements.append(kk_box_char(current)) }
            else { skipped += 1 }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_char_range_sorted")
public func kk_char_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_sorted")
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
    elements.sort { kk_unbox_char($0) < kk_unbox_char($1) }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_char_range_randomOrNull")
public func kk_char_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_randomOrNull")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_char_range_randomOrNull_random")
public func kk_char_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_randomOrNull_random")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_char_range_random_random")
public func kk_char_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_random_random")
    }
    return runtimeSignedRangeRandom(
        first: range.first,
        last: range.last,
        step: range.step,
        randomRaw: randomRaw,
        outThrown: outThrown
    )
}

// MARK: - Progression fromClosedRange (STDLIB-RANGE-039)

func runtimeSignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
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

func runtimeUnsignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
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

@_cdecl("kk_char_progression_fromClosedRange")
public func kk_char_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let startChar = kk_unbox_char(rangeStart)
    let endChar = kk_unbox_char(rangeEnd)
    let alignedLast = runtimeSignedProgressionLast(start: startChar, end: endChar, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: startChar, last: alignedLast, step: step))
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
