import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@_cdecl("kk_any_to_string")
public func kk_any_to_string(_ value: Int, _ tag: Int32) -> UnsafeMutableRawPointer {
    if value == runtimeNullSentinelInt {
        return runtimeMakeStringPointer("null")
    }
    if tag == 2 {
        return runtimeMakeStringPointer(value != 0 ? "true" : "false")
    }
    if tag == 3,
       let pointer = UnsafeMutableRawPointer(bitPattern: value),
       extractString(from: pointer) != nil
    {
        return pointer
    }
    return runtimeMakeStringPointer(runtimeElementToString(value))
}

private func runtimeStringHashCode(_ value: String) -> Int {
    value.unicodeScalars.reduce(0) { partial, scalar in
        31 &* partial &+ Int(Int32(bitPattern: scalar.value))
    }
}

private func runtimeAnyHashCode(_ value: Int, _ tag: Int32) -> Int {
    if value == runtimeNullSentinelInt {
        return 0
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: value) else {
        return tag == 2 ? (value != 0 ? 1231 : 1237) : value
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return tag == 2 ? (value != 0 ? 1231 : 1237) : value
    }
    if let stringBox = tryCast(pointer, to: RuntimeStringBox.self) {
        return runtimeStringHashCode(stringBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1231 : 1237
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        let longValue = Int64(longBox.value)
        return Int(truncatingIfNeeded: longValue ^ (longValue >> 32))
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return kk_float_to_bits(floatBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        let bits = Int64(bitPattern: UInt64(bitPattern: Int64(kk_double_to_bits(doubleBox.value))))
        return Int(truncatingIfNeeded: bits ^ (bits >> 32))
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return Int(truncatingIfNeeded: UInt(bitPattern: pointer))
}

private func runtimeAnyKind(_ value: Int, _ tag: Int32) -> Int32 {
    if value == runtimeNullSentinelInt {
        return 0
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: value) else {
        return tag == 2 ? 2 : 1
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return tag == 2 ? 2 : 1
    }
    if tryCast(pointer, to: RuntimeBoolBox.self) != nil {
        return 2
    }
    if tryCast(pointer, to: RuntimeStringBox.self) != nil {
        return 3
    }
    if tryCast(pointer, to: RuntimeIntBox.self) != nil {
        return 1
    }
    if tryCast(pointer, to: RuntimeLongBox.self) != nil {
        return 4
    }
    if tryCast(pointer, to: RuntimeFloatBox.self) != nil {
        return 5
    }
    if tryCast(pointer, to: RuntimeDoubleBox.self) != nil {
        return 6
    }
    if tryCast(pointer, to: RuntimeCharBox.self) != nil {
        return 7
    }
    return 100
}

/// Any.hashCode() — uses runtime-aware hashing for boxed values and raw primitives.
@_cdecl("kk_any_hashCode")
public func kk_any_hashCode(_ value: Int, _ tag: Int32) -> Int {
    runtimeAnyHashCode(value, tag)
}

/// Any.equals(other) — uses runtime-aware equality for boxed values and tagged primitives.
@_cdecl("kk_any_equals")
public func kk_any_equals(_ lhs: Int, _ lhsTag: Int32, _ rhs: Int, _ rhsTag: Int32) -> Int {
    if runtimeAnyKind(lhs, lhsTag) != runtimeAnyKind(rhs, rhsTag) {
        return kk_box_bool(0)
    }
    return kk_box_bool(runtimeValuesEqual(lhs, rhs) ? 1 : 0)
}

@_cdecl("kk_float_to_bits")
public func kk_float_to_bits(_ value: Float) -> Int {
    Int(value.bitPattern)
}

@_cdecl("kk_bits_to_float")
public func kk_bits_to_float(_ value: Int) -> Float {
    Float(bitPattern: UInt32(truncatingIfNeeded: value))
}

@_cdecl("kk_double_to_bits")
public func kk_double_to_bits(_ value: Double) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
}

@_cdecl("kk_bits_to_double")
public func kk_bits_to_double(_ value: Int) -> Double {
    Double(bitPattern: UInt64(bitPattern: Int64(value)))
}

@_cdecl("kk_int_to_float_bits")
public func kk_int_to_float_bits(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_int_to_float")
public func kk_int_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_int_to_byte")
public func kk_int_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_int_to_short")
public func kk_int_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

@_cdecl("kk_int_to_double_bits")
public func kk_int_to_double_bits(_ value: Int) -> Int {
    kk_double_to_bits(Double(value))
}

@_cdecl("kk_float_to_double_bits")
public func kk_float_to_double_bits(_ value: Int) -> Int {
    kk_double_to_bits(Double(kk_bits_to_float(value)))
}

@_cdecl("kk_println_long")
public func kk_println_long(_ value: Int) {
    Swift.print(value)
}

@_cdecl("kk_println_float")
public func kk_println_float(_ value: Int) {
    let rendered = runtimeFormatFloatingPoint(kk_bits_to_float(value))
    Swift.print(rendered)
}

@_cdecl("kk_println_double")
public func kk_println_double(_ value: Int) {
    let rendered = runtimeFormatFloatingPoint(kk_bits_to_double(value))
    Swift.print(rendered)
}

@_cdecl("kk_math_abs_int")
public func kk_math_abs_int(_ value: Int) -> Int {
    if value == Int.min {
        return Int.min
    }
    return value < 0 ? -value : value
}

@_cdecl("kk_math_abs")
public func kk_math_abs(_ value: Int) -> Int {
    kk_double_to_bits(Swift.abs(kk_bits_to_double(value)))
}

@_cdecl("kk_math_sqrt")
public func kk_math_sqrt(_ value: Int) -> Int {
    kk_double_to_bits(sqrt(kk_bits_to_double(value)))
}

@_cdecl("kk_math_pow")
public func kk_math_pow(_ base: Int, _ exp: Int) -> Int {
    let rawBase = kk_bits_to_double(base)
    let rawExp = kk_bits_to_double(exp)
    return kk_double_to_bits(pow(rawBase, rawExp))
}

@_cdecl("kk_math_ceil")
public func kk_math_ceil(_ value: Int) -> Int {
    kk_double_to_bits(ceil(kk_bits_to_double(value)))
}

@_cdecl("kk_math_floor")
public func kk_math_floor(_ value: Int) -> Int {
    kk_double_to_bits(floor(kk_bits_to_double(value)))
}

@_cdecl("kk_math_round")
public func kk_math_round(_ value: Int) -> Int {
    kk_double_to_bits(round(kk_bits_to_double(value)))
}

@_cdecl("kk_println_char")
public func kk_println_char(_ value: Int) {
    if let scalar = UnicodeScalar(value) {
        Swift.print(String(scalar))
    } else {
        Swift.print("\u{FFFD}")
    }
}

@_cdecl("kk_println_bool")
public func kk_println_bool(_ value: Int) {
    let unboxedValue = kk_unbox_bool(value)
    Swift.print(unboxedValue != 0 ? "true" : "false")
}

@_cdecl("kk_bitwise_and")
public func kk_bitwise_and(_ lhs: Int, _ rhs: Int) -> Int {
    lhs & rhs
}

@_cdecl("kk_bitwise_or")
public func kk_bitwise_or(_ lhs: Int, _ rhs: Int) -> Int {
    lhs | rhs
}

@_cdecl("kk_bitwise_xor")
public func kk_bitwise_xor(_ lhs: Int, _ rhs: Int) -> Int {
    lhs ^ rhs
}

@_cdecl("kk_op_inv")
public func kk_op_inv(_ value: Int) -> Int {
    ~value
}

@_cdecl("kk_op_shl")
public func kk_op_shl(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return Int(bitPattern: UInt(bitPattern: lhs) << shift)
}

@_cdecl("kk_op_shr")
public func kk_op_shr(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return lhs >> shift
}

@_cdecl("kk_op_ushr")
public func kk_op_ushr(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return Int(bitPattern: UInt(bitPattern: lhs) >> shift)
}

@_cdecl("kk_double_to_int")
public func kk_double_to_int(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(Int32.max) { return Int(Int32.max) }
    if d <= Double(Int32.min) { return Int(Int32.min) }
    return Int(Int32(d))
}

@_cdecl("kk_float_to_int")
public func kk_float_to_int(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(Int32.max) { return Int(Int32.max) }
    if f <= Float(Int32.min) { return Int(Int32.min) }
    return Int(Int32(f))
}

@_cdecl("kk_double_to_long")
public func kk_double_to_long(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(Int64.max) { return Int(Int64.max) }
    if d <= Double(Int64.min) { return Int(Int64.min) }
    return Int(Int64(d))
}

@_cdecl("kk_float_to_long")
public func kk_float_to_long(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(Int64.max) { return Int(Int64.max) }
    if f <= Float(Int64.min) { return Int(Int64.min) }
    return Int(Int64(f))
}

@_cdecl("kk_long_to_int")
public func kk_long_to_int(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_float")
public func kk_long_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_long_to_double")
public func kk_long_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(value))
}

@_cdecl("kk_double_to_float")
public func kk_double_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(kk_bits_to_double(value)))
}

