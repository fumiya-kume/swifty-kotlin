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
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw) else { return 0 }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let pairBox = tryCast(ptr, to: RuntimePairBox.self) else { return 0 }
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

/// Trampoline for thenBy.
@_cdecl("kk_comparator_then_by_trampoline")
public func kk_comparator_then_by_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw) else { return 0 }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let outerBox = tryCast(ptr, to: RuntimePairBox.self) else { return 0 }
    guard let ptr1 = UnsafeMutableRawPointer(bitPattern: outerBox.first),
          let ptr2 = UnsafeMutableRawPointer(bitPattern: outerBox.second),
          let inner1 = tryCast(ptr1, to: RuntimePairBox.self),
          let inner2 = tryCast(ptr2, to: RuntimePairBox.self)
    else { return 0 }
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

@_cdecl("kk_comparator_then_by_descending_trampoline")
public func kk_comparator_then_by_descending_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let result = kk_comparator_then_by_trampoline(closureRaw, a, b, outThrown)
    if outThrown?.pointee != 0 { return 0 }
    return result == 0 ? 0 : -result
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
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw) else { return 0 }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let pairBox = tryCast(ptr, to: RuntimePairBox.self) else { return 0 }
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
