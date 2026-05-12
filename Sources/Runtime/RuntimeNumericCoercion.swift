import Foundation

/// Range-based coercion functions (STDLIB-CONV-006) plus UByte / UShort /
/// Char conversions (STDLIB-PRIM-002).
///
/// Split out from `RuntimeNumericCompat.swift`.

// MARK: - Range-based coercion functions (STDLIB-CONV-006)

/// Double.coerceIn(range) — range object argument
@_cdecl("kk_double_coerceIn_range")
public func kk_double_coerceIn_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_double_coerceIn_range")
    }
    let minimum = kk_double_to_bits(Double(range.first))
    let maximum = kk_double_to_bits(Double(range.last))
    return kk_double_coerceIn(value, minimum, maximum)
}

/// Float.coerceIn(range) — range object argument
@_cdecl("kk_float_coerceIn_range")
public func kk_float_coerceIn_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_float_coerceIn_range")
    }
    let minimum = kk_float_to_bits(Float(range.first))
    let maximum = kk_float_to_bits(Float(range.last))
    return kk_float_coerceIn(value, minimum, maximum)
}

/// Int.coerceIn(range) — range object argument
@_cdecl("kk_int_coerceIn_range")
public func kk_int_coerceIn_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_int_coerceIn_range")
    }
    return kk_int_coerceIn(value, range.first, range.last)
}

/// Long.coerceIn(range) — range object argument
@_cdecl("kk_long_coerceIn_range")
public func kk_long_coerceIn_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_coerceIn_range")
    }
    return kk_long_coerceIn(value, range.first, range.last)
}

// MARK: - Range-based coerceAtLeast/coerceAtMost functions (STDLIB-CONV-006)

/// Double.coerceAtLeast(range) — use range first as minimum
@_cdecl("kk_double_coerceAtLeast_range")
public func kk_double_coerceAtLeast_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_double_coerceAtLeast_range")
    }
    let minimum = kk_double_to_bits(Double(range.first))
    return kk_double_coerceAtLeast(value, minimum)
}

/// Double.coerceAtMost(range) — use range last as maximum
@_cdecl("kk_double_coerceAtMost_range")
public func kk_double_coerceAtMost_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_double_coerceAtMost_range")
    }
    let maximum = kk_double_to_bits(Double(range.last))
    return kk_double_coerceAtMost(value, maximum)
}

/// Float.coerceAtLeast(range) — use range first as minimum
@_cdecl("kk_float_coerceAtLeast_range")
public func kk_float_coerceAtLeast_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_float_coerceAtLeast_range")
    }
    let minimum = kk_float_to_bits(Float(range.first))
    return kk_float_coerceAtLeast(value, minimum)
}

/// Float.coerceAtMost(range) — use range last as maximum
@_cdecl("kk_float_coerceAtMost_range")
public func kk_float_coerceAtMost_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_float_coerceAtMost_range")
    }
    let maximum = kk_float_to_bits(Float(range.last))
    return kk_float_coerceAtMost(value, maximum)
}

/// Int.coerceAtLeast(range) — use range first as minimum
@_cdecl("kk_int_coerceAtLeast_range")
public func kk_int_coerceAtLeast_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_int_coerceAtLeast_range")
    }
    return kk_int_coerceAtLeast(value, range.first)
}

/// Int.coerceAtMost(range) — use range last as maximum
@_cdecl("kk_int_coerceAtMost_range")
public func kk_int_coerceAtMost_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_int_coerceAtMost_range")
    }
    return kk_int_coerceAtMost(value, range.last)
}

/// Long.coerceAtLeast(range) — use range first as minimum
@_cdecl("kk_long_coerceAtLeast_range")
public func kk_long_coerceAtLeast_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_coerceAtLeast_range")
    }
    return kk_long_coerceAtLeast(value, range.first)
}

/// Long.coerceAtMost(range) — use range last as maximum
@_cdecl("kk_long_coerceAtMost_range")
public func kk_long_coerceAtMost_range(_ value: Int, _ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_long_coerceAtMost_range")
    }
    return kk_long_coerceAtMost(value, range.last)
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

// MARK: - UByte and UShort Conversions (STDLIB-PRIM-002)

@_cdecl("kk_int_to_ubyte")
public func kk_int_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_int_to_ushort")
public func kk_int_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_ubyte")
public func kk_long_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_ushort")
public func kk_long_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_ubyte")
public func kk_uint_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_ushort")
public func kk_uint_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_ubyte")
public func kk_ulong_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_ushort")
public func kk_ulong_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_int")
public func kk_ubyte_to_int(_ value: Int) -> Int {
    // UByte is always in valid range for Int
    value
}

