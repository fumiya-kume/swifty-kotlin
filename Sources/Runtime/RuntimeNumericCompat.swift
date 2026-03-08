import Foundation

@_cdecl("kk_any_to_string")
public func kk_any_to_string(_ value: Int, _ tag: Int32) -> UnsafeMutableRawPointer {
    if value == runtimeNullSentinelInt {
        return runtimeMakeStringPointer("null")
    }
    if tag == 3,
       let pointer = UnsafeMutableRawPointer(bitPattern: value),
       extractString(from: pointer) != nil
    {
        return pointer
    }
    return runtimeMakeStringPointer(runtimeElementToString(value))
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
    Swift.print(kk_bits_to_float(value))
}

@_cdecl("kk_println_double")
public func kk_println_double(_ value: Int) {
    Swift.print(kk_bits_to_double(value))
}

@_cdecl("kk_println_char")
public func kk_println_char(_ value: Int) {
    if let scalar = UnicodeScalar(value) {
        Swift.print(String(scalar))
    } else {
        Swift.print("\u{FFFD}")
    }
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
