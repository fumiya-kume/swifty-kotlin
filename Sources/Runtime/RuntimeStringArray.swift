import Foundation

@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let throwableInt = runtimeAllocateThrowable(message: text)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        fatalError("kk_throwable_new: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_is_cancellation")
public func kk_throwable_is_cancellation(_ throwableRaw: Int) -> Int {
    kk_is_cancellation_exception(throwableRaw)
}

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never {
    fatalError(runtimePanicMessage(fromCString: cstr))
}

@_cdecl("kk_abort_unreachable")
public func kk_abort_unreachable(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: reached unreachable code")
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

private enum RuntimeTypeTokenEncoding {
    static let baseMask: Int64 = 0xFF
    static let nullableBit: Int64 = 0x100
    static let payloadShift: Int64 = 9
    static let payloadMask: Int64 = (1 << 55) - 1
    static let anyBase: Int64 = 1
    static let stringBase: Int64 = 2
    static let intBase: Int64 = 3
    static let booleanBase: Int64 = 4
    static let nullBase: Int64 = 5
    static let nominalBase: Int64 = 6
    static let uintBase: Int64 = 7
    static let ulongBase: Int64 = 8
    static let ubyteBase: Int64 = 9
    static let ushortBase: Int64 = 10
}

func runtimePanicMessage(fromCString cstr: UnsafePointer<CChar>) -> String {
    let message = String(cString: cstr)
    return "KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(message)"
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = String(decoding: buffer, as: UTF8.self)
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return opaque
}

@_cdecl("kk_int_toString_radix")
public func kk_int_toString_radix(_ value: Int, _ radix: Int) -> UnsafeMutableRawPointer {
    let clampedRadix = max(2, min(36, radix))
    let str = String(value, radix: clampedRadix)
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let lhs = extractString(from: normalizeNullableRuntimePointer(a)) ?? ""
    let rhs = extractString(from: normalizeNullableRuntimePointer(b)) ?? ""
    let box = RuntimeStringBox(lhs + rhs)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return opaque
}

@_cdecl("kk_string_compareTo")
public func kk_string_compareTo(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> Int {
    let lhs = extractString(from: normalizeNullableRuntimePointer(a)) ?? ""
    let rhs = extractString(from: normalizeNullableRuntimePointer(b)) ?? ""
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}

@_cdecl("kk_string_length")
public func kk_string_length(_ strRaw: Int) -> Int {
    if strRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return runtimeNullSentinelInt
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer, let stringBox = tryCast(ptr, to: RuntimeStringBox.self) else {
        return runtimeNullSentinelInt
    }
    return stringBox.value.utf8.count
}

@_cdecl("kk_op_is")
public func kk_op_is(_ value: Int, _ typeToken: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let isNullableTarget = (token & RuntimeTypeTokenEncoding.nullableBit) != 0
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask

    if value == runtimeNullSentinelInt {
        if isNullableTarget || base == RuntimeTypeTokenEncoding.nullBase {
            return 1
        }
        return 0
    }

    switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        return 1

    case RuntimeTypeTokenEncoding.stringBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isObjectPointer else {
            return 0
        }
        return tryCast(ptr, to: RuntimeStringBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.uintBase,
         RuntimeTypeTokenEncoding.ulongBase,
         RuntimeTypeTokenEncoding.ubyteBase,
         RuntimeTypeTokenEncoding.ushortBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return 1
        }
        return tryCast(ptr, to: RuntimeIntBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.booleanBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return (value == 0 || value == 1) ? 1 : 0
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return (value == 0 || value == 1) ? 1 : 0
        }
        return tryCast(ptr, to: RuntimeBoolBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.nullBase:
        return 0

    case RuntimeTypeTokenEncoding.nominalBase:
        guard let sourceTypeID = runtimeObjectTypeID(rawValue: value) else {
            return 0
        }
        return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: payload) ? 1 : 0

    default:
        return 0
    }
}

@_cdecl("kk_op_cast")
public func kk_op_cast(_ value: Int, _ typeToken: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if kk_op_is(value, typeToken) != 0 {
        return value
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "ClassCastException")
    return 0
}

@_cdecl("kk_op_safe_cast")
public func kk_op_safe_cast(_ value: Int, _ typeToken: Int) -> Int {
    kk_op_is(value, typeToken) != 0 ? value : runtimeNullSentinelInt
}

@_cdecl("kk_op_contains")
public func kk_op_contains(_ container: Int, _ element: Int) -> Int {
    guard let array = runtimeArrayBox(from: container) else {
        return 0
    }
    return array.elements.contains(element) ? 1 : 0
}

@_cdecl("kk_array_new")
public func kk_array_new(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_object_new")
public func kk_object_new(_ length: Int, _ classId: Int) -> Int {
    let box = RuntimeObjectBox(length: length, classID: Int64(classId))
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        let key = UInt(bitPattern: opaque)
        state.objectPointers.insert(key)
        state.objectTypeByPointer[key] = Int64(classId)
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_object_type_id")
public func kk_object_type_id(_ objectRaw: Int) -> Int {
    Int(runtimeObjectTypeID(rawValue: objectRaw) ?? 0)
}

/// Returns the simple name of the type encoded in the given type token as a
/// runtime string pointer.  For builtin types the name is derived from the
/// token base; for nominal types the compiler supplies a `nameHint` string
/// pointer that is returned directly (the hint carries the simple name that
/// was known at compile-time after inline expansion).
@_cdecl("kk_type_token_simple_name")
public func kk_type_token_simple_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    // If a compiler-provided name hint is available, use it directly.
    if nameHint != 0, nameHint != runtimeNullSentinelInt {
        return nameHint
    }
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let name = switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        "Any"
    case RuntimeTypeTokenEncoding.stringBase:
        "String"
    case RuntimeTypeTokenEncoding.intBase:
        "Int"
    case RuntimeTypeTokenEncoding.uintBase:
        "UInt"
    case RuntimeTypeTokenEncoding.ulongBase:
        "ULong"
    case RuntimeTypeTokenEncoding.ubyteBase:
        "UByte"
    case RuntimeTypeTokenEncoding.ushortBase:
        "UShort"
    case RuntimeTypeTokenEncoding.booleanBase:
        "Boolean"
    case RuntimeTypeTokenEncoding.nullBase:
        "Nothing"
    default:
        "Unknown"
    }
    let utf8 = Array(name.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Returns the qualified name of the type encoded in the given type token.
/// Behaves identically to `kk_type_token_simple_name` for now; a future
/// implementation may distinguish package-qualified names for nominal types.
@_cdecl("kk_type_token_qualified_name")
public func kk_type_token_qualified_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    kk_type_token_simple_name(typeToken, nameHint)
}

@_cdecl("kk_type_register_super")
public func kk_type_register_super(_ childTypeId: Int, _ superTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(superTypeId))
    return 0
}

@_cdecl("kk_type_register_iface")
public func kk_type_register_iface(_ childTypeId: Int, _ ifaceTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(ifaceTypeId))
    return 0
}