@_cdecl("kk_ushort_to_int")
public func kk_ushort_to_int(_ value: Int) -> Int {
    // UShort is always in valid range for Int
    value
}

@_cdecl("kk_ubyte_to_long")
public func kk_ubyte_to_long(_ value: Int) -> Int {
    // UByte is always in valid range for Long
    value
}

@_cdecl("kk_ushort_to_long")
public func kk_ushort_to_long(_ value: Int) -> Int {
    // UShort is always in valid range for Long
    value
}

@_cdecl("kk_ubyte_to_uint")
public func kk_ubyte_to_uint(_ value: Int) -> Int {
    // UByte is always in valid range for UInt
    value
}

@_cdecl("kk_ushort_to_uint")
public func kk_ushort_to_uint(_ value: Int) -> Int {
    // UShort is always in valid range for UInt
    value
}

@_cdecl("kk_ubyte_to_ulong")
public func kk_ubyte_to_ulong(_ value: Int) -> Int {
    // UByte is always in valid range for ULong
    value
}

@_cdecl("kk_ushort_to_ulong")
public func kk_ushort_to_ulong(_ value: Int) -> Int {
    // UShort is always in valid range for ULong
    value
}

// MARK: - Char Conversions (STDLIB-PRIM-002)

@_cdecl("kk_int_to_char")
public func kk_int_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_char")
public func kk_long_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_char")
public func kk_uint_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_char")
public func kk_ulong_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_char")
public func kk_ubyte_to_char(_ value: Int) -> Int {
    // UByte is always in valid range for Char
    value
}

@_cdecl("kk_ushort_to_char")
public func kk_ushort_to_char(_ value: Int) -> Int {
    // UShort is always in valid range for Char
    value
}

@_cdecl("kk_char_to_int")
public func kk_char_to_int(_ value: Int) -> Int {
    // Char is stored as Int, so this is identity
    value
}

@_cdecl("kk_char_to_long")
public func kk_char_to_long(_ value: Int) -> Int {
    // Char is stored as Int, so this is identity
    value
}

@_cdecl("kk_char_to_uint")
public func kk_char_to_uint(_ value: Int) -> Int {
    // Char is stored as Int, so this is identity
    value
}

@_cdecl("kk_char_to_ulong")
public func kk_char_to_ulong(_ value: Int) -> Int {
    // Char is stored as Int, so this is identity
    value
}

// MARK: - Additional Unsigned Conversions (STDLIB-PRIM-002)

@_cdecl("kk_float_to_uint")
public func kk_float_to_uint(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(UInt32.max) { return Int(UInt32.max) }
    if f <= 0 { return 0 }
    return Int(UInt32(f))
}

@_cdecl("kk_double_to_uint")
public func kk_double_to_uint(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(UInt32.max) { return Int(UInt32.max) }
    if d <= 0 { return 0 }
    return Int(UInt32(d))
}

@_cdecl("kk_float_to_ulong")
public func kk_float_to_ulong(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(UInt64.max) { return Int(UInt64.max) }
    if f <= 0 { return 0 }
    return Int(UInt64(f))
}

@_cdecl("kk_double_to_ulong")
public func kk_double_to_ulong(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(UInt64.max) { return Int(UInt64.max) }
    if d <= 0 { return 0 }
    return Int(UInt64(d))
}

@_cdecl("kk_byte_to_uint")
public func kk_byte_to_uint(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_short_to_uint")
public func kk_short_to_uint(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_byte_to_ulong")
public func kk_byte_to_ulong(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_short_to_ulong")
public func kk_short_to_ulong(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

// MARK: - Additional Char Conversions (STDLIB-PRIM-002)

@_cdecl("kk_byte_to_char")
public func kk_byte_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: Int8(truncatingIfNeeded: value)))
}

@_cdecl("kk_short_to_char")
public func kk_short_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: Int16(truncatingIfNeeded: value)))
}

@_cdecl("kk_float_to_char")
public func kk_float_to_char(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN || f.isSignalingNaN { return 0 }
    if f <= 0 { return 0 }
    if f >= Float(UInt16.max) { return Int(UInt16.max) }
    return Int(UInt16(f))
}

@_cdecl("kk_double_to_char")
public func kk_double_to_char(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN || d.isSignalingNaN { return 0 }
    if d <= 0 { return 0 }
    if d >= Double(UInt16.max) { return Int(UInt16.max) }
    return Int(UInt16(d))
}

func runtimeMakeStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    value.withCString { cString in
        cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    }
}

func runtimeNormalizedShift(_ value: Int) -> Int {
    Int(UInt(bitPattern: value) & UInt(Int.bitWidth - 1))
}

