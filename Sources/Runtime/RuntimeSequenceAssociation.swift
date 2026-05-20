import Foundation

/// `Sequence.joinTo` / `joinToString` / `sumOf` / `associate` /
/// `associateBy` / `associateWith` plus their `*To` destination-map
/// variants (STDLIB-275, STDLIB-SEQ-023).
///
/// Split out from `RuntimeSequence.swift`.

// MARK: - Sequence Terminal Operations: joinToString/sumOf/associate/associateBy (STDLIB-275)

@_cdecl("kk_sequence_joinTo")
public func kk_sequence_joinTo(
    _ seqRaw: Int,
    _ destinationRaw: Int,
    _ separatorRaw: Int,
    _ prefixRaw: Int,
    _ postfixRaw: Int
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let rendered = elements.map(runtimeElementToString).joined(separator: separator)
    let stringValue = prefix + rendered + postfix
    let utf8 = Array(stringValue.utf8)
    let stringRaw = Int(bitPattern: utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    })
    return kk_string_builder_append_obj(destinationRaw, stringRaw)
}

@_cdecl("kk_sequence_joinToString")
public func kk_sequence_joinToString(_ seqRaw: Int, _ separatorRaw: Int, _ prefixRaw: Int, _ postfixRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""
    let joined = elements.map(runtimeElementToString).joined(separator: separator)
    let stringValue = prefix + joined + postfix
    let utf8 = Array(stringValue.utf8)
    return Int(bitPattern: utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    })
}

@_cdecl("kk_sequence_sumOf")
public func kk_sequence_sumOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var total = 0
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        total += maybeUnbox(result)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return total
}

@_cdecl("kk_sequence_sumBy")
public func kk_sequence_sumBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_sequence_sumOf(seqRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_sequence_sumByDouble")
public func kk_sequence_sumByDouble(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var total = 0.0
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        total += kk_bits_to_double(result)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return kk_double_to_bits(0.0) }
    return kk_double_to_bits(total)
}



@_cdecl("kk_sequence_associate")
public func kk_sequence_associate(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let pair = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        keys.append(kk_pair_first(pair))
        values.append(kk_pair_second(pair))
        return true
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_sequence_associateBy")
public func kk_sequence_associateBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        keys.append(maybeUnbox(key))
        values.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_sequence_partition")
public func kk_sequence_partition(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matching: [Int] = []
    var nonMatching: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let result = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if maybeUnbox(result) != 0 {
            matching.append(elem)
        } else {
            nonMatching.append(elem)
        }
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    let matchingList = registerRuntimeObject(RuntimeListBox(elements: matching))
    let nonMatchingList = registerRuntimeObject(RuntimeListBox(elements: nonMatching))
    return kk_pair_new(matchingList, nonMatchingList)
}

@_cdecl("kk_sequence_associateWith")
public func kk_sequence_associateWith(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        var thrown = 0
        let value = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        keys.append(elem)
        values.append(maybeUnbox(value))
        return true
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

// MARK: - Sequence destination map operations (STDLIB-SEQ-023)

private func runtimeSequenceAssociateToMap(
    seqRaw: Int,
    destRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: StaticString,
    entry: @escaping (_ elem: Int, _ transformed: Int) -> (key: Int, value: Int)
) -> Int {
    guard runtimeMapBox(from: destRaw) != nil else {
        invalidContainerPanic(caller, "map")
    }
    var didThrow = false
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: caller, outThrown: outThrown) { elem in
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        let mapped = entry(elem, transformed)
        _ = kk_mutable_map_put(destRaw, mapped.key, mapped.value)
        return true
    }
    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

@_cdecl("kk_sequence_associateTo")
public func kk_sequence_associateTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceAssociateToMap(
        seqRaw: seqRaw,
        destRaw: destRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown,
        caller: #function
    ) { _, pair in
        (kk_pair_first(pair), kk_pair_second(pair))
    }
}

@_cdecl("kk_sequence_associateByTo")
public func kk_sequence_associateByTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceAssociateToMap(
        seqRaw: seqRaw,
        destRaw: destRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown,
        caller: #function
    ) { elem, key in
        (maybeUnbox(key), elem)
    }
}

@_cdecl("kk_sequence_associateWithTo")
public func kk_sequence_associateWithTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceAssociateToMap(
        seqRaw: seqRaw,
        destRaw: destRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown,
        caller: #function
    ) { elem, value in
        (elem, maybeUnbox(value))
    }
}

