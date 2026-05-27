import Foundation

/// ArrayDeque runtime (STDLIB-240) plus generic Array utility functions
/// (STDLIB-089).
///
/// Split out from `RuntimeCollections.swift`.

// MARK: - ArrayDeque Functions (STDLIB-240)

@_cdecl("kk_arraydeque_new")
public func kk_arraydeque_new() -> Int {
    registerRuntimeObject(RuntimeArrayDequeBox(elements: []))
}

@_cdecl("kk_arraydeque_addFirst")
public func kk_arraydeque_addFirst(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.elements.insert(element, at: 0)
    return 0
}

@_cdecl("kk_arraydeque_addLast")
public func kk_arraydeque_addLast(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.elements.append(element)
    return 0
}

@_cdecl("kk_arraydeque_removeFirst")
public func kk_arraydeque_removeFirst(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements.removeFirst()
}

@_cdecl("kk_arraydeque_removeLast")
public func kk_arraydeque_removeLast(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements.removeLast()
}

@_cdecl("kk_arraydeque_first")
public func kk_arraydeque_first(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements[0]
}

@_cdecl("kk_arraydeque_last")
public func kk_arraydeque_last(_ dequeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    guard !deque.elements.isEmpty else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArrayDeque is empty.")
        return 0
    }
    return deque.elements[deque.elements.count - 1]
}

@_cdecl("kk_arraydeque_size")
public func kk_arraydeque_size(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    return deque.elements.count
}

@_cdecl("kk_arraydeque_isEmpty")
public func kk_arraydeque_isEmpty(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(deque.elements.isEmpty ? 1 : 0)
}

@_cdecl("kk_arraydeque_toString")
public func kk_arraydeque_toString(_ dequeRaw: Int) -> UnsafeMutableRawPointer {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = deque.elements.map { elem -> String in
        runtimeElementToString(elem)
    }
    let str = "[" + parts.joined(separator: ", ") + "]"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Array utility functions (STDLIB-089)

@_cdecl("kk_array_copyOf")
public func kk_array_copyOf(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf")
    }
    let box = RuntimeArrayBox(length: array.elements.count)
    for (i, elem) in array.elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOf_newSize")
public func kk_array_copyOf_newSize(_ arrayRaw: Int, _ newSize: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf_newSize")
    }
    let targetSize = max(0, newSize)
    let box = RuntimeArrayBox(length: targetSize)
    let copiedCount = min(array.elements.count, targetSize)
    for i in 0 ..< copiedCount {
        box.elements[i] = array.elements[i]
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOf_newSize_init")
public func kk_array_copyOf_newSize_init(
    _ arrayRaw: Int,
    _ newSize: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOf_newSize_init")
    }
    let targetSize = max(0, newSize)
    let box = RuntimeArrayBox(length: targetSize)
    let copiedCount = min(array.elements.count, targetSize)
    for i in 0 ..< copiedCount {
        box.elements[i] = array.elements[i]
    }
    if copiedCount < targetSize {
        for index in copiedCount ..< targetSize {
            var thrown = 0
            let value = runtimeInvokeCollectionLambda1(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                value: index,
                outThrown: &thrown
            )
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            box.elements[index] = maybeUnbox(value)
        }
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyOfRange")
public func kk_array_copyOfRange(_ arrayRaw: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyOfRange")
    }
    // Kotlin semantics: validate boundaries
    let size = array.elements.count
    let from = max(0, min(fromIndex, size))
    let to = max(from, min(toIndex, size))
    let count = to - from
    let box = RuntimeArrayBox(length: count)
    for i in 0 ..< count {
        box.elements[i] = array.elements[from + i]
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_reversedArray")
public func kk_array_reversedArray(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_reversedArray")
    }
    let box = RuntimeArrayBox(length: array.elements.count)
    for (index, element) in array.elements.reversed().enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_sortedArray")
public func kk_array_sortedArray(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_sortedArray")
    }
    let sorted = array.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let box = RuntimeArrayBox(length: sorted.count)
    for (index, element) in sorted.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_sortedArrayDescending")
public func kk_array_sortedArrayDescending(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_sortedArrayDescending")
    }
    let sorted = array.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison > 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let box = RuntimeArrayBox(length: sorted.count)
    for (index, element) in sorted.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_copyInto")
public func kk_array_copyInto(
    _ arrayRaw: Int,
    _ destinationRaw: Int,
    _ destinationOffset: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    guard let source = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_copyInto")
    }
    guard let destination = runtimeArrayBox(from: destinationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid destination handle in kk_array_copyInto")
    }

    let sourceSize = source.elements.count
    let start = max(0, min(startIndex, sourceSize))
    let end = max(start, min(endIndex, sourceSize))
    let destinationStart = max(0, min(destinationOffset, destination.elements.count))
    let count = min(end - start, destination.elements.count - destinationStart)
    guard count > 0 else {
        return destinationRaw
    }

    let copied = Array(source.elements[start ..< start + count])
    for index in 0 ..< count {
        destination.elements[destinationStart + index] = copied[index]
    }
    return destinationRaw
}

private func runtimeArrayFromElements(_ elements: [Int]) -> Int {
    let box = RuntimeArrayBox(length: elements.count)
    for (index, element) in elements.enumerated() {
        box.elements[index] = element
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_array_sliceArray_range")
public func kk_array_sliceArray_range(_ arrayRaw: Int, _ rangeRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          let range = runtimeRangeBox(from: rangeRaw)
    else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    let size = array.elements.count
    let first = range.first
    let last = range.last
    let step = range.step > 0 ? range.step : 1
    guard first <= last, first >= 0, first < size else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }

    var selected: [Int] = []
    var index = first
    while index <= last && index < size {
        selected.append(array.elements[index])
        index += step
    }
    return runtimeArrayFromElements(selected)
}

@_cdecl("kk_array_sliceArray_iterable")
public func kk_array_sliceArray_iterable(_ arrayRaw: Int, _ indicesRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    let indexElements: [Int]
    if let indexList = runtimeListBox(from: indicesRaw) {
        indexElements = indexList.elements
    } else if let indexSet = runtimeSetBox(from: indicesRaw) {
        indexElements = indexSet.elements
    } else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }

    let size = array.elements.count
    var selected: [Int] = []
    for rawIndex in indexElements {
        let index = kk_unbox_int(rawIndex)
        if index >= 0 && index < size {
            selected.append(array.elements[index])
        }
    }
    return runtimeArrayFromElements(selected)
}

@_cdecl("kk_array_fill")
public func kk_array_fill(_ arrayRaw: Int, _ value: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_fill")
    }
    for i in 0 ..< array.elements.count {
        array.elements[i] = value
    }
    return 0
}

@_cdecl("kk_array_contentEquals")
public func kk_array_contentEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return kk_box_bool(0)
    }
    guard let other = runtimeArrayBox(from: otherRaw) else {
        return kk_box_bool(0)
    }

    // Quick size check
    if array.elements.count != other.elements.count {
        return kk_box_bool(0)
    }

    // Element-by-element comparison
    for i in 0 ..< array.elements.count {
        if !runtimeValuesEqual(array.elements[i], other.elements[i]) {
            return kk_box_bool(0)
        }
    }

    return kk_box_bool(1)
}

