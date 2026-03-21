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

/// Encode a Float's IEEE 754 bit pattern into an Int for transport across the
/// C ABI boundary. Uses `bitPattern`-based (non-trapping) conversions throughout,
/// mirroring `kk_double_to_bits`. On 64-bit platforms `UInt(UInt32)` zero-extends;
/// on a hypothetical 32-bit target the cast is a no-op since UInt32 == UInt.
@_cdecl("kk_float_to_bits")
public func kk_float_to_bits(_ value: Float) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
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
    // Range expressions (LongRange) are typed as Long in sema but produce
    // opaque runtime object handles.  Detect that case and render via
    // runtimeElementToString so that "println(1L..10L)" prints "1..10".
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObj = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObj, tryCast(ptr, to: RuntimeRangeBox.self) != nil {
            Swift.print(runtimeElementToString(value))
            return
        }
    }
    Swift.print(value)
}

@_cdecl("kk_println_ulong")
public func kk_println_ulong(_ value: Int) {
    Swift.print(UInt(bitPattern: value))
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
    kk_double_to_bits(kk_bits_to_double(value).rounded(.toNearestOrEven))
}

// Trigonometric functions (STDLIB-430)
//
// Architecture assumption: Double bit-pattern transport via Int/intptr_t relies
// on Int being 64-bit (MemoryLayout<Int>.size == 8) so that the full 64-bit
// IEEE 754 payload is preserved. This is true on all Apple Silicon and x86_64
// targets; 32-bit platforms are not supported by this runtime.
//
// Note: Each @_cdecl wrapper is spelled out individually rather than factored
// through a shared closure helper. This repetition is intentional — keeping
// every entry point as a plain, self-contained function ensures the C ABI
// surface is auditable in code review and prevents optimizer surprises from
// indirect-call thunks in hot numeric paths.

@_cdecl("kk_math_sin")
public func kk_math_sin(_ value: Int) -> Int {
    kk_double_to_bits(sin(kk_bits_to_double(value)))
}

@_cdecl("kk_math_cos")
public func kk_math_cos(_ value: Int) -> Int {
    kk_double_to_bits(cos(kk_bits_to_double(value)))
}

@_cdecl("kk_math_tan")
public func kk_math_tan(_ value: Int) -> Int {
    kk_double_to_bits(tan(kk_bits_to_double(value)))
}

@_cdecl("kk_math_asin")
public func kk_math_asin(_ value: Int) -> Int {
    kk_double_to_bits(asin(kk_bits_to_double(value)))
}

@_cdecl("kk_math_acos")
public func kk_math_acos(_ value: Int) -> Int {
    kk_double_to_bits(acos(kk_bits_to_double(value)))
}

@_cdecl("kk_math_atan")
public func kk_math_atan(_ value: Int) -> Int {
    kk_double_to_bits(atan(kk_bits_to_double(value)))
}

@_cdecl("kk_math_atan2")
public func kk_math_atan2(_ y: Int, _ x: Int) -> Int {
    kk_double_to_bits(atan2(kk_bits_to_double(y), kk_bits_to_double(x)))
}

// MARK: - STDLIB-431: exp/ln/log functions

@_cdecl("kk_math_exp")
public func kk_math_exp(_ value: Int) -> Int {
    kk_double_to_bits(exp(kk_bits_to_double(value)))
}

@_cdecl("kk_math_ln")
public func kk_math_ln(_ value: Int) -> Int {
    kk_double_to_bits(log(kk_bits_to_double(value)))
}

@_cdecl("kk_math_log2")
public func kk_math_log2(_ value: Int) -> Int {
    kk_double_to_bits(log2(kk_bits_to_double(value)))
}

@_cdecl("kk_math_log10")
public func kk_math_log10(_ value: Int) -> Int {
    kk_double_to_bits(log10(kk_bits_to_double(value)))
}

@_cdecl("kk_math_log")
public func kk_math_log(_ x: Int, _ base: Int) -> Int {
    let rawX = kk_bits_to_double(x)
    let rawBase = kk_bits_to_double(base)
    return kk_double_to_bits(log(rawX) / log(rawBase))
}

// MARK: - STDLIB-432: sign/hypot + PI/E constants

@_cdecl("kk_math_sign")
public func kk_math_sign(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return kk_double_to_bits(Double.nan) }
    if d > 0 { return kk_double_to_bits(1.0) }
    if d < 0 { return kk_double_to_bits(-1.0) }
    // Preserve sign of zero: return the original value for +0.0 / -0.0
    return value
}

@_cdecl("kk_math_hypot")
public func kk_math_hypot(_ x: Int, _ y: Int) -> Int {
    let rawX = kk_bits_to_double(x)
    let rawY = kk_bits_to_double(y)
    return kk_double_to_bits(hypot(rawX, rawY))
}

@_cdecl("kk_math_PI")
public func kk_math_PI() -> Int {
    kk_double_to_bits(Double.pi)
}

