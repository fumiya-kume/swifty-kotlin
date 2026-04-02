import Foundation

// MARK: - Comparator from selector (STDLIB-175)

/// Creates a comparator closure from a selector. Returns closure_raw to be paired with
/// kk_comparator_from_selector_trampoline (ascending) or kk_comparator_from_selector_descending_trampoline.
@_cdecl("kk_comparator_from_selector")
public func kk_comparator_from_selector(_ selectorFn: Int, _ selectorClosure: Int) -> Int {
    let box = RuntimePairBox(first: selectorFn, second: selectorClosure)
    return registerRuntimeObject(box)
}

/// Trampoline: (closure_raw, a, b, outThrown) -> Int. Used with closure from kk_comparator_from_selector.
@_cdecl("kk_comparator_from_selector_trampoline")
public func kk_comparator_from_selector_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    let selectorFn = pairBox.first
    let selectorClosure = pairBox.second
    var thrown = 0
    let keyA = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: a, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    let keyB = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: b, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return runtimeCompareValues(keyA, keyB)
}

/// Trampoline for compareByDescending: negates the comparison result.
@_cdecl("kk_comparator_from_selector_descending_trampoline")
public func kk_comparator_from_selector_descending_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let result = kk_comparator_from_selector_trampoline(closureRaw, a, b, outThrown)
    if outThrown?.pointee != 0 { return 0 }
    return result == 0 ? 0 : -result
}

@_cdecl("kk_comparator_from_selector_descending")
public func kk_comparator_from_selector_descending(_ selectorFn: Int, _ selectorClosure: Int) -> Int {
    kk_comparator_from_selector(selectorFn, selectorClosure)
}

// MARK: - Multi-selector compareBy (STDLIB-613)

/// Creates a comparator closure from multiple selectors.
/// Stores the (fn, closure) pairs in a RuntimeListBox for the trampoline to iterate.
@_cdecl("kk_comparator_from_multi_selectors")
public func kk_comparator_from_multi_selectors(
    _ sel1Fn: Int, _ sel1Closure: Int,
    _ sel2Fn: Int, _ sel2Closure: Int
) -> Int {
    let box = RuntimeListBox(elements: [sel1Fn, sel1Closure, sel2Fn, sel2Closure])
    return registerRuntimeObject(box)
}

/// 3-selector variant.
@_cdecl("kk_comparator_from_multi_selectors3")
public func kk_comparator_from_multi_selectors3(
    _ sel1Fn: Int, _ sel1Closure: Int,
    _ sel2Fn: Int, _ sel2Closure: Int,
    _ sel3Fn: Int, _ sel3Closure: Int
) -> Int {
    let box = RuntimeListBox(elements: [sel1Fn, sel1Closure, sel2Fn, sel2Closure, sel3Fn, sel3Closure])
    return registerRuntimeObject(box)
}

/// Trampoline for multi-selector compareBy.
@_cdecl("kk_comparator_from_multi_selectors_trampoline")
public func kk_comparator_from_multi_selectors_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let listBox = tryCast(ptr, to: RuntimeListBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    let elements = listBox.elements
    // Elements are packed as [fn1, closure1, fn2, closure2, ...]
    guard elements.count % 2 == 0, elements.count >= 4 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: malformed multi-selector comparator: expected even element count >= 4, got \(elements.count)")
    }
    let selectorCount = elements.count / 2
    var thrown = 0
    for i in 0..<selectorCount {
        let selectorFn = elements[i * 2]
        let selectorClosure = elements[i * 2 + 1]
        let keyA = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: a, outThrown: &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let keyB = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: b, outThrown: &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let cmp = runtimeCompareValues(keyA, keyB)
        if cmp != 0 { return cmp }
    }
    return 0
}

// MARK: - Chained comparators (STDLIB-176)