@_cdecl("kk_object_register_itable_method")
public func kk_object_register_itable_method(
    _ objectRaw: Int,
    _ ifaceSlot: Int,
    _ methodSlot: Int,
    _ functionRaw: Int
) -> Int {
    guard ifaceSlot >= 0,
          methodSlot >= 0,
          functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    let dispatchKey = (UInt64(UInt32(ifaceSlot)) << 32) | UInt64(UInt32(methodSlot))
    runtimeStorage.withLock { state in
        var methods = state.objectItableMethods[objectKey] ?? [:]
        methods[dispatchKey] = functionRaw
        state.objectItableMethods[objectKey] = methods
    }
    return 0
}

@_cdecl("kk_array_get")
public func kk_array_get(_ arrayRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    return array.elements[index]
}

@_cdecl("kk_array_get_inbounds")
public func kk_array_get_inbounds(_ arrayRaw: Int, _ index: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          array.elements.indices.contains(index)
    else {
        fatalError("kk_array_get_inbounds precondition failed")
    }
    return array.elements[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    array.elements[index] = value
    return value
}

@_cdecl("kk_vararg_spread_concat")
public func kk_vararg_spread_concat(_ pairsArrayRaw: Int, _ pairCount: Int) -> Int {
    guard let pairs = runtimeArrayBox(from: pairsArrayRaw),
          pairCount > 0,
          pairs.elements.count >= pairCount * 2 else { return kk_array_new(0) }
    var totalCount = 0
    for i in 0 ..< pairCount {
        let marker = pairs.elements[i * 2]
        let value = pairs.elements[i * 2 + 1]
        if marker == -1 {
            if let array = runtimeArrayBox(from: value) {
                totalCount += array.elements.count
            }
        } else {
            totalCount += 1
        }
    }
    let result = kk_array_new(totalCount)
    if let box = runtimeArrayBox(from: result) {
        var writeIndex = 0
        for i in 0 ..< pairCount {
            let marker = pairs.elements[i * 2]
            let value = pairs.elements[i * 2 + 1]
            if marker == -1 {
                if let array = runtimeArrayBox(from: value) {
                    for elem in array.elements {
                        box.elements[writeIndex] = elem
                        writeIndex += 1
                    }
                }
            } else {
                box.elements[writeIndex] = value
                writeIndex += 1
            }
        }
    }
    return result
}

@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    let intValue = if let ptr = obj {
        Int(bitPattern: ptr)
    } else {
        0
    }
    if intValue == runtimeNullSentinelInt {
        Swift.print("null")
        return
    }
    guard let raw = obj else {
        Swift.print(intValue)
        return
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    if !isObjectPointer {
        Swift.print(intValue)
        return
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        Swift.print(boolBox.value ? "true" : "false")
        return
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        Swift.print(intBox.value)
        return
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        Swift.print(stringBox.value)
        return
    }
    if let doubleBox = tryCast(raw, to: RuntimeDoubleBox.self) {
        Swift.print(doubleBox.value)
        return
    }
    if let floatBox = tryCast(raw, to: RuntimeFloatBox.self) {
        Swift.print(floatBox.value)
        return
    }
    if let longBox = tryCast(raw, to: RuntimeLongBox.self) {
        Swift.print(longBox.value)
        return
    }
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.message))")
        return
    }
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        if let scalar = UnicodeScalar(charBox.value) {
            Swift.print(Character(scalar))
        } else {
            Swift.print("�")
        }
        return
    }
    if let listBox = tryCast(raw, to: RuntimeListBox.self) {
        let rendered = listBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        let rendered = setBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        Swift.print("{\(rendered)}")
        return
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.first)
        let second = runtimeRenderAnyForPrint(pairBox.second)
        Swift.print("(\(first), \(second))")
        return
    }
    if let _ = tryCast(raw, to: RuntimeIndexingIterableBox.self) {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        Swift.print("kotlin.collections.IndexingIterable@\(hex)")
        return
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        let rendered = arrayBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    Swift.print("<object \(raw)>")
}