@_cdecl("kk_math_E")
public func kk_math_E() -> Int {
    kk_double_to_bits(M_E)
}

// MARK: - STDLIB-500~509: Float trig/math overloads
//
// Float values are transported as bit-encoded Int (intptr_t), just like Double.
// The low 32 bits carry the IEEE 754 single-precision payload; upper bits are
// ignored on decode and zero-extended on encode.

/// Helper: decode bit-encoded Float, apply a unary operation, re-encode.
/// Reduces boilerplate across the Float math entry points below.
private func applyFloatUnaryOp(_ v: Int, _ op: (Float) -> Float) -> Int {
    kk_float_to_bits(op(kk_bits_to_float(v)))
}

@_cdecl("kk_math_sin_float")
public func kk_math_sin_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, sinf)
}

@_cdecl("kk_math_cos_float")
public func kk_math_cos_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, cosf)
}

@_cdecl("kk_math_tan_float")
public func kk_math_tan_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, tanf)
}

@_cdecl("kk_math_asin_float")
public func kk_math_asin_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, asinf)
}

@_cdecl("kk_math_acos_float")
public func kk_math_acos_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, acosf)
}

@_cdecl("kk_math_atan_float")
public func kk_math_atan_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, atanf)
}

@_cdecl("kk_math_atan2_float")
public func kk_math_atan2_float(_ y: Int, _ x: Int) -> Int {
    let fy = kk_bits_to_float(y)
    let fx = kk_bits_to_float(x)
    return kk_float_to_bits(atan2f(fy, fx))
}

@_cdecl("kk_math_sqrt_float")
public func kk_math_sqrt_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, sqrtf)
}

@_cdecl("kk_math_round_float")
public func kk_math_round_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v) { $0.rounded(.toNearestOrEven) }
}

@_cdecl("kk_math_ceil_float")
public func kk_math_ceil_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, ceilf)
}

@_cdecl("kk_math_floor_float")
public func kk_math_floor_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, floorf)
}

// MARK: - STDLIB-430: additional Float overloads (abs, exp, ln, log2, log10, log, sign, hypot)

@_cdecl("kk_math_abs_float")
public func kk_math_abs_float(_ value: Int) -> Int {
    kk_float_to_bits(Swift.abs(kk_bits_to_float(value)))
}

@_cdecl("kk_math_exp_float")
public func kk_math_exp_float(_ value: Int) -> Int {
    kk_float_to_bits(exp(kk_bits_to_float(value)))
}

@_cdecl("kk_math_ln_float")
public func kk_math_ln_float(_ value: Int) -> Int {
    kk_float_to_bits(log(kk_bits_to_float(value)))
}

@_cdecl("kk_math_log2_float")
public func kk_math_log2_float(_ value: Int) -> Int {
    kk_float_to_bits(log2(kk_bits_to_float(value)))
}

@_cdecl("kk_math_log10_float")
public func kk_math_log10_float(_ value: Int) -> Int {
    kk_float_to_bits(log10(kk_bits_to_float(value)))
}

@_cdecl("kk_math_log_float")
public func kk_math_log_float(_ x: Int, _ base: Int) -> Int {
    let rawX = kk_bits_to_float(x)
    let rawBase = kk_bits_to_float(base)
    return kk_float_to_bits(log(rawX) / log(rawBase))
}

@_cdecl("kk_math_sign_float")
public func kk_math_sign_float(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return kk_float_to_bits(Float.nan) }
    if f > 0 { return kk_float_to_bits(1.0) }
    if f < 0 { return kk_float_to_bits(-1.0) }
    // Preserve sign of zero: return the original value for +0.0 / -0.0
    return value
}

@_cdecl("kk_math_hypot_float")
public func kk_math_hypot_float(_ x: Int, _ y: Int) -> Int {
    let rawX = kk_bits_to_float(x)
    let rawY = kk_bits_to_float(y)
    return kk_float_to_bits(hypot(rawX, rawY))
}

// MARK: - STDLIB-510~511: roundToInt / roundToLong extensions

// Kotlin's roundToInt/roundToLong use Math.round() semantics: ties round
// towards positive infinity. For Float and Double, we use bit-manipulation
// algorithms matching Java 7+ Math.round(...) to avoid precision loss from
// floor(x + 0.5) near half-integer boundaries (JDK-6430675).

/// Bit-manipulation rounding for Float matching Java 7+ Math.round(float).
/// Avoids the precision loss of `floorf(raw + 0.5)` for values just below
/// half-integer boundaries (e.g. Float(bitPattern: 0x3EFFFFFF) ~ 0.49999997).
private func roundFloatJava7(_ raw: Float) -> Int64 {
    let bits = raw.bitPattern
    let biasedExp = Int((bits >> 23) & 0xFF)
    let shift = 149 - biasedExp  // (23 - 1 + 127) - biasedExp
    if (shift & ~31) == 0 {  // 0 <= shift <= 31
        var r = Int32(bitPattern: (bits & 0x7F_FFFF) | 0x80_0000)
        if Int32(bitPattern: bits) < 0 { r = -r }
        return Int64((r >> shift) &+ 1) >> 1
    } else {
        // Exponent too small (magnitude < 0.5 → 0) or too large (already integral)
        if raw >= Float(Int64.max) { return Int64.max }
        if raw <= Float(Int64.min) { return Int64.min }
        return Int64(raw)
    }
}