/// thenBy: first comparator, then selector for tie-breaker.
@_cdecl("kk_comparator_then_by")
public func kk_comparator_then_by(
    _ c1Fn: Int,
    _ c1Closure: Int,
    _ selectorFn: Int,
    _ selectorClosure: Int
) -> Int {
    // Store [c1Fn, c1Closure, selectorFn, selectorClosure] - need 4 words. Use two pairs or a custom box.
    // Use RuntimeTripleBox? No - we need 4 ints. Let me check RuntimeTripleBox - it has 3. We need 4.
    // Create a simple box for 4 ints or use a different approach.
    // Alternative: use a pair of pairs. pair1 = (c1Fn, c1Closure), pair2 = (selectorFn, selectorClosure)
    // Then we need a box holding (pair1_raw, pair2_raw). So we'd have pair((c1Fn,c1Closure), (selectorFn, selectorClosure)).
    let inner1 = RuntimePairBox(first: c1Fn, second: c1Closure)
    let inner2 = RuntimePairBox(first: selectorFn, second: selectorClosure)
    let outer = RuntimePairBox(first: registerRuntimeObject(inner1), second: registerRuntimeObject(inner2))
    return registerRuntimeObject(outer)
}

@_cdecl("kk_comparator_then_by_descending")
public func kk_comparator_then_by_descending(
    _ c1Fn: Int,
    _ c1Closure: Int,
    _ selectorFn: Int,
    _ selectorClosure: Int
) -> Int {
    kk_comparator_then_by(c1Fn, c1Closure, selectorFn, selectorClosure)
}

/// thenDescending: first comparator, then comparator for tie-breaker.
@_cdecl("kk_comparator_then_descending")
public func kk_comparator_then_descending(
    _ c1Fn: Int,
    _ c1Closure: Int,
    _ comparatorFn: Int,
    _ comparatorClosure: Int
) -> Int {
    let inner1 = RuntimePairBox(first: c1Fn, second: c1Closure)
    let inner2 = RuntimePairBox(first: comparatorFn, second: comparatorClosure)
    let outer = RuntimePairBox(first: registerRuntimeObject(inner1), second: registerRuntimeObject(inner2))
    return registerRuntimeObject(outer)
}

/// thenComparator: first comparator, then comparator for tie-breaker.
@_cdecl("kk_comparator_then_comparator")
public func kk_comparator_then_comparator(
    _ c1Fn: Int,
    _ c1Closure: Int,
    _ comparatorFn: Int,
    _ comparatorClosure: Int
) -> Int {
    let inner1 = RuntimePairBox(first: c1Fn, second: c1Closure)
    let inner2 = RuntimePairBox(first: comparatorFn, second: comparatorClosure)
    let outer = RuntimePairBox(first: registerRuntimeObject(inner1), second: registerRuntimeObject(inner2))
    return registerRuntimeObject(outer)
}

