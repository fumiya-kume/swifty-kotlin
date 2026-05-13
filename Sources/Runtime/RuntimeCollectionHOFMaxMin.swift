import Foundation

/// `kk_list_max{Of,With,OfWith}` / `kk_list_min{Of,With,OfWith}`
/// (and `OrNull` variants) — STDLIB-301b/c/d.
///
/// Split out from `RuntimeCollectionHOF.swift` to keep each runtime
/// source scoped to a single collection HOF concern.

private enum RuntimeCollectionExtremumDirection {
    case maximum
    case minimum

    func isBetter(_ comparison: Int) -> Bool {
        switch self {
        case .maximum:
            comparison > 0
        case .minimum:
            comparison < 0
        }
    }
}

private enum RuntimeCollectionEmptyExtremumResult {
    case throwNoSuchElement
    case nullSentinel

    func value(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        switch self {
        case .throwNoSuchElement:
            handleCollectionLambdaThrow(
                runtimeAllocateThrowable(message: "NoSuchElementException: List is empty."),
                outThrown
            )
        case .nullSentinel:
            runtimeNullSentinelInt
        }
    }
}

private func runtimeCollectionListOrPanic(_ listRaw: Int, functionName: StaticString) -> RuntimeListBox {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(functionName, "list")
    }
    return list
}

private func runtimeListExtremumOf(
    listRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: list.elements[0],
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(runtimeCompareValues(value, bestValue)) {
            bestValue = value
        }
    }
    return bestValue
}

private func runtimeListExtremumWith(
    listRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    var bestElem = list.elements[0]
    for elem in list.elements.dropFirst() {
        var thrown = 0
        let cmp = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: elem,
            rhs: bestElem,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(cmp) {
            bestElem = elem
        }
    }
    return bestElem
}

private func runtimeListExtremumOfWith(
    listRaw: Int,
    cmpFnPtr: Int,
    cmpClosureRaw: Int,
    selFnPtr: Int,
    selClosureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(
        fnPtr: selFnPtr,
        closureRaw: selClosureRaw,
        value: list.elements[0],
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(
            fnPtr: selFnPtr,
            closureRaw: selClosureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        thrown = 0
        let cmp = runtimeInvokeCollectionLambda2(
            fnPtr: cmpFnPtr,
            closureRaw: cmpClosureRaw,
            lhs: value,
            rhs: bestValue,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(cmp) {
            bestValue = value
        }
    }
    return bestValue
}

// MARK: - maxOf / minOf (non-OrNull, throws on empty) (STDLIB-301b)

@_cdecl("kk_list_maxOf")
public func kk_list_maxOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOf(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOf")
public func kk_list_minOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOf(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

// MARK: - maxWith / minWith / maxWithOrNull / minWithOrNull (comparator-based) (STDLIB-301c)

@_cdecl("kk_list_maxWithOrNull")
public func kk_list_maxWithOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxWith")
public func kk_list_maxWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minWithOrNull")
public func kk_list_minWithOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minWith")
public func kk_list_minWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

// MARK: - maxOfWith / minOfWith / maxOfWithOrNull / minOfWithOrNull (comparator + selector) (STDLIB-301d)

@_cdecl("kk_list_maxOfWithOrNull")
public func kk_list_maxOfWithOrNull(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .maximum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxOfWith")
public func kk_list_maxOfWith(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOfWithOrNull")
public func kk_list_minOfWithOrNull(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .minimum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOfWith")
public func kk_list_minOfWith(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_takeLast")
public func kk_list_takeLast(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.suffix(clamped))))
}

@_cdecl("kk_list_dropLast")
public func kk_list_dropLast(_ listRaw: Int, _ count: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropLast(clamped))))
}

@_cdecl("kk_list_sum")
public func kk_list_sum(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var total = 0
    for element in listBox.elements {
        // Lists produced by compiled Kotlin code store boxed primitives.
        total &+= maybeUnbox(element)
    }
    return total
}

@_cdecl("kk_list_average")
public func kk_list_average(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = listBox.elements
    guard !elements.isEmpty else { return kk_double_to_bits(Double.nan) }
    var sum: Double = 0.0
    for raw in elements {
        if let ptr = UnsafeMutableRawPointer(bitPattern: raw) {
            let isObj = runtimeStorage.withLock { state in
                state.objectPointers.contains(UInt(bitPattern: ptr))
            }
            if isObj {
                if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
                    sum += doubleBox.value
                    continue
                } else if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
                    sum += Double(floatBox.value)
                    continue
                } else if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
                    sum += Double(longBox.value)
                    continue
                } else if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
                    sum += Double(intBox.value)
                    continue
                }
            }
        }
        // Unboxed raw integer (plain Int list element)
        sum += Double(raw)
    }
    return kk_double_to_bits(sum / Double(elements.count))
}