@_cdecl("kk_long_to_byte")
public func kk_long_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_short")
public func kk_long_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

@_cdecl("kk_int_coerceIn")
public func kk_int_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    if value < minimum { return minimum }
    if value > maximum { return maximum }
    return value
}

@_cdecl("kk_int_coerceAtLeast")
public func kk_int_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    value < minimum ? minimum : value
}

@_cdecl("kk_int_coerceAtMost")
public func kk_int_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    value > maximum ? maximum : value
}

@_cdecl("kk_uint_to_int")
public func kk_uint_to_int(_ value: Int) -> Int {
    value
}

@_cdecl("kk_ulong_to_int")
public func kk_ulong_to_int(_ value: Int) -> Int {
    value
}

@_cdecl("kk_int_to_uint")
public func kk_int_to_uint(_ value: Int) -> Int {
    value
}

@_cdecl("kk_long_to_uint")
public func kk_long_to_uint(_ value: Int) -> Int {
    value
}

@_cdecl("kk_int_to_long")
public func kk_int_to_long(_ value: Int) -> Int {
    value
}

@_cdecl("kk_uint_to_long")
public func kk_uint_to_long(_ value: Int) -> Int {
    value
}

@_cdecl("kk_int_to_ulong")
public func kk_int_to_ulong(_ value: Int) -> Int {
    value
}

@_cdecl("kk_long_to_ulong")
public func kk_long_to_ulong(_ value: Int) -> Int {
    value
}

@_cdecl("kk_uint_to_ulong")
public func kk_uint_to_ulong(_ value: Int) -> Int {
    value
}

private func runtimeMakeStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    value.withCString { cString in
        cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    }
}

private func runtimeNormalizedShift(_ value: Int) -> Int {
    Int(UInt(bitPattern: value) & UInt(Int.bitWidth - 1))
}