private func runtimeCollectionStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buffer in
        kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count))
    }
}

private func runtimeArrayContentToString(
    _ arrayRaw: Int,
    renderElement: (Int) -> String
) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return runtimeCollectionStringPointer("[]")
    }
    let rendered = array.elements.map(renderElement).joined(separator: ", ")
    return runtimeCollectionStringPointer("[\(rendered)]")
}

@_cdecl("kk_array_contentToString")
public func kk_array_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw, renderElement: runtimeElementToString)
}

@_cdecl("kk_intArray_contentToString")
public func kk_intArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int32(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_longArray_contentToString")
public func kk_longArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int64($0)) }
}

@_cdecl("kk_byteArray_contentToString")
public func kk_byteArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int8(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_shortArray_contentToString")
public func kk_shortArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(Int16(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_uIntArray_contentToString")
public func kk_uIntArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt32(bitPattern: Int32(truncatingIfNeeded: $0))) }
}

@_cdecl("kk_uLongArray_contentToString")
public func kk_uLongArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt64(bitPattern: Int64($0))) }
}

@_cdecl("kk_doubleArray_contentToString")
public func kk_doubleArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { runtimeFormatFloatingPoint(kk_bits_to_double($0)) }
}

@_cdecl("kk_floatArray_contentToString")
public func kk_floatArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { runtimeFormatFloatingPoint(kk_bits_to_float($0)) }
}

@_cdecl("kk_booleanArray_contentToString")
public func kk_booleanArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { $0 != 0 ? "true" : "false" }
}

@_cdecl("kk_charArray_contentToString")
public func kk_charArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { UnicodeScalar($0).map(String.init) ?? "?" }
}