/// Runtime support for kotlin.io.println() (STDLIB-063).
/// Prints a newline with no arguments.
@_cdecl("kk_println_newline")
public func kk_println_newline() {
    Swift.print()
}

/// Runtime support for kotlin.io.readLine() (STDLIB-063).
/// Reads a line from stdin. Returns null (runtimeNullSentinelInt) on EOF.
@_cdecl("kk_readline")
public func kk_readline() -> Int {
    guard let line = readLine() else {
        return runtimeNullSentinelInt
    }
    let utf8 = Array(line.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

private func runtimeRenderAnyForPrint(_ value: Int) -> String {
    if value == runtimeNullSentinelInt {
        return "null"
    }
    guard let raw = UnsafeMutableRawPointer(bitPattern: value) else {
        return String(value)
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    guard isObjectPointer else {
        return String(value)
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        return String(intBox.value)
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let doubleBox = tryCast(raw, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let floatBox = tryCast(raw, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let longBox = tryCast(raw, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        if let scalar = UnicodeScalar(charBox.value) {
            return String(Character(scalar))
        }
        return "�"
    }
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        return "Throwable(\(throwable.message))"
    }
    if let listBox = tryCast(raw, to: RuntimeListBox.self) {
        return "[\(listBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        return "[\(setBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        return "{\(rendered)}"
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.first)
        let second = runtimeRenderAnyForPrint(pairBox.second)
        return "(\(first), \(second))"
    }
    if let _ = tryCast(raw, to: RuntimeIndexingIterableBox.self) {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        return "kotlin.collections.IndexingIterable@\(hex)"
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        return "[\(arrayBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    return "<object \(raw)>"
}

// MARK: - String nullable receiver helpers

@_cdecl("kk_string_isNullOrEmpty")
public func kk_string_isNullOrEmpty(_ strRaw: Int) -> Int {
    guard let rawPointer = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return kk_box_bool(1)
    }
    guard let str = extractString(from: rawPointer) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(str.isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNullOrBlank")
public func kk_string_isNullOrBlank(_ strRaw: Int) -> Int {
    guard let rawPointer = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return kk_box_bool(1)
    }
    guard let str = extractString(from: rawPointer) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(str.allSatisfy(\.isWhitespace) ? 1 : 0)
}