@_cdecl("kk_list_reversed")
public func kk_list_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.reversed())))
}

@_cdecl("kk_list_as_reversed")
public func kk_list_as_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return registerRuntimeObject(RuntimeListBox(reversedViewOf: listBox))
}

@_cdecl("kk_list_sorted")
public func kk_list_sorted(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@inline(__always)
func runtimePrimitiveCompareKindFromRaw(_ raw: Int32) -> RuntimePrimitiveCompareKind {
    switch raw {
    case 1: return .long
    case 2: return .uint
    case 3: return .ulong
    case 4: return .boolean
    case 5: return .char
    case 6: return .float
    case 7: return .double
    default: return .int
    }
}

@inline(__always)
func runtimeSortElements(
    _ elements: [Int],
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind
) -> [Int] {
    return elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeComparePrimitiveValues(lhs.element, rhs.element, kind: primitiveKind)
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

@inline(__always)
func runtimeSortByElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind?,
    outThrown: UnsafeMutablePointer<Int>?
) -> [(offset: Int, element: Int)]? {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var indexed: [(offset: Int, element: Int, key: Int)] = []
    indexed.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            if let outThrown {
                outThrown.pointee = thrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in collection HOF lambda. outThrown was nil.")
            }
            return nil
        }
        indexed.append((offset: indexed.count, element: elem, key: key))
    }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison: Int
        if let primitiveKind {
            comparison = runtimeComparePrimitiveValues(lhs.key, rhs.key, kind: primitiveKind)
        } else {
            comparison = runtimeCompareValues(lhs.key, rhs.key)
        }
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }
    return sorted.map { (offset: $0.offset, element: $0.element) }
}

@_cdecl("kk_list_sorted_primitive")
public func kk_list_sorted_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(listBox.elements, descending: false, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedDescending_primitive")
public func kk_list_sortedDescending_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(listBox.elements, descending: true, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_set_sorted")
public func kk_set_sorted(_ setRaw: Int) -> Int {
    guard let _setBox = runtimeSetBox(from: setRaw) else { invalidContainerPanic(#function, "set") }
    let elements = _setBox.elements
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
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

/// Returns a list containing only elements with distinct keys returned by the selector.
///
/// Key deduplication uses `RuntimeElementKey` which delegates to
/// `kk_any_hashCode` / `runtimeValuesEqual` for structural equality,
/// so data-class and other reference-typed keys compare by value.
@_cdecl("kk_list_distinctBy")
public func kk_list_distinctBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var seenKeys = Set<RuntimeElementKey>()
    seenKeys.reserveCapacity(list.elements.count)
    var result: [Int] = []
    result.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if seenKeys.insert(RuntimeElementKey(value: key)).inserted {
            result.append(elem)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_shuffled")
public func kk_list_shuffled(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let shuffled = elements.shuffled()
    return registerRuntimeObject(RuntimeListBox(elements: shuffled))
}


/// Collection<T : Comparable>.max(): T (throws NoSuchElementException if empty)
@_cdecl("kk_list_max")
public func kk_list_max(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let result = kk_list_maxOrNull(listRaw)
    guard result != runtimeNullSentinelInt else {
        return handleCollectionLambdaThrow(runtimeAllocateThrowable(message: "NoSuchElementException: List is empty."), outThrown)
    }
    return result
}