@_cdecl("kk_uByteArray_contentToString")
public func kk_uByteArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt8(truncatingIfNeeded: $0)) }
}

@_cdecl("kk_uShortArray_contentToString")
public func kk_uShortArray_contentToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    runtimeArrayContentToString(arrayRaw) { String(UInt16(truncatingIfNeeded: $0)) }
}

private struct RuntimeArrayDeepEqualityPair: Hashable {
    let lhs: Int
    let rhs: Int
}

private func runtimePlainArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer,
          let box = tryCast(pointer, to: RuntimeArrayBox.self),
          type(of: box) == RuntimeArrayBox.self
    else {
        return nil
    }
    return box
}

private func runtimeArrayBoxesDeepEqual(
    lhsRaw: Int,
    rhsRaw: Int,
    lhs: RuntimeArrayBox,
    rhs: RuntimeArrayBox,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    guard lhs.elements.count == rhs.elements.count else {
        return false
    }
    let pair = RuntimeArrayDeepEqualityPair(lhs: lhsRaw, rhs: rhsRaw)
    guard visited.insert(pair).inserted else {
        return true
    }
    defer { visited.remove(pair) }

    for index in lhs.elements.indices {
        if !runtimeValuesDeepEqual(lhs.elements[index], rhs.elements[index], visited: &visited) {
            return false
        }
    }
    return true
}

private func runtimeValuesDeepEqual(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    if lhsRaw == rhsRaw {
        return true
    }
    if let lhs = runtimePlainArrayBox(from: lhsRaw),
       let rhs = runtimePlainArrayBox(from: rhsRaw)
    {
        return runtimeArrayBoxesDeepEqual(
            lhsRaw: lhsRaw,
            rhsRaw: rhsRaw,
            lhs: lhs,
            rhs: rhs,
            visited: &visited
        )
    }
    return runtimeValuesEqual(lhsRaw, rhsRaw)
}

@_cdecl("kk_array_contentDeepEquals")
public func kk_array_contentDeepEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return kk_box_bool(runtimeArrayBox(from: otherRaw) == nil ? 1 : 0)
    }
    guard let other = runtimeArrayBox(from: otherRaw) else {
        return kk_box_bool(0)
    }
    var visited: Set<RuntimeArrayDeepEqualityPair> = []
    return kk_box_bool(runtimeArrayBoxesDeepEqual(
        lhsRaw: arrayRaw,
        rhsRaw: otherRaw,
        lhs: array,
        rhs: other,
        visited: &visited
    ) ? 1 : 0)
}

@_cdecl("kk_array_contentHashCode")
public func kk_array_contentHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }

    var result: Int = 1
    for element in array.elements {
        result = 31 * result + kk_any_hashCode(element, 0)
    }

    return result
}

private func runtimeArrayBoxDeepToString(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> String {
    guard visited.insert(raw).inserted else {
        return "[...]"
    }
    defer { visited.remove(raw) }

    let rendered = box.elements
        .map { runtimeValueDeepToString($0, visited: &visited) }
        .joined(separator: ", ")
    return "[\(rendered)]"
}

private func runtimeValueDeepToString(_ raw: Int, visited: inout Set<Int>) -> String {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepToString(raw: raw, box: array, visited: &visited)
    }
    return runtimeElementToString(raw)
}

private func runtimeArrayStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buffer in
        kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count))
    }
}

@_cdecl("kk_array_contentDeepToString")
public func kk_array_contentDeepToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return runtimeArrayStringPointer("null")
    }
    var visited: Set<Int> = []
    return runtimeArrayStringPointer(runtimeArrayBoxDeepToString(raw: arrayRaw, box: array, visited: &visited))
}

private func runtimeArrayBoxDeepHash(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> Int {
    guard visited.insert(raw).inserted else {
        return 0
    }
    defer { visited.remove(raw) }

    var result = 1
    for element in box.elements {
        result = 31 &* result &+ runtimeValueDeepHash(element, visited: &visited)
    }
    return result
}

private func runtimeValueDeepHash(_ raw: Int, visited: inout Set<Int>) -> Int {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepHash(raw: raw, box: array, visited: &visited)
    }
    return kk_any_hashCode(raw, 0)
}

@_cdecl("kk_array_contentDeepHashCode")
public func kk_array_contentDeepHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    var visited: Set<Int> = []
    return runtimeArrayBoxDeepHash(raw: arrayRaw, box: array, visited: &visited)
}

