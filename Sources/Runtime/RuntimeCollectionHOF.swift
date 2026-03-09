import Foundation

@_cdecl("kk_list_map")
public func kk_list_map(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_filter")
public func kk_list_filter(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if maybeUnbox(result) != 0 { filtered.append(elem) }
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_mapNotNull")
public func kk_list_mapNotNull(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeListBox(elements: []))
        }
        let normalized = maybeUnbox(result)
        if normalized != runtimeNullSentinelInt {
            mapped.append(normalized)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_filterNotNull")
public func kk_list_filterNotNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let filtered = list.elements.filter { maybeUnbox($0) != runtimeNullSentinelInt }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

@_cdecl("kk_list_forEach")
public func kk_list_forEach(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        _ = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return 0
}

@_cdecl("kk_list_flatMap")
public func kk_list_flatMap(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let subListRaw = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return registerRuntimeObject(RuntimeListBox(elements: [])) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_any")
public func kk_list_any(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return kk_box_bool(0) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return kk_box_bool(0) }
        if maybeUnbox(result) != 0 { return kk_box_bool(1) }
    }
    return kk_box_bool(0)
}

@_cdecl("kk_list_none")
public func kk_list_none(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return kk_box_bool(1) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return kk_box_bool(0) }
        if maybeUnbox(result) != 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_list_all")
public func kk_list_all(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return kk_box_bool(1) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return kk_box_bool(0) }
        if maybeUnbox(result) == 0 { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_list_fold")
public func kk_list_fold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return initial }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = initial
    for elem in list.elements {
        var thrown = 0
        acc = maybeUnbox(lambda(acc, elem, &thrown))
        if thrown != 0 { outThrown?.pointee = thrown; return initial }
    }
    return acc
}

@_cdecl("kk_list_reduce")
public func kk_list_reduce(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw), !list.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var acc = list.elements[0]
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        acc = maybeUnbox(lambda(acc, list.elements[idx], &thrown))
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    }
    return acc
}

@_cdecl("kk_list_groupBy")
public func kk_list_groupBy(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [Int: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        let unboxedKey = maybeUnbox(key)
        if let grpIdx = keyToIndex[unboxedKey] {
            groupElements[grpIdx].append(elem)
        } else {
            let newIndex = groupKeys.count
            keyToIndex[unboxedKey] = newIndex
            groupKeys.append(unboxedKey)
            groupElements.append([elem])
        }
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}

@_cdecl("kk_list_sortedBy")
public func kk_list_sortedBy(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var elems: [Int] = []
    var keys: [Int] = []
    elems.reserveCapacity(list.elements.count)
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeListBox(elements: []))
        }
        elems.append(elem)
        keys.append(maybeUnbox(key))
    }
    let indices = Array(elems.indices)
    let sorted = indices.sorted { lhs, rhs in
        if keys[lhs] != keys[rhs] { return keys[lhs] < keys[rhs] }
        return lhs < rhs
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map { elems[$0] }))
}

@_cdecl("kk_list_count")
public func kk_list_count(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_list_first")
public func kk_list_first(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Collection is empty.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { return elem }
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return 0
}

@_cdecl("kk_list_last")
public func kk_list_last(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Collection is empty.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastMatch: Int?
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if maybeUnbox(result) != 0 { lastMatch = elem }
    }
    if let match = lastMatch { return match }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "Collection contains no element matching the predicate."
    )
    return 0
}

@_cdecl("kk_list_find")
public func kk_list_find(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return runtimeNullSentinelInt }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        let result = lambda(elem, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_list_associateBy")
public func kk_list_associateBy(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let key = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(maybeUnbox(key))
        values.append(elem)
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associateWith")
public func kk_list_associateWith(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let value = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(elem)
        values.append(maybeUnbox(value))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_associate")
public func kk_list_associate(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let pair = lambda(elem, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        keys.append(kk_pair_first(pair))
        values.append(kk_pair_second(pair))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_list_zip")
public func kk_list_zip(_ listRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeListBox(from: listRaw)?.elements ?? []
    let rhs = runtimeListBox(from: otherRaw)?.elements ?? []
    let count = min(lhs.count, rhs.count)
    var pairs: [Int] = []
    pairs.reserveCapacity(count)
    for index in 0 ..< count {
        pairs.append(kk_pair_new(lhs[index], rhs[index]))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_list_withIndex")
public func kk_list_withIndex(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var pairs: [Int] = []
    pairs.reserveCapacity(list.elements.count)
    for (index, element) in list.elements.enumerated() {
        pairs.append(kk_pair_new(index, element))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_list_forEachIndexed")
public func kk_list_forEachIndexed(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (index, element) in list.elements.enumerated() {
        var thrown = 0
        _ = lambda(index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

@_cdecl("kk_list_mapIndexed")
public func kk_list_mapIndexed(_ listRaw: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(list.elements.count)
    for (index, element) in list.elements.enumerated() {
        var thrown = 0
        let result = lambda(index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeListBox(elements: []))
        }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_unzip")
public func kk_list_unzip(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    var firstValues: [Int] = []
    var secondValues: [Int] = []
    firstValues.reserveCapacity(elements.count)
    secondValues.reserveCapacity(elements.count)
    for pairRaw in elements {
        firstValues.append(kk_pair_first(pairRaw))
        secondValues.append(kk_pair_second(pairRaw))
    }
    let firstList = registerRuntimeObject(RuntimeListBox(elements: firstValues))
    let secondList = registerRuntimeObject(RuntimeListBox(elements: secondValues))
    return kk_pair_new(firstList, secondList)
}

@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_reversed")
public func kk_list_reversed(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.reversed())))
}

@_cdecl("kk_list_sorted")
public func kk_list_sorted(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_distinct")
public func kk_list_distinct(_ listRaw: Int) -> Int {
    let elements = runtimeListBox(from: listRaw)?.elements ?? []
    return registerRuntimeObject(RuntimeListBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}