/// Trampoline for thenBy.
@_cdecl("kk_comparator_then_by_trampoline")
public func kk_comparator_then_by_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let outerBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    guard let ptr1 = UnsafeMutableRawPointer(bitPattern: outerBox.first),
          let ptr2 = UnsafeMutableRawPointer(bitPattern: outerBox.second),
          let inner1 = tryCast(ptr1, to: RuntimePairBox.self),
          let inner2 = tryCast(ptr2, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null inner comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator inner closure")
        return 0
    }
    var thrown = 0
    let r1 = runtimeInvokeCollectionLambda2(fnPtr: inner1.first, closureRaw: inner1.second, lhs: a, rhs: b, outThrown: &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    if r1 != 0 { return r1 }
    let keyA = runtimeInvokeCollectionLambda1(fnPtr: inner2.first, closureRaw: inner2.second, value: a, outThrown: &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB = runtimeInvokeCollectionLambda1(fnPtr: inner2.first, closureRaw: inner2.second, value: b, outThrown: &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return runtimeCompareValues(keyA, keyB)
}

/// Trampoline for thenComparator.
@_cdecl("kk_comparator_then_comparator_trampoline")
public func kk_comparator_then_comparator_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let outerBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    guard let ptr1 = UnsafeMutableRawPointer(bitPattern: outerBox.first),
          let ptr2 = UnsafeMutableRawPointer(bitPattern: outerBox.second),
          let inner1 = tryCast(ptr1, to: RuntimePairBox.self),
          let inner2 = tryCast(ptr2, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null inner comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator inner closure")
        return 0
    }
    var thrown = 0
    let r1 = runtimeInvokeCollectionLambda2(
        fnPtr: inner1.first,
        closureRaw: inner1.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    if r1 != 0 { return r1 }
    let r2 = runtimeInvokeCollectionLambda2(
        fnPtr: inner2.first,
        closureRaw: inner2.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return r2
}

/// Trampoline for thenByDescending: reverse only the tie-breaker result.
@_cdecl("kk_comparator_then_by_descending_trampoline")
public func kk_comparator_then_by_descending_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let outerBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    guard let ptr1 = UnsafeMutableRawPointer(bitPattern: outerBox.first),
          let ptr2 = UnsafeMutableRawPointer(bitPattern: outerBox.second),
          let inner1 = tryCast(ptr1, to: RuntimePairBox.self),
          let inner2 = tryCast(ptr2, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null inner comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator inner closure")
        return 0
    }
    var thrown = 0
    let r1 = runtimeInvokeCollectionLambda2(
        fnPtr: inner1.first,
        closureRaw: inner1.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    if r1 != 0 { return r1 }
    let keyA = runtimeInvokeCollectionLambda1(
        fnPtr: inner2.first,
        closureRaw: inner2.second,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB = runtimeInvokeCollectionLambda1(
        fnPtr: inner2.first,
        closureRaw: inner2.second,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let r2 = runtimeCompareValues(keyA, keyB)
    return r2 == 0 ? 0 : -r2
}

/// Trampoline for thenDescending: reverse only the tie-breaker result.
@_cdecl("kk_comparator_then_descending_trampoline")
public func kk_comparator_then_descending_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let outerBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    guard let ptr1 = UnsafeMutableRawPointer(bitPattern: outerBox.first),
          let ptr2 = UnsafeMutableRawPointer(bitPattern: outerBox.second),
          let inner1 = tryCast(ptr1, to: RuntimePairBox.self),
          let inner2 = tryCast(ptr2, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null inner comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator inner closure")
        return 0
    }
    var thrown = 0
    let r1 = runtimeInvokeCollectionLambda2(
        fnPtr: inner1.first,
        closureRaw: inner1.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    if r1 != 0 { return r1 }
    let r2 = runtimeInvokeCollectionLambda2(
        fnPtr: inner2.first,
        closureRaw: inner2.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return r2 == 0 ? 0 : -r2
}

@_cdecl("kk_comparator_nulls_first")
public func kk_comparator_nulls_first(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    return registerRuntimeObject(pair)
}

@_cdecl("kk_comparator_nulls_last")
public func kk_comparator_nulls_last(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    return registerRuntimeObject(pair)
}

@inline(__always)
private func runtimeCompareNullableOrder(
    a: Int,
    b: Int,
    nullsFirst: Bool
) -> Int? {
    let aIsNull = (a == runtimeNullSentinelInt || a == 0)
    let bIsNull = (b == runtimeNullSentinelInt || b == 0)
    if aIsNull && bIsNull { return 0 }
    if aIsNull { return nullsFirst ? -1 : 1 }
    if bIsNull { return nullsFirst ? 1 : -1 }
    return nil
}

@_cdecl("kk_comparator_nulls_first_trampoline")
public func kk_comparator_nulls_first_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    if let nullableResult = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: true) {
        return nullableResult
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda2(
        fnPtr: pairBox.first,
        closureRaw: pairBox.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

@_cdecl("kk_comparator_nulls_last_trampoline")
public func kk_comparator_nulls_last_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    if let nullableResult = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: false) {
        return nullableResult
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda2(
        fnPtr: pairBox.first,
        closureRaw: pairBox.second,
        lhs: a,
        rhs: b,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

/// reversed: wraps a comparator and negates its result.
@_cdecl("kk_comparator_reversed")
public func kk_comparator_reversed(_ cFn: Int, _ cClosure: Int) -> Int {
    let box = RuntimePairBox(first: cFn, second: cClosure)
    return registerRuntimeObject(box)
}

@_cdecl("kk_comparator_reversed_trampoline")
public func kk_comparator_reversed_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        // Return 0 instead of panic for invalid/null comparator closure
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda2(fnPtr: pairBox.first, closureRaw: pairBox.second, lhs: a, rhs: b, outThrown: &thrown)
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return result == 0 ? 0 : -result
}

// MARK: - naturalOrder / reverseOrder (STDLIB-177)

@_cdecl("kk_comparator_natural_order_trampoline")
public func kk_comparator_natural_order_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = outThrown
    _ = closureRaw
    return runtimeCompareValues(a, b)
}

@_cdecl("kk_comparator_reverse_order_trampoline")
public func kk_comparator_reverse_order_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = outThrown
    _ = closureRaw
    return -runtimeCompareValues(a, b)
}

/// naturalOrder() returns closure=0; use with kk_comparator_natural_order_trampoline.
@_cdecl("kk_comparator_natural_order")
public func kk_comparator_natural_order() -> Int {
    0
}

/// reverseOrder() returns closure=0; use with kk_comparator_reverse_order_trampoline.
@_cdecl("kk_comparator_reverse_order")
public func kk_comparator_reverse_order() -> Int {
    0
}

// MARK: - compareValues / compareValuesBy

/// Internal helper for nullable value comparison. Nulls are less than non-nulls.
func runtimeCompareNullableValues(_ a: Int, _ b: Int) -> Int {
    let aIsNull = (a == runtimeNullSentinelInt || a == 0)
    let bIsNull = (b == runtimeNullSentinelInt || b == 0)
    if aIsNull && bIsNull { return 0 }
    if aIsNull { return -1 }
    if bIsNull { return 1 }
    return runtimeCompareValues(a, b)
}

/// compareValues(a: T?, b: T?): Int — nulls are less than non-nulls.
/// Codegen emits: kk_compareValues(a, b, outThrown). outThrown is unused but present for ABI.
@_cdecl("kk_compareValues")
public func kk_compareValues(_ a: Int, _ b: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    return kk_box_int(runtimeCompareNullableValues(a, b))
}

@inline(__always)
private func runtimeInvokeCompareValuesSelector(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: value, outThrown: outThrown)
}

/// compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int — single selector.
/// Codegen emits: kk_compareValuesBy1(a, b, selectorFnPtr, selectorClosureRaw, outThrown).
@_cdecl("kk_compareValuesBy1")
public func kk_compareValuesBy1(
    _ a: Int,
    _ b: Int,
    _ selectorFn: Int,
    _ selectorClosure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA, keyB))
}

/// compareValuesBy(a: T, b: T, selector1, selector2): Int — 2-selector variant.
/// Codegen emits:
/// kk_compareValuesBy(a, b, sel1FnPtr, sel1ClosureRaw, sel2FnPtr, sel2ClosureRaw, outThrown).
@_cdecl("kk_compareValuesBy")
public func kk_compareValuesBy(
    _ a: Int,
    _ b: Int,
    _ sel1Fn: Int,
    _ sel1Closure: Int,
    _ sel2Fn: Int,
    _ sel2Closure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp1 = runtimeCompareNullableValues(keyA1, keyB1)
    if cmp1 != 0 { return kk_box_int(cmp1) }

    let keyA2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA2, keyB2))
}

/// compareValuesBy(a: T, b: T, selector1, selector2, selector3): Int — 3-selector variant.
/// Codegen emits:
/// kk_compareValuesBy3(a, b, sel1FnPtr, sel1ClosureRaw, sel2FnPtr, sel2ClosureRaw,
/// sel3FnPtr, sel3ClosureRaw, outThrown).
@_cdecl("kk_compareValuesBy3")
public func kk_compareValuesBy3(
    _ a: Int,
    _ b: Int,
    _ sel1Fn: Int,
    _ sel1Closure: Int,
    _ sel2Fn: Int,
    _ sel2Closure: Int,
    _ sel3Fn: Int,
    _ sel3Closure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp1 = runtimeCompareNullableValues(keyA1, keyB1)
    if cmp1 != 0 { return kk_box_int(cmp1) }

    let keyA2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp2 = runtimeCompareNullableValues(keyA2, keyB2)
    if cmp2 != 0 { return kk_box_int(cmp2) }

    let keyA3 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel3Fn,
        closureRaw: sel3Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB3 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel3Fn,
        closureRaw: sel3Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA3, keyB3))
}
