import Foundation

/// Bit-manipulation runtime functions (STDLIB-BIT-007).
///
/// Split out from `RuntimeNumericCompat.swift`.

// MARK: - STDLIB-BIT-007: Additional bit manipulation functions

@_cdecl("kk_int_rotateLeft")
public func kk_int_rotateLeft(_ value: Int, _ distance: Int) -> Int {
    let u = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
    let d = UInt32(truncatingIfNeeded: distance) & 31
    guard d != 0 else { return Int(Int32(bitPattern: u)) }
    return Int(Int32(bitPattern: (u << d) | (u >> (32 - d))))
}

@_cdecl("kk_int_rotateRight")
public func kk_int_rotateRight(_ value: Int, _ distance: Int) -> Int {
    let u = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
    let d = UInt32(truncatingIfNeeded: distance) & 31
    guard d != 0 else { return Int(Int32(bitPattern: u)) }
    return Int(Int32(bitPattern: (u >> d) | (u << (32 - d))))
}

@_cdecl("kk_int_highestOneBit")
public func kk_int_highestOneBit(_ value: Int) -> Int {
    let truncated = Int32(truncatingIfNeeded: value)
    if truncated == 0 { return 0 }
    return Int(1 << (31 - truncated.leadingZeroBitCount))
}

@_cdecl("kk_int_lowestOneBit")
public func kk_int_lowestOneBit(_ value: Int) -> Int {
    let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
    if bits == 0 { return 0 }
    return Int(Int32(bitPattern: bits & (0 &- bits)))
}

@_cdecl("kk_int_takeHighestOneBit")
public func kk_int_takeHighestOneBit(_ value: Int) -> Int {
    let truncated = Int32(truncatingIfNeeded: value)
    if truncated == 0 { return 0 }
    let shift = 31 - truncated.leadingZeroBitCount
    let mask = Int32(bitPattern: UInt32(0xFFFF_FFFF) << shift)
    return Int(truncated & mask)
}

@_cdecl("kk_int_takeLowestOneBit")
public func kk_int_takeLowestOneBit(_ value: Int) -> Int {
    kk_int_lowestOneBit(value)
}

// Long bit manipulation functions (64-bit)

@_cdecl("kk_long_rotateLeft")
public func kk_long_rotateLeft(_ value: Int, _ distance: Int) -> Int {
    let u = UInt(bitPattern: value)
    let d = UInt(truncatingIfNeeded: distance) & 63
    guard d != 0 else { return value }
    return Int(bitPattern: (u << d) | (u >> (64 - d)))
}

@_cdecl("kk_long_rotateRight")
public func kk_long_rotateRight(_ value: Int, _ distance: Int) -> Int {
    let u = UInt(bitPattern: value)
    let d = UInt(truncatingIfNeeded: distance) & 63
    guard d != 0 else { return value }
    return Int(bitPattern: (u >> d) | (u << (64 - d)))
}

@_cdecl("kk_long_highestOneBit")
public func kk_long_highestOneBit(_ value: Int) -> Int {
    if value == 0 { return 0 }
    return 1 << (63 - value.leadingZeroBitCount)
}

@_cdecl("kk_long_lowestOneBit")
public func kk_long_lowestOneBit(_ value: Int) -> Int {
    let bits = UInt(bitPattern: value)
    if bits == 0 { return 0 }
    return Int(bitPattern: bits & (0 &- bits))
}

@_cdecl("kk_long_takeHighestOneBit")
public func kk_long_takeHighestOneBit(_ value: Int) -> Int {
    if value == 0 { return 0 }
    let shift = 63 - value.leadingZeroBitCount
    return value & (~0 << shift)
}

@_cdecl("kk_long_takeLowestOneBit")
public func kk_long_takeLowestOneBit(_ value: Int) -> Int {
    kk_long_lowestOneBit(value)
}

@_cdecl("kk_int_coerceIn")
public func kk_int_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    precondition(minimum <= maximum, "Cannot coerce value to an empty range: maximum \(maximum) is less than minimum \(minimum).")
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

