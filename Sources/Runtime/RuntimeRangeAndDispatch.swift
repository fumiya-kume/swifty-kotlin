
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

/// BUG-198: Iterator state for compiler-lowered signed range `for-in` loops.
/// This intentionally has no Iterator itable: the lowering calls the three
/// dedicated entry points directly, while explicit `range.iterator()` keeps the
/// KSP-452 source-backed iterator implementation.
final class RuntimeSignedRangeForInIteratorBox {
    var current: Int
    let last: Int
    let step: Int
    var hasNextValue: Bool

    init(current: Int, last: Int, step: Int) {
        self.current = current
        self.last = last
        self.step = step
        if step > 0 {
            self.hasNextValue = current <= last
        } else if step < 0 {
            self.hasNextValue = current >= last
        } else {
            self.hasNextValue = false
        }
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
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
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
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

// MARK: - Signed range traverse helpers (parallel to unsigned variants above)

func runtimeSignedRangeIsEmpty(_ range: RuntimeRangeBox) -> Bool {
    if range.step > 0 { return range.first > range.last }
    if range.step < 0 { return range.first < range.last }
    return true
}

func runtimeSignedRangeTraverse(
    _ range: RuntimeRangeBox,
    _ body: (_ current: Int, _ index: Int) -> Bool
) -> Bool {
    var current = range.first
    var index = 0
    if range.step > 0 {
        while current <= range.last {
            if !body(current, index) { return false }
            current &+= range.step
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            if !body(current, index) { return false }
            current &+= range.step
            index &+= 1
        }
    }
    return true
}

func runtimeSignedRangeTraverseReversed(
    _ range: RuntimeRangeBox,
    _ body: (_ current: Int) -> Bool
) -> Bool {
    var current = range.last
    if range.step > 0 {
        while current >= range.first {
            if !body(current) { return false }
            current &-= range.step
        }
    } else if range.step < 0 {
        while current <= range.first {
            if !body(current) { return false }
            current &-= range.step
        }
    }
    return true
}

func runtimeSignedRangeFirstMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = 0
    var didThrow = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if result != 0 { found = true; match = current; return false }
        return true
    }
    if found { return match }
    if didThrow { return orNull ? runtimeNullSentinelInt : 0 }
    if orNull { return runtimeNullSentinelInt }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

func runtimeSignedRangeLastMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = 0
    var didThrow = false
    _ = runtimeSignedRangeTraverseReversed(range) { current in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if result != 0 { found = true; match = current; return false }
        return true
    }
    if found { return match }
    if didThrow { return orNull ? runtimeNullSentinelInt : 0 }
    if orNull { return runtimeNullSentinelInt }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

// MARK: - Range randomOrNull helpers

func runtimeRandomIndex(count: Int, randomRaw: Int?) -> Int {
    if let randomRaw {
        return runtimeRandomNextIntBelow(randomRaw, count)
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
    guard range.step != 0 else { return runtimeNullSentinelInt }
    let ascending = range.step > 0
    guard ascending ? range.first <= range.last : range.first >= range.last else {
        return runtimeNullSentinelInt
    }
    let absStep = UInt64(range.step.magnitude)
    let signMask = UInt64(1) << 63
    let firstOrdered = UInt64(bitPattern: Int64(range.first)) ^ signMask
    let lastOrdered = UInt64(bitPattern: Int64(range.last)) ^ signMask
    let distance = ascending ? lastOrdered &- firstOrdered : firstOrdered &- lastOrdered
    if absStep == 1 && distance == UInt64.max {
        let bits: UInt64
        if let randomRaw {
            bits = runtimeRandomBits(from: randomRaw)
        } else {
            var rng = SystemRandomNumberGenerator()
            bits = rng.next()
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: bits))
    }
    let count = distance / absStep + 1
    let index: UInt64
    if let randomRaw {
        index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    } else if count == UInt64.max {
        var rng = SystemRandomNumberGenerator()
        index = rng.next() % count
    } else {
        index = UInt64.random(in: 0 ..< count)
    }
    let offset = index &* absStep
    let chosenOrdered = ascending ? firstOrdered &+ offset : firstOrdered &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosenOrdered ^ signMask))
}

func runtimeUnsignedRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    guard range.step != 0 else { return runtimeNullSentinelInt }
    let first = UInt64(UInt(bitPattern: range.first))
    let last = UInt64(UInt(bitPattern: range.last))
    let ascending = range.step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeNullSentinelInt
    }
    let absStep = UInt64(range.step.magnitude)
    let distance = ascending ? last &- first : first &- last
    if absStep == 1 && distance == UInt64.max {
        let bits: UInt64
        if let randomRaw {
            bits = runtimeRandomBits(from: randomRaw)
        } else {
            var rng = SystemRandomNumberGenerator()
            bits = rng.next()
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: bits))
    }
    let count = distance / absStep + 1
    let index: UInt64
    if let randomRaw {
        index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    } else if count == UInt64.max {
        var rng = SystemRandomNumberGenerator()
        index = rng.next() % count
    } else {
        index = UInt64.random(in: 0 ..< count)
    }
    let offset = index &* absStep
    let chosen = ascending ? first &+ offset : first &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosen))
}

func runtimeCharRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    let count = runtimeCharRangeCount(range)
    guard count > 0 else { return runtimeNullSentinelInt }
    let index = runtimeRandomIndex(count: count, randomRaw: randomRaw)
    let first = kk_unbox_char(range.first)
    let value = first &+ (range.step &* index)
    return kk_box_char(value)
}

func runtimeCharRangeRandom(
    _ range: RuntimeRangeBox,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let count = runtimeCharRangeCount(range)
    guard count > 0 else { return runtimeRangeRandomError(outThrown) }
    let index = runtimeRandomIndex(upperBound: UInt64(count), randomRaw: randomRaw)
    let first = kk_unbox_char(range.first)
    let value = first &+ (range.step &* Int(truncatingIfNeeded: index))
    return kk_box_char(value)
}

// MARK: - Range.random(Random) helpers (rejection sampling; STDLIB-RANGE-RANDOM-002)

func runtimeRandomBits(from randomRaw: Int) -> UInt64 {
    runtimeRandomNextBits64(randomRaw)
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
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "Range is empty.")
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
        outThrown?.pointee = runtimeAllocateNullPointerException(message: "")
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

@_cdecl("__kk_op_rangeUntil")
public func __kk_op_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    if rhs <= lhs {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1))
}

@_cdecl("__kk_op_ulong_rangeUntil")
public func __kk_op_ulong_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    let lhsUnsigned = UInt(bitPattern: lhs)
    let rhsUnsigned = UInt(bitPattern: rhs)
    if rhsUnsigned <= lhsUnsigned {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1))
}

@_cdecl("__kk_op_downTo")
public func __kk_op_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("__kk_op_step")
public func __kk_op_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    // Kotlin spec: step() requires a strictly positive argument (STDLIB-022).
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
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

private let runtimeIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Iterable"
)

/// BUG-167: Calls `iterator()` on a source-implemented `Iterable` object through
/// the `kotlin.collections.Iterable` itable (method slot 0). Returns nil when
/// the value does not implement `Iterable` in source, so callers can fall back
/// to the runtime box representations.
func runtimeSourceIterableIterator(
    _ iterableRaw: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    outThrown?.pointee = 0
    let fnPtr = kk_itable_lookup_dynamic(iterableRaw, Int(runtimeIterableInterfaceTypeID), 0)
    guard fnPtr != 0 else {
        return nil
    }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let iterRaw = fn(iterableRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "Iterable.iterator() dispatch"
        )
        return nil
    }
    return iterRaw
}

