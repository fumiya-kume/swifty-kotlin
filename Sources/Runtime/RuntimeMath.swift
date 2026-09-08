
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
//
// Most companion-object constants (infinities, NaN) are
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