@_cdecl("kk_sequence_groupByTo")
public func kk_sequence_groupByTo(
    _ seqRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex: [RuntimeElementKey: Int] = [:]
    var cachedLists: [Int: RuntimeListBox] = [:]
    for (index, key) in dest.keys.enumerated() {
        keyIndex[RuntimeElementKey(value: key)] = index
        if index < dest.values.count, let existingList = runtimeListBox(from: dest.values[index]) {
            cachedLists[index] = existingList
        }
    }

    var traversalState: SequenceTraversalState?
    var didThrow = false
    let visit: (Int) -> Bool = { elem in
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        let normalizedKey = RuntimeElementKey(value: maybeUnbox(key))
        if let index = keyIndex[normalizedKey] {
            if let existingList = cachedLists[index] {
                existingList.elements.append(elem)
            } else {
                guard index < dest.values.count,
                      let existingList = runtimeListBox(from: dest.values[index])
                else {
                    invalidContainerPanic(#function, "MutableList")
                }
                cachedLists[index] = existingList
                existingList.elements.append(elem)
            }
        } else {
            let newIndex = dest.keys.count
            let newList = RuntimeListBox(elements: [elem])
            dest.keys.append(normalizedKey.value)
            dest.values.append(registerRuntimeObject(newList))
            keyIndex[normalizedKey] = newIndex
            cachedLists[newIndex] = newList
        }
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        let state = SequenceTraversalState()
        traversalState = state
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if !visit(elem) { break }
        }
    }

    if didThrow {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    return destRaw
}

private func runtimeSequenceBestValue(
    seqRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: StaticString,
    comparisonSign: Int,
    returnElement: Bool,
    throwOnEmpty: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var bestElement: Int?
    var bestSelector: Int?
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: caller, outThrown: outThrown) { elem in
        var thrown = 0
        let selector = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        let normalizedSelector = maybeUnbox(selector)
        if let current = bestSelector {
            let comparison = runtimeCompareValues(normalizedSelector, current)
            if (comparisonSign < 0 && comparison < 0) || (comparisonSign > 0 && comparison > 0) {
                bestSelector = normalizedSelector
                bestElement = elem
            }
        } else {
            bestSelector = normalizedSelector
            bestElement = elem
        }
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return runtimeNullSentinelInt
    }
    if returnElement {
        guard let bestElement else {
            if throwOnEmpty {
                outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
            }
            return runtimeNullSentinelInt
        }
        return bestElement
    }
    guard let bestSelector else {
        if throwOnEmpty {
            outThrown?.pointee = runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement)
        }
        return runtimeNullSentinelInt
    }
    return bestSelector
}

private func runtimeSequenceExtremumWith(
    seqRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: StaticString,
    comparisonSign: Int,
    throwOnEmpty: Bool
) -> Int {
    var bestElement: Int?
    var didThrow = false
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: caller, outThrown: outThrown) { elem in
        guard let current = bestElement else {
            bestElement = elem
            return true
        }
        var thrown = 0
        let comparison = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: elem,
            rhs: current,
            outThrown: &thrown
        )
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            didThrow = true
            return false
        }
        if (comparisonSign < 0 && comparison < 0) || (comparisonSign > 0 && comparison > 0) {
            bestElement = elem
        }
        return true
    }
    if didThrow || (outThrown?.pointee ?? 0) != 0 {
        return runtimeExceptionCaughtSentinel
    }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    guard let bestElement else {
        if throwOnEmpty {
            return handleCollectionLambdaThrow(
                runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement),
                outThrown
            )
        }
        return runtimeNullSentinelInt
    }
    return bestElement
}

@_cdecl("kk_sequence_maxWithOrNull")
public func kk_sequence_maxWithOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceExtremumWith(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: 1, throwOnEmpty: false
    )
}

@_cdecl("kk_sequence_maxBy")
public func kk_sequence_maxBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
        runtimeSequenceBestValue(
            seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
            caller: #function, comparisonSign: 1, returnElement: true, throwOnEmpty: true
        )
    )
}

private func runtimeSequenceExtremumWith(
    seqRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: StaticString,
    comparisonSign: Int
) -> Int {
    let compare = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var bestElement: Int?
    var didThrow = false
    let traversalState = runtimeTraverseSequenceSource(seqRaw, caller: caller, outThrown: outThrown) { elem in
        if let current = bestElement {
            var thrown = 0
            let comparison = compare(elem, current, &thrown)
            if thrown != 0 {
                _ = handleCollectionLambdaThrow(thrown, outThrown)
                didThrow = true
                return false
            }
            if (comparisonSign < 0 && comparison < 0) || (comparisonSign > 0 && comparison > 0) {
                bestElement = elem
            }
        } else {
            bestElement = elem
        }
        return true
    }
    if didThrow { return runtimeExceptionCaughtSentinel }
    if let outThrown, outThrown.pointee != 0 { return runtimeExceptionCaughtSentinel }
    if let traversalState, traversalState.limitReached {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached),
            outThrown
        )
    }
    guard let bestElement else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: kEmptySequenceNoSuchElement), outThrown)
    }
    return bestElement
}

@_cdecl("kk_sequence_minWith")
public func kk_sequence_minWith(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceExtremumWith(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: -1
    )
}

@_cdecl("kk_sequence_minByOrNull")
public func kk_sequence_minByOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: -1, returnElement: true, throwOnEmpty: false
    )
}

@_cdecl("kk_sequence_maxByOrNull")
public func kk_sequence_maxByOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: 1, returnElement: true, throwOnEmpty: false
    )
}

@_cdecl("kk_sequence_minWith")
public func kk_sequence_minWith(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceExtremumWith(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: -1
    )
}

@_cdecl("kk_sequence_minOf")
public func kk_sequence_minOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: -1, returnElement: false, throwOnEmpty: true
    )
}

@_cdecl("kk_sequence_minOfOrNull")
public func kk_sequence_minOfOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: -1, returnElement: false, throwOnEmpty: false
    )
}

@_cdecl("kk_sequence_maxOf")
public func kk_sequence_maxOf(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: 1, returnElement: false, throwOnEmpty: true
    )
}

@_cdecl("kk_sequence_maxOfOrNull")
public func kk_sequence_maxOfOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSequenceBestValue(
        seqRaw: seqRaw, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown,
        caller: #function, comparisonSign: 1, returnElement: false, throwOnEmpty: false
    )
}
