import Foundation

/// `Sequence.scan` / `runningFold` / `runningReduce` / `foldIndexed` /
/// `runningFoldIndexed` / `scanIndexed` / `reduceIndexed` /
/// `reduceIndexedOrNull` runtime entry points (STDLIB-558..560,
/// STDLIB-556/557, STDLIB-SEQ-015..017).
///
/// Split out from `RuntimeSequence.swift`.

// MARK: - Sequence scan / runningFold / runningReduce (STDLIB-558, STDLIB-559, STDLIB-560)

@_cdecl("kk_sequence_scan")
public func kk_sequence_scan(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = maybeUnbox(initial)
    var results: [Int] = [acc]
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let nextAcc = lambda(closureRaw, acc, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        results.append(acc)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

@_cdecl("kk_sequence_runningFold")
public func kk_sequence_runningFold(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_sequence_scan(seqRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_sequence_runningReduce")
public func kk_sequence_runningReduce(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var hasAccumulator = false
    var acc = 0
    var results: [Int] = []
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            results.append(acc)
            return true
        }
        var thrown = 0
        let nextAcc = lambda(closureRaw, acc, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        results.append(acc)
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// MARK: - Sequence foldIndexed / runningFoldIndexed / scanIndexed / reduceIndexed / reduceIndexedOrNull
// MARK: - (STDLIB-556, STDLIB-557, STDLIB-SEQ-015, STDLIB-SEQ-016, STDLIB-SEQ-017)

@_cdecl("kk_sequence_runningReduceIndexed")
public func kk_sequence_runningReduceIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    var results: [Int] = []
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            results.append(acc)
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: acc,
            arg3: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        results.append(acc)
        index += 1
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_sequence_foldIndexed")
public func kk_sequence_foldIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    var index = 0
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr, closureRaw: closureRaw,
            arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return initial }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return initial
    }
    return acc
}

@_cdecl("kk_sequence_runningFoldIndexed")
public func kk_sequence_runningFoldIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_sequence_scanIndexed(seqRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_sequence_scanIndexed")
public func kk_sequence_scanIndexed(
    _ seqRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = maybeUnbox(initial)
    var index = 0
    var results: [Int] = [acc]
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr, closureRaw: closureRaw,
            arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        results.append(acc)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

@_cdecl("kk_sequence_reduceIndexed")
public func kk_sequence_reduceIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr, closureRaw: closureRaw,
            arg1: index, arg2: acc, arg3: elem, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

@_cdecl("kk_sequence_reduceIndexedOrNull")
public func kk_sequence_reduceIndexedOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            index += 1
            return true
        }
        var thrown = 0
        let nextAcc = runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: acc,
            arg3: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        acc = maybeUnbox(nextAcc)
        index += 1
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        return runtimeNullSentinelInt
    }
    return acc
}