// Long coercion (STDLIB-500) — Long uses the same Int representation on 64-bit.
//
// NOTE: All kk_long_* entrypoints take and return Swift `Int` (intptr_t).
// On the current macOS-only 64-bit target Int and Int64 are identical, so
// Kotlin Long (64-bit signed) maps directly to intptr_t without loss.
// If the compiler ever targets 32-bit platforms this assumption must be
// revisited: Long would need a dedicated 64-bit representation distinct
// from the pointer-sized Int used for Kotlin Int.
//
// Compile-time assertion: Long == Int requires 64-bit Int.
#if !arch(arm64) && !arch(x86_64)
    #error("KSwiftK runtime requires a 64-bit platform where Int == Int64.")
#endif

@_cdecl("kk_long_coerceIn")
public func kk_long_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    precondition(minimum <= maximum, "Cannot coerce value to an empty range: maximum \(maximum) is less than minimum \(minimum).")
    if value < minimum { return minimum }
    if value > maximum { return maximum }
    return value
}

@_cdecl("kk_long_coerceAtLeast")
public func kk_long_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    value < minimum ? minimum : value
}

@_cdecl("kk_long_coerceAtMost")
public func kk_long_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    value > maximum ? maximum : value
}

/// Double coercion (STDLIB-500) — values passed as bit-encoded intptr_t.
@_cdecl("kk_double_coerceIn")
public func kk_double_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    let v = kk_bits_to_double(value)
    let lo = kk_bits_to_double(minimum)
    let hi = kk_bits_to_double(maximum)
    precondition(!(lo > hi), "Cannot coerce value to an empty range: maximum \(hi) is less than minimum \(lo).")
    if v < lo { return minimum }
    if v > hi { return maximum }
    return value
}

@_cdecl("kk_double_coerceAtLeast")
public func kk_double_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    let v = kk_bits_to_double(value)
    let lo = kk_bits_to_double(minimum)
    return v < lo ? minimum : value
}

@_cdecl("kk_double_coerceAtMost")
public func kk_double_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    let v = kk_bits_to_double(value)
    let hi = kk_bits_to_double(maximum)
    return v > hi ? maximum : value
}

/// Float coercion (STDLIB-500) — values passed as bit-encoded intptr_t.
@_cdecl("kk_float_coerceIn")
public func kk_float_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    let v = kk_bits_to_float(value)
    let lo = kk_bits_to_float(minimum)
    let hi = kk_bits_to_float(maximum)
    precondition(!(lo > hi), "Cannot coerce value to an empty range: maximum \(hi) is less than minimum \(lo).")
    if v < lo { return minimum }
    if v > hi { return maximum }
    return value
}

@_cdecl("kk_float_coerceAtLeast")
public func kk_float_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    let v = kk_bits_to_float(value)
    let lo = kk_bits_to_float(minimum)
    return v < lo ? minimum : value
}

@_cdecl("kk_float_coerceAtMost")
public func kk_float_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    let v = kk_bits_to_float(value)
    let hi = kk_bits_to_float(maximum)
    return v > hi ? maximum : value
}

// Unsigned coercion helpers compare the raw intptr_t payload as UInt so the
// runtime preserves the bit pattern for UByte/UShort/UInt/ULong values.
@inline(__always)
private func runtimeUnsignedCoerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    let v = UInt(bitPattern: value)
    let lo = UInt(bitPattern: minimum)
    let hi = UInt(bitPattern: maximum)
    precondition(!(lo > hi), "Cannot coerce value to an empty range: maximum \(hi) is less than minimum \(lo).")
    if v < lo { return minimum }
    if v > hi { return maximum }
    return value
}

@inline(__always)
private func runtimeUnsignedCoerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    UInt(bitPattern: value) < UInt(bitPattern: minimum) ? minimum : value
}

@inline(__always)
private func runtimeUnsignedCoerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    UInt(bitPattern: value) > UInt(bitPattern: maximum) ? maximum : value
}

@_cdecl("kk_ubyte_coerceIn")
public func kk_ubyte_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ubyte_coerceAtLeast")
public func kk_ubyte_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ubyte_coerceAtMost")
public func kk_ubyte_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_ushort_coerceIn")
public func kk_ushort_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ushort_coerceAtLeast")
public func kk_ushort_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ushort_coerceAtMost")
public func kk_ushort_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_uint_coerceIn")
public func kk_uint_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_uint_coerceAtLeast")
public func kk_uint_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_uint_coerceAtMost")
public func kk_uint_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_ulong_coerceIn")
public func kk_ulong_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ulong_coerceAtLeast")
public func kk_ulong_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ulong_coerceAtMost")
public func kk_ulong_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

