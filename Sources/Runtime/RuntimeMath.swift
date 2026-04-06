import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - STDLIB-MATH-112: Math constants complete implementation
//
// Runtime entry points for Kotlin math constants. These are the complete set of
// numeric constants exposed by Kotlin's standard library:
//   - kotlin.math.PI, kotlin.math.E  (top-level math package constants)
//   - Double companion object constants: POSITIVE_INFINITY, NEGATIVE_INFINITY,
//     NaN, MAX_VALUE, MIN_VALUE
//   - Int companion object constants:  MAX_VALUE, MIN_VALUE
//   - Long companion object constants: MAX_VALUE, MIN_VALUE
//
// Most companion-object constants (Int/Long/Double bounds, infinities, NaN) are
// resolved at compile time as inline literals in CallTypeChecker+MemberCallInference.swift
// and never require a runtime call. The functions below serve as fallback runtime
// entry points and explicit documentation of all constant values.

// MARK: - Double special-value constants

/// Returns the Double representation of positive infinity.
/// Kotlin: Double.POSITIVE_INFINITY
@_cdecl("kk_double_positive_infinity")
public func kk_double_positive_infinity() -> Int {
    kk_double_to_bits(Double.infinity)
}

/// Returns the Double representation of negative infinity.
/// Kotlin: Double.NEGATIVE_INFINITY
@_cdecl("kk_double_negative_infinity")
public func kk_double_negative_infinity() -> Int {
    kk_double_to_bits(-Double.infinity)
}

/// Returns the Double representation of Not-a-Number.
/// Kotlin: Double.NaN
@_cdecl("kk_double_nan")
public func kk_double_nan() -> Int {
    kk_double_to_bits(Double.nan)
}

/// Returns the largest finite Double value (approximately 1.7976931348623157e+308).
/// Kotlin: Double.MAX_VALUE
@_cdecl("kk_double_max_value")
public func kk_double_max_value() -> Int {
    kk_double_to_bits(Double.greatestFiniteMagnitude)
}

/// Returns the smallest positive non-zero Double value (approximately 5e-324).
/// Kotlin: Double.MIN_VALUE  (note: Kotlin MIN_VALUE = leastNonzeroMagnitude, not -MAX_VALUE)
@_cdecl("kk_double_min_value")
public func kk_double_min_value() -> Int {
    kk_double_to_bits(Double.leastNonzeroMagnitude)
}

// MARK: - Float special-value constants

/// Returns the Float representation of positive infinity.
/// Kotlin: Float.POSITIVE_INFINITY
@_cdecl("kk_float_positive_infinity")
public func kk_float_positive_infinity() -> Int {
    kk_float_to_bits(Float.infinity)
}

/// Returns the Float representation of negative infinity.
/// Kotlin: Float.NEGATIVE_INFINITY
@_cdecl("kk_float_negative_infinity")
public func kk_float_negative_infinity() -> Int {
    kk_float_to_bits(-Float.infinity)
}

/// Returns the Float representation of Not-a-Number.
/// Kotlin: Float.NaN
@_cdecl("kk_float_nan")
public func kk_float_nan() -> Int {
    kk_float_to_bits(Float.nan)
}

/// Returns the largest finite Float value (approximately 3.4028235e+38).
/// Kotlin: Float.MAX_VALUE
@_cdecl("kk_float_max_value")
public func kk_float_max_value() -> Int {
    kk_float_to_bits(Float.greatestFiniteMagnitude)
}

/// Returns the smallest positive non-zero Float value (approximately 1.4e-45).
/// Kotlin: Float.MIN_VALUE  (Kotlin MIN_VALUE = leastNonzeroMagnitude)
@_cdecl("kk_float_min_value")
public func kk_float_min_value() -> Int {
    kk_float_to_bits(Float.leastNonzeroMagnitude)
}

// MARK: - Int companion constants

/// Returns Int.MAX_VALUE (2^31 - 1 = 2147483647).
/// Kotlin: Int.MAX_VALUE
@_cdecl("kk_int_max_value")
public func kk_int_max_value() -> Int {
    return Int(Int32.max)
}

/// Returns Int.MIN_VALUE (-2^31 = -2147483648).
/// Kotlin: Int.MIN_VALUE
@_cdecl("kk_int_min_value")
public func kk_int_min_value() -> Int {
    return Int(Int32.min)
}

// MARK: - Long companion constants

/// Returns Long.MAX_VALUE (2^63 - 1 = 9223372036854775807).
/// Kotlin: Long.MAX_VALUE
@_cdecl("kk_long_max_value")
public func kk_long_max_value() -> Int {
    return Int(Int64.max)
}

/// Returns Long.MIN_VALUE (-2^63 = -9223372036854775808).
/// Kotlin: Long.MIN_VALUE
@_cdecl("kk_long_min_value")
public func kk_long_min_value() -> Int {
    return Int(truncatingIfNeeded: Int64.min)
}

// MARK: - Math constants (kotlin.math.PI, kotlin.math.E)

/// Returns the mathematical constant π (pi).
/// Kotlin: kotlin.math.PI
@_cdecl("kk_math_pi")
public func kk_math_pi() -> Int {
    kk_double_to_bits(Double.pi)
}

/// Returns the mathematical constant e (Euler's number).
/// Kotlin: kotlin.math.E
@_cdecl("kk_math_e")
public func kk_math_e() -> Int {
    kk_double_to_bits(Double(M_E))
}