/// Bit-manipulation rounding for Double matching Java 7+ Math.round(double).
/// Avoids the precision loss of `floor(raw + 0.5)` for values just below
/// half-integer boundaries (e.g. 0.49999999999999994).
private func roundDoubleJava7(_ raw: Double) -> Int64 {
    let bits = raw.bitPattern
    let biasedExp = Int((bits >> 52) & 0x7FF)
    let shift = 1074 - biasedExp  // (52 - 1 + 1023) - biasedExp
    if (shift & ~63) == 0 {  // 0 <= shift <= 63
        var r = Int64(bitPattern: (bits & 0xF_FFFF_FFFF_FFFF) | 0x10_0000_0000_0000)
        if Int64(bitPattern: bits) < 0 { r = -r }
        return ((r >> shift) &+ 1) >> 1
    } else {
        if raw >= Double(Int64.max) { return Int64.max }
        if raw <= Double(Int64.min) { return Int64.min }
        return Int64(raw)
    }
}

@_cdecl("kk_float_roundToInt")
public func kk_float_roundToInt(_ value: Int) -> Int {
    let raw = kk_bits_to_float(value)
    if raw.isNaN { return 0 }
    let r = roundFloatJava7(raw)
    if r >= Int64(Int32.max) { return Int(Int32.max) }
    if r <= Int64(Int32.min) { return Int(Int32.min) }
    return Int(Int32(r))
}

@_cdecl("kk_double_roundToInt")
public func kk_double_roundToInt(_ value: Int) -> Int {
    let raw = kk_bits_to_double(value)
    if raw.isNaN { return 0 }
    let r = roundDoubleJava7(raw)
    if r >= Int64(Int32.max) { return Int(Int32.max) }
    if r <= Int64(Int32.min) { return Int(Int32.min) }
    return Int(Int32(r))
}

@_cdecl("kk_float_roundToLong")
public func kk_float_roundToLong(_ value: Int) -> Int {
    let raw = kk_bits_to_float(value)
    if raw.isNaN { return 0 }
    let r = roundFloatJava7(raw)
    if r >= Int64.max { return Int(Int64.max) }
    if r <= Int64.min { return Int(Int64.min) }
    return Int(r)
}

@_cdecl("kk_double_roundToLong")
public func kk_double_roundToLong(_ value: Int) -> Int {
    let raw = kk_bits_to_double(value)
    if raw.isNaN { return 0 }
    let r = roundDoubleJava7(raw)
    if r >= Int64.max { return Int(Int64.max) }
    if r <= Int64.min { return Int(Int64.min) }
    return Int(r)
}

// MARK: - STDLIB-512~513: ulp / nextUp / nextDown extensions

@_cdecl("kk_double_ulp")
public func kk_double_ulp(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).ulp)
}

@_cdecl("kk_double_nextUp")
public func kk_double_nextUp(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).nextUp)
}

@_cdecl("kk_double_nextDown")
public func kk_double_nextDown(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).nextDown)
}

@_cdecl("kk_float_ulp")
public func kk_float_ulp(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).ulp)
}

@_cdecl("kk_float_nextUp")
public func kk_float_nextUp(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).nextUp)
}

@_cdecl("kk_float_nextDown")
public func kk_float_nextDown(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).nextDown)
}

@_cdecl("kk_println_char")
public func kk_println_char(_ value: Int) {
    let unboxed = kk_unbox_char(value)
    if let scalar = UnicodeScalar(unboxed) {
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

@_cdecl("kk_op_not")
public func kk_op_not(_ value: Int) -> Int {
    value == 0 ? 1 : 0
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

// Long→* conversions: `Int` (intptr_t) is used for Long values.
// This is correct on 64-bit macOS where Int == Int64; see the note above
// kk_long_coerceIn for the full rationale.
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

// Kotlin Int is 32-bit; the runtime stores it sign-extended in a 64-bit word.
// Truncate to Int32 before querying bit properties so results match Kotlin semantics
// (e.g. (-1).countOneBits() == 32, not 64).
@_cdecl("kk_int_countOneBits")
public func kk_int_countOneBits(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value).nonzeroBitCount)
}

@_cdecl("kk_int_countLeadingZeroBits")
public func kk_int_countLeadingZeroBits(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value).leadingZeroBitCount)
}

@_cdecl("kk_int_countTrailingZeroBits")
public func kk_int_countTrailingZeroBits(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value).trailingZeroBitCount)
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

// Double coercion (STDLIB-500) — values passed as bit-encoded intptr_t.
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

// Float coercion (STDLIB-500) — values passed as bit-encoded intptr_t.
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