/// KSP-998: Explicit `Iterable.iterator()` calls use a throwing bridge so a
/// source iterator is acquired lazily and its exception reaches Kotlin catch.
@_cdecl("kk_iterable_iterator")
public func kk_iterable_iterator(_ iterableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: iterableRaw) != nil {
        return iterableRaw
    }
    if runtimeSequenceBox(from: iterableRaw) != nil {
        let elements = runtimeSequenceSourceElementsOrPanic(from: iterableRaw, caller: #function)
        return registerRuntimeObject(RuntimeListIteratorBox(elements: elements))
    }
    if runtimeListBox(from: iterableRaw) != nil || runtimeSetBox(from: iterableRaw) != nil {
        return kk_list_iterator(iterableRaw)
    }
    if let arrayBox = runtimeArrayBox(from: iterableRaw), type(of: arrayBox) == RuntimeArrayBox.self {
        return kk_list_iterator(iterableRaw)
    }
    // Preserve the legacy compiler bridge for the old runtime-backed
    // IndexingIterable representation while source-backed withIndex() uses the
    // Kotlin IndexingIterable class above.
    if runtimeIndexingIterableBox(from: iterableRaw) != nil {
        return kk_indexing_iterable_iterator(iterableRaw)
    }
    if let sourceIterator = runtimeSourceIterableIterator(iterableRaw, outThrown: outThrown) {
        return sourceIterator
    }
    guard let range = runtimeRangeBox(from: iterableRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_range_iterator")
public func kk_range_iterator(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil {
        return rangeRaw
    }
    if runtimeSequenceBox(from: rangeRaw) != nil {
        let elements = runtimeSequenceSourceElementsOrPanic(from: rangeRaw, caller: #function)
        return registerRuntimeObject(RuntimeListIteratorBox(elements: elements))
    }
    if runtimeListBox(from: rangeRaw) != nil {
        return kk_list_iterator(rangeRaw)
    }
    if runtimeSetBox(from: rangeRaw) != nil {
        return kk_list_iterator(rangeRaw)
    }
    // `for (x in arrayOf(...))` (and other raw arrays: IntArray, ByteArray, ...)
    // reaches this generic for-loop entry point same as List, when the iterable
    // has no compile-time-resolved iterator (e.g. a generic Iterable<T>
    // parameter); without this branch an array falls through to the range-box
    // guard below, gets treated as an invalid range, and the loop silently
    // iterates zero times (kk_range_hasNext sees no RuntimeRangeIteratorBox).
    // The exact-type check excludes RuntimeObjectBox, a RuntimeArrayBox subclass
    // used for ordinary class instances.
    if let arrayBox = runtimeArrayBox(from: rangeRaw), type(of: arrayBox) == RuntimeArrayBox.self {
        return kk_list_iterator(rangeRaw)
    }
    // BUG-167: A source-implemented `Iterable` (e.g. `class C : Iterable<Int>`)
    // reaches this entry point too, since its `iterator()` is only known
    // dynamically. Dispatch it through the `kotlin.collections.Iterable` itable
    // — the same shape `runtimeTraverseSourceSequenceObject` uses for
    // `Sequence` — instead of treating the object as an invalid range.
    if let sourceIterator = runtimeSourceIterableIterator(rangeRaw, outThrown: outThrown) {
        return sourceIterator
    }
    if let outThrown, outThrown.pointee != 0 {
        return 0
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
        return __kk_iterator_builder_hasNext(iterRaw)
    }
    if runtimeListIteratorBox(from: iterRaw) != nil {
        return kk_list_iterator_hasNext(iterRaw)
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
        return __kk_iterator_builder_next(iterRaw)
    }
    if runtimeListIteratorBox(from: iterRaw) != nil {
        return kk_list_iterator_next(iterRaw)
    }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    iterator.current = iterator.current &+ iterator.step
    return current
}

/// BUG-198: Fast path used only after lowering proves a signed built-in range.
@_cdecl("kk_range_for_in_iterator")
public func kk_range_for_in_iterator(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeSignedRangeForInIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_range_for_in_hasNext")
public func kk_range_for_in_hasNext(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeSignedRangeForInIteratorBox(from: iterRaw) else {
        return 0
    }
    return iterator.hasNextValue ? 1 : 0
}

@_cdecl("kk_range_for_in_next")
public func kk_range_for_in_next(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeSignedRangeForInIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    guard iterator.hasNextValue else {
        return current
    }

    let (candidate, overflow) = current.addingReportingOverflow(iterator.step)
    if overflow {
        iterator.hasNextValue = false
        return current
    }
    if iterator.step > 0 {
        iterator.hasNextValue = candidate > current && candidate <= iterator.last
    } else if iterator.step < 0 {
        iterator.hasNextValue = candidate < current && candidate >= iterator.last
    } else {
        iterator.hasNextValue = false
    }
    iterator.current = candidate
    return current
}

@_cdecl("kk_iterator_hasNext")
public func kk_iterator_hasNext(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return __kk_iterator_builder_hasNext(iterRaw)
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
    if runtimeIndexingIteratorBox(from: iterRaw) != nil {
        return kk_indexing_iterable_hasNext(iterRaw)
    }
    if let objectResult = runtimeObjectIteratorMethodCall(iterRaw, methodSlot: 0, outThrown: outThrown) {
        return objectResult
    }
    return 0
}

@_cdecl("kk_iterator_next")
public func kk_iterator_next(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: iterRaw) != nil {
        return __kk_iterator_builder_next(iterRaw)
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
    if runtimeIndexingIteratorBox(from: iterRaw) != nil {
        return kk_indexing_iterable_next(iterRaw)
    }
    if let objectResult = runtimeObjectIteratorMethodCall(iterRaw, methodSlot: 1, outThrown: outThrown) {
        if let outThrown, outThrown.pointee != 0 {
            return objectResult
        }
        // Iterator<T>.next() crosses an erased generic boundary. Source-backed
        // CharIterator implementations return the raw Char scalar from their
        // concrete method, so box it before generic consumers store the value.
        if runtimeSourceIteratorValue(objectResult, iteratorRaw: iterRaw).tag == RuntimeValue.charTag {
            return kk_box_char(objectResult)
        }
        return objectResult
    }
    return 0
}

private func runtimeObjectIteratorMethodCall(
    _ iterRaw: Int,
    methodSlot: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let iteratorInterfaceSlot = 0
    let functionRaw = kk_itable_lookup(iterRaw, iteratorInterfaceSlot, methodSlot)
    guard functionRaw != 0 else {
        return nil
    }

    let method = unsafeBitCast(
        functionRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = method(iterRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "Iterator object dispatch"
        )
        return 0
    }
    return result
}

// MARK: - IntRange properties (STDLIB-092)

@_cdecl("__kk_range_first")
public func kk_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_first")
    }
    return range.first
}

@_cdecl("__kk_range_last")
public func kk_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_last")
    }
    return range.last
}

