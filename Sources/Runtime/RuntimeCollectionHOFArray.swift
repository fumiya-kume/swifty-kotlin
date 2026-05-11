import Foundation

/// Array higher-order functions (STDLIB-088) and Array `binarySearch`
/// with comparator (STDLIB-COL-BSEARCH-004).
///
/// Split out from `RuntimeCollectionHOF.swift`.

// MARK: - Array higher-order functions (STDLIB-088)

@_cdecl("kk_array_map")
public func kk_array_map(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var mapped: [Int] = []
    mapped.reserveCapacity(array.elements.count)
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_array_filter")
public func kk_array_filter(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var filtered: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_forEach")
public func kk_array_forEach(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    for elem in array.elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_array_any")
public func kk_array_any(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    // Zero-arg overload: any() returns true if array is non-empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 0 : 1) }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return kk_box_bool(1) }
    }
    return kk_box_bool(0)
}

@_cdecl("kk_array_none")
public func kk_array_none(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    // Zero-arg overload: none() returns true if array is empty
    if fnPtr == 0 { return kk_box_bool(array.elements.isEmpty ? 1 : 0) }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

// MARK: - Array binarySearch with comparator (STDLIB-COL-BSEARCH-004)

@_cdecl("kk_array_binarySearch_compare")
public func kk_array_binarySearch_compare(
    _ arrayRaw: Int,
    _ element: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ fromIndex: Int,
    _ toIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    let size = array.elements.count
    let from = max(0, min(fromIndex, size))
    let to = max(from, min(toIndex, size))
    var low = from
    var high = to - 1
    while low <= high {
        let mid = low + (high - low) / 2
        var thrown = 0
        let cmp = comparatorInvoke(array.elements[mid], element, &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if cmp < 0 {
            low = mid + 1
        } else if cmp > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@_cdecl("kk_array_sortedArrayWith")
public func kk_array_sortedArrayWith(
    _ arrayRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var hadThrow = false
    var indexed = array.elements.enumerated().map { ($0.offset, $0.element) }
    indexed.sort { lhs, rhs in
        guard !hadThrow else { return false }
        var thrown = 0
        let result = comparatorInvoke(lhs.1, rhs.1, &thrown)
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            hadThrow = true
            return false
        }
        if result != 0 { return result < 0 }
        return lhs.0 < rhs.0
    }
    if hadThrow {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }

    let box = RuntimeArrayBox(length: indexed.count)
    for (index, pair) in indexed.enumerated() {
        box.elements[index] = pair.1
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_mapIndexed")
public func kk_array_mapIndexed(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var mapped: [Int] = []
    mapped.reserveCapacity(array.elements.count)
    for (index, elem) in array.elements.enumerated() {
        var thrown = 0
        let indexedValue = runtimeIndexedValueNew(index: index, value: elem)
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: indexedValue, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_array_mapNotNull")
public func kk_array_mapNotNull(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var mapped: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let normalized = runtimeMapNotNullResultValue(result) {
            mapped.append(normalized)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_array_flatMap")
public func kk_array_flatMap(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var result: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let subListRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_array_filterIndexed")
public func kk_array_filterIndexed(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var filtered: [Int] = []
    for (index, elem) in array.elements.enumerated() {
        var thrown = 0
        let indexedValue = runtimeIndexedValueNew(index: index, value: elem)
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: indexedValue, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_filterNot")
public func kk_array_filterNot(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    var filtered: [Int] = []
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_filterNotNull")
public func kk_array_filterNotNull(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    let filtered = array.elements.filter { maybeUnbox($0) != runtimeNullSentinelInt }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_array_reduce")
public func kk_array_reduce(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    guard !array.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Empty collection can't be reduced."), outThrown)
    }
    var acc = maybeUnbox(array.elements[0])
    for idx in 1 ..< array.elements.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: array.elements[idx], outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_array_reduceIndexed")
public func kk_array_reduceIndexed(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    guard !array.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Empty collection can't be reduced."), outThrown)
    }
    var acc = maybeUnbox(array.elements[0])
    for idx in 1 ..< array.elements.count {
        var thrown = 0
        let indexedValue = runtimeIndexedValueNew(index: idx, value: array.elements[idx])
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: indexedValue, outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_array_reduceOrNull")
public func kk_array_reduceOrNull(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    guard !array.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var acc = maybeUnbox(array.elements[0])
    for idx in 1 ..< array.elements.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: array.elements[idx], outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_array_fold")
public func kk_array_fold(
    _ arrayRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    var acc = initial
    for elem in array.elements {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: elem, outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_array_foldIndexed")
public func kk_array_foldIndexed(
    _ arrayRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    var acc = initial
    for (index, elem) in array.elements.enumerated() {
        var thrown = 0
        let indexedValue = runtimeIndexedValueNew(index: index, value: elem)
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: acc, rhs: indexedValue, outThrown: &thrown))
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return acc
}

@_cdecl("kk_array_find")
public func kk_array_find(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_array_findLast")
public func kk_array_findLast(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    for elem in array.elements.reversed() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_array_first")
public func kk_array_first(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    guard !array.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return array.elements[0]
    }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection contains no element matching the predicate."), outThrown)
}

@_cdecl("kk_array_firstOrNull")
public func kk_array_firstOrNull(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    guard !array.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    if fnPtr == 0 {
        return array.elements[0]
    }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_array_last")
public func kk_array_last(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        invalidContainerPanic(#function, "array")
    }
    guard !array.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return array.elements[array.elements.count - 1]
    }
    for elem in array.elements.reversed() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "Collection contains no element matching the predicate."), outThrown)
}

@_cdecl("kk_array_lastOrNull")
public func kk_array_lastOrNull(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    guard !array.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    if fnPtr == 0 {
        return array.elements[array.elements.count - 1]
    }
    for elem in array.elements.reversed() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_array_all")
public func kk_array_all(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_array_count")
public func kk_array_count(_ arrayRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else { invalidContainerPanic(#function, "array") }
    if fnPtr == 0 {
        return array.elements.count
    }
    var count = 0
    for elem in array.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

