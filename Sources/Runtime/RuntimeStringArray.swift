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
    _ = throwableRaw
    return 0
}

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never {
    fatalError(runtimePanicMessage(fromCString: cstr))
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

private enum RuntimeTypeTokenEncoding {
    static let baseMask = 0xFF
    static let nullableBit = 0x100
    static let anyBase = 1
    static let stringBase = 2
    static let intBase = 3
    static let booleanBase = 4
    static let nullBase = 5
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
    let base = typeToken & RuntimeTypeTokenEncoding.baseMask
    let isNullableTarget = (typeToken & RuntimeTypeTokenEncoding.nullableBit) != 0

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

    case RuntimeTypeTokenEncoding.intBase:
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

    default:
        return 0
    }
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
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.message))")
        return
    }
    Swift.print("<object \(raw)>")
}
