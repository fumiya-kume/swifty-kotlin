
// ArrayDeque runtime (STDLIB-240) plus generic Array utility functions
// (STDLIB-089).
//
// Split out from `RuntimeCollections.swift`.

// MARK: - ArrayDeque ring-buffer bridges (KSP-625)
//
// `first` / `last` / `isEmpty` / `toString` and the emptiness checks that guard
// `removeFirst` / `removeLast` now live in
// `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayDeque.kt`; only the
// element-storage mutation primitives remain here.

@_cdecl("__kk_arraydeque_new")
public func __kk_arraydeque_new() -> Int {
    registerRuntimeObject(RuntimeArrayDequeBox(elements: []))
}

@_cdecl("__kk_arraydeque_addFirst")
public func __kk_arraydeque_addFirst(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.pushFirst(RuntimeValue(raw: element))
    return 0
}

@_cdecl("__kk_arraydeque_addLast")
public func __kk_arraydeque_addLast(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.pushLast(RuntimeValue(raw: element))
    return 0
}

@_cdecl("__kk_arraydeque_removeFirst")
public func __kk_arraydeque_removeFirst(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.popFirst()
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_removeLast")
public func __kk_arraydeque_removeLast(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.popLast()
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_get")
public func __kk_arraydeque_get(_ dequeRaw: Int, _ index: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.element(at: index)
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_size")
public func __kk_arraydeque_size(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    return deque.count
}

// MARK: - Array utility functions (STDLIB-089)

@_cdecl("__kk_array_copyOf")
public func __kk_array_copyOf(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_array_copyOf")
    }
    let box = RuntimeArrayBox(length: array.elements.count)
    for (i, elem) in array.elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
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
        // swiftlint:disable:next for_where
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

@_cdecl("__kk_array_contentDeepEquals")
public func __kk_array_contentDeepEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
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

@_cdecl("__kk_array_contentDeepToString")
public func __kk_array_contentDeepToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
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

@_cdecl("__kk_array_contentDeepHashCode")
public func __kk_array_contentDeepHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    var visited: Set<Int> = []
    return runtimeArrayBoxDeepHash(raw: arrayRaw, box: array, visited: &visited)
}