@_cdecl("__kk_range_count")
public func kk_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_count")
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

@_cdecl("__kk_range_isEmpty")
public func kk_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_isEmpty")
    }
    if range.step > 0 {
        return range.first > range.last ? 1 : 0
    } else if range.step < 0 {
        return range.first < range.last ? 1 : 0
    }
    return 1
}

@_cdecl("__kk_range_sum")
public func kk_range_sum(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_sum")
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

@_cdecl("__kk_range_contains")
public func kk_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_contains")
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

@_cdecl("__kk_range_endExclusive")
public func kk_range_endExclusive(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_endExclusive")
    }
    return range.last &+ 1
}

// MARK: - IntRange take/drop/average/sorted (STDLIB-RANGE-TDS)

@_cdecl("kk_range_take")
public func kk_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_take")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
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
public func kk_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_drop")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var elements: [Int] = []
    var current = range.first
    var skipped = 0
    if range.step > 0 {
        while current <= range.last {
            if skipped >= n { elements.append(current) } else { skipped += 1 }
            current &+= range.step
        }
    } else if range.step < 0 {
        while current >= range.last {
            if skipped >= n { elements.append(current) } else { skipped += 1 }
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

@_cdecl("__kk_char_range_step")
public func __kk_char_range_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
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
public func kk_char_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_take")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
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
public func kk_char_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_drop")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    var skipped = 0
    if range.step > 0 {
        var current = first
        while current <= last {
            if skipped >= n { elements.append(kk_box_char(current)) } else { skipped += 1 }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            if skipped >= n { elements.append(kk_box_char(current)) } else { skipped += 1 }
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

@_cdecl("__kk_char_range_randomOrNull")
public func __kk_char_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_randomOrNull")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("__kk_char_range_randomOrNull_random")
public func __kk_char_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_randomOrNull_random")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("__kk_char_range_random")
public func __kk_char_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_random")
    }
    return runtimeCharRangeRandom(range, randomRaw: 0, outThrown: outThrown)
}

@_cdecl("__kk_char_range_random_random")
public func __kk_char_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_random_random")
    }
    return runtimeCharRangeRandom(range, randomRaw: randomRaw, outThrown: outThrown)
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

@_cdecl("__kk_int_progression_fromClosedRange")
public func __kk_int_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("__kk_long_progression_fromClosedRange")
public func __kk_long_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // For LongProgression, we use the same RuntimeRangeBox but treat values as Long
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("__kk_uint_progression_fromClosedRange")
public func __kk_uint_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // UIntProgression uses signed Int for step, UInt for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("__kk_ulong_progression_fromClosedRange")
public func __kk_ulong_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // ULongProgression uses signed Int for step, ULong for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(first: rangeStart, last: alignedLast, step: step))
}

@_cdecl("__kk_char_progression_fromClosedRange")
public func __kk_char_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
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
    resolveRuntimeHandle(rawValue, as: RuntimeRangeIteratorBox.self)
}

private func runtimeSignedRangeForInIteratorBox(from rawValue: Int) -> RuntimeSignedRangeForInIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSignedRangeForInIteratorBox.self)
}

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}
