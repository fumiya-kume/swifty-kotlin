package kotlin.math

import kotlin.comparisons.maxOf
import kotlin.comparisons.minOf
import kotlin.fromBits
import kotlin.internal.KsSymbolName

// KSP-635
// abs / sign / min / max and the PI / E constants migrated from the synthetic
// stubs in Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift
// and the kk_math_abs*/kk_math_sign*/kk_math_min*/kk_math_max*/kk_math_PI/kk_math_E
// entry points in Sources/Runtime/RuntimeNumericCompat.swift.
//
// The floating-point min/max delegate to kotlin.comparisons.maxOf/minOf, which
// already own the NaN propagation and signed-zero ordering contract; everything
// else is expressible without touching the runtime.

/** Ratio of the circumference of a circle to its diameter, approximately 3.14159. */
@SinceKotlin("1.2")
public const val PI: Double = 3.141592653589793
@SinceKotlin("1.2")
public const val E: Double = 2.718281828459045

// `0.0 - x` (rather than `-x`) normalizes -0.0 to +0.0 while leaving NaN and
// the infinities untouched. abs(Int.MIN_VALUE) / abs(Long.MIN_VALUE) overflow
// back to the same value, matching Kotlin.

public fun abs(n: Int): Int = if (n < 0) -n else n

public fun abs(n: Long): Long = if (n < 0L) -n else n

public fun abs(x: Double): Double = if (x <= 0.0) 0.0 - x else x

public fun abs(x: Float): Float = if (x <= 0.0f) 0.0f - x else x

public val Int.absoluteValue: Int get() = abs(this)

public val Long.absoluteValue: Long get() = abs(this)

public val Double.absoluteValue: Double get() = abs(this)

public val Float.absoluteValue: Float get() = abs(this)

// NaN falls through to the final branch and is returned as-is, and ±0.0 keeps
// its own sign, as specified for Math.signum.

public fun sign(x: Double): Double = if (x > 0.0) 1.0 else if (x < 0.0) -1.0 else x

public fun sign(x: Float): Float = if (x > 0.0f) 1.0f else if (x < 0.0f) -1.0f else x

public val Double.sign: Double get() = if (this > 0.0) 1.0 else if (this < 0.0) -1.0 else this

public val Float.sign: Float get() = if (this > 0.0f) 1.0f else if (this < 0.0f) -1.0f else this

public val Int.sign: Int get() = if (this > 0) 1 else if (this < 0) -1 else 0

public val Long.sign: Int get() = if (this > 0L) 1 else if (this < 0L) -1 else 0

public fun max(a: Int, b: Int): Int = maxOf(a, b)

public fun max(a: Long, b: Long): Long = maxOf(a, b)

public fun max(a: Float, b: Float): Float = maxOf(a, b)

public fun max(a: Double, b: Double): Double = maxOf(a, b)

public fun max(a: UInt, b: UInt): UInt = maxOf(a, b)

public fun max(a: ULong, b: ULong): ULong = maxOf(a, b)

public fun min(a: Int, b: Int): Int = minOf(a, b)

public fun min(a: Long, b: Long): Long = minOf(a, b)

public fun min(a: Float, b: Float): Float = minOf(a, b)

public fun min(a: Double, b: Double): Double = minOf(a, b)

public fun min(a: UInt, b: UInt): UInt = minOf(a, b)

public fun min(a: ULong, b: ULong): ULong = minOf(a, b)

// KSP-636
// ceil / floor / round / truncate and withSign migrated from the synthetic
// stubs in Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift
// and the kk_math_* entry points in Sources/Runtime/RuntimeNumericCompat.swift.
//
// Rounding functions still need libm/Foundation, so they are exposed as
// internal __kk_math_* runtime bridges. withSign is pure bit manipulation on
// top of Double/Float.toRawBits and Double/Float.fromBits, so it lives fully
// in Kotlin.

@KsSymbolName("__kk_math_ceil")
internal external fun __kkMathCeil(x: Double): Double

@KsSymbolName("__kk_math_floor")
internal external fun __kkMathFloor(x: Double): Double

@KsSymbolName("__kk_math_round")
internal external fun __kkMathRound(x: Double): Double

@KsSymbolName("__kk_math_truncate")
internal external fun __kkMathTruncate(x: Double): Double

@KsSymbolName("__kk_math_ceil_float")
internal external fun __kkMathCeilFloat(x: Float): Float

@KsSymbolName("__kk_math_floor_float")
internal external fun __kkMathFloorFloat(x: Float): Float

@KsSymbolName("__kk_math_round_float")
internal external fun __kkMathRoundFloat(x: Float): Float

@KsSymbolName("__kk_math_truncate_float")
internal external fun __kkMathTruncateFloat(x: Float): Float

public fun ceil(x: Double): Double = __kkMathCeil(x)

public fun floor(x: Double): Double = __kkMathFloor(x)

public fun round(x: Double): Double = __kkMathRound(x)

public fun truncate(x: Double): Double = __kkMathTruncate(x)

public fun ceil(x: Float): Float = __kkMathCeilFloat(x)

public fun floor(x: Float): Float = __kkMathFloorFloat(x)

public fun round(x: Float): Float = __kkMathRoundFloat(x)

public fun truncate(x: Float): Float = __kkMathTruncateFloat(x)

public fun Double.withSign(sign: Double): Double {
    val xBits = this.toRawBits()
    val signBit = sign.toRawBits() and Long.MIN_VALUE
    val mag = xBits and Long.MAX_VALUE
    return fromBits(mag or signBit)
}

public fun Double.withSign(sign: Int): Double =
    if (sign < 0) -abs(this) else abs(this)

public fun Float.withSign(sign: Float): Float {
    val xBits = this.toRawBits()
    val signBit = sign.toRawBits() and Int.MIN_VALUE
    val mag = xBits and Int.MAX_VALUE
    return fromBits(mag or signBit)
}

public fun Float.withSign(sign: Int): Float =
    if (sign < 0) -abs(this) else abs(this)

// KSP-637 & KSP-638
// Transcendental kotlin.math functions are Kotlin-source public wrappers around
// internal libm entry points. Keeping the bridge declarations private to the
// bundled source prevents the native ABI names from becoming public stdlib
// symbols while preserving the platform math implementation and its edge cases.
//
// roundToInt / roundToLong / ulp / nextUp / nextDown are Kotlin-source
// surface declarations. Their native implementations remain bridges because
// rounding must preserve Kotlin's NaN exception and saturation contract, while
// the precision helpers operate on IEEE 754 bit patterns.

@KsSymbolName("__kk_math_sqrt")
internal external fun __kkMathSqrt(x: Double): Double

@KsSymbolName("__kk_math_sqrt_float")
internal external fun __kkMathSqrtFloat(x: Float): Float

@KsSymbolName("__kk_math_pow")
internal external fun __kkMathPow(x: Double, y: Double): Double

@KsSymbolName("__kk_math_pow_float")
internal external fun __kkMathPowFloat(x: Float, y: Float): Float

@KsSymbolName("__kk_math_pow_int")
internal external fun __kkMathPowInt(x: Double, n: Int): Double

@KsSymbolName("__kk_math_pow_float_int")
internal external fun __kkMathPowFloatInt(x: Float, n: Int): Float

@KsSymbolName("__kk_math_IEEErem")
internal external fun __kkMathIEEErem(x: Double, divisor: Double): Double

@KsSymbolName("__kk_math_IEEErem_float")
internal external fun __kkMathIEEEremFloat(x: Float, divisor: Float): Float

@KsSymbolName("__kk_math_nextTowards")
internal external fun __kkMathNextTowards(x: Double, to: Double): Double

@KsSymbolName("__kk_math_nextTowards_float")
internal external fun __kkMathNextTowardsFloat(x: Float, to: Float): Float

@KsSymbolName("__kk_math_sin")
internal external fun __kkMathSin(x: Double): Double

@KsSymbolName("__kk_math_cos")
internal external fun __kkMathCos(x: Double): Double

@KsSymbolName("__kk_math_tan")
internal external fun __kkMathTan(x: Double): Double

@KsSymbolName("__kk_math_asin")
internal external fun __kkMathAsin(x: Double): Double

@KsSymbolName("__kk_math_acos")
internal external fun __kkMathAcos(x: Double): Double

@KsSymbolName("__kk_math_atan")
internal external fun __kkMathAtan(x: Double): Double

@KsSymbolName("__kk_math_atan2")
internal external fun __kkMathAtan2(y: Double, x: Double): Double

@KsSymbolName("__kk_math_exp")
internal external fun __kkMathExp(x: Double): Double

@KsSymbolName("__kk_math_expm1")
internal external fun __kkMathExpm1(x: Double): Double

@KsSymbolName("__kk_math_ln")
internal external fun __kkMathLn(x: Double): Double

@KsSymbolName("__kk_math_ln1p")
internal external fun __kkMathLn1p(x: Double): Double

@KsSymbolName("__kk_math_log2")
internal external fun __kkMathLog2(x: Double): Double

@KsSymbolName("__kk_math_log10")
internal external fun __kkMathLog10(x: Double): Double

@KsSymbolName("__kk_math_log")
internal external fun __kkMathLog(x: Double, base: Double): Double

@KsSymbolName("__kk_math_sinh")
internal external fun __kkMathSinh(x: Double): Double

@KsSymbolName("__kk_math_cosh")
internal external fun __kkMathCosh(x: Double): Double

@KsSymbolName("__kk_math_tanh")
internal external fun __kkMathTanh(x: Double): Double

@KsSymbolName("__kk_math_acosh")
internal external fun __kkMathAcosh(x: Double): Double

@KsSymbolName("__kk_math_asinh")
internal external fun __kkMathAsinh(x: Double): Double

@KsSymbolName("__kk_math_atanh")
internal external fun __kkMathAtanh(x: Double): Double

@KsSymbolName("__kk_math_cbrt")
internal external fun __kkMathCbrt(x: Double): Double

@KsSymbolName("__kk_math_hypot")
internal external fun __kkMathHypot(x: Double, y: Double): Double

@KsSymbolName("__kk_math_sin_float")
internal external fun __kkMathSinFloat(x: Float): Float

@KsSymbolName("__kk_math_cos_float")
internal external fun __kkMathCosFloat(x: Float): Float

@KsSymbolName("__kk_math_tan_float")
internal external fun __kkMathTanFloat(x: Float): Float

@KsSymbolName("__kk_math_asin_float")
internal external fun __kkMathAsinFloat(x: Float): Float

@KsSymbolName("__kk_math_acos_float")
internal external fun __kkMathAcosFloat(x: Float): Float

@KsSymbolName("__kk_math_atan_float")
internal external fun __kkMathAtanFloat(x: Float): Float

@KsSymbolName("__kk_math_atan2_float")
internal external fun __kkMathAtan2Float(y: Float, x: Float): Float

@KsSymbolName("__kk_math_exp_float")
internal external fun __kkMathExpFloat(x: Float): Float

@KsSymbolName("__kk_math_expm1_float")
internal external fun __kkMathExpm1Float(x: Float): Float

@KsSymbolName("__kk_math_ln_float")
internal external fun __kkMathLnFloat(x: Float): Float

@KsSymbolName("__kk_math_ln1p_float")
internal external fun __kkMathLn1pFloat(x: Float): Float

@KsSymbolName("__kk_math_log2_float")
internal external fun __kkMathLog2Float(x: Float): Float

@KsSymbolName("__kk_math_log10_float")
internal external fun __kkMathLog10Float(x: Float): Float

@KsSymbolName("__kk_math_log_float")
internal external fun __kkMathLogFloat(x: Float, base: Float): Float

@KsSymbolName("__kk_math_sinh_float")
internal external fun __kkMathSinhFloat(x: Float): Float

@KsSymbolName("__kk_math_cosh_float")
internal external fun __kkMathCoshFloat(x: Float): Float

@KsSymbolName("__kk_math_tanh_float")
internal external fun __kkMathTanhFloat(x: Float): Float

@KsSymbolName("__kk_math_acosh_float")
internal external fun __kkMathAcoshFloat(x: Float): Float

@KsSymbolName("__kk_math_asinh_float")
internal external fun __kkMathAsinhFloat(x: Float): Float

@KsSymbolName("__kk_math_atanh_float")
internal external fun __kkMathAtanhFloat(x: Float): Float

@KsSymbolName("__kk_math_cbrt_float")
internal external fun __kkMathCbrtFloat(x: Float): Float

@KsSymbolName("__kk_math_hypot_float")
internal external fun __kkMathHypotFloat(x: Float, y: Float): Float

@KsSymbolName("__kk_float_roundToInt")
internal external fun __kkFloatRoundToInt(x: Float): Int

@KsSymbolName("__kk_double_roundToInt")
internal external fun __kkDoubleRoundToInt(x: Double): Int

@KsSymbolName("__kk_float_roundToLong")
internal external fun __kkFloatRoundToLong(x: Float): Long

@KsSymbolName("__kk_double_roundToLong")
internal external fun __kkDoubleRoundToLong(x: Double): Long

@KsSymbolName("__kk_double_ulp")
internal external fun __kkDoubleUlp(x: Double): Double

@KsSymbolName("__kk_float_ulp")
internal external fun __kkFloatUlp(x: Float): Float

@KsSymbolName("__kk_double_nextUp")
internal external fun __kkDoubleNextUp(x: Double): Double

@KsSymbolName("__kk_float_nextUp")
internal external fun __kkFloatNextUp(x: Float): Float

@KsSymbolName("__kk_double_nextDown")
internal external fun __kkDoubleNextDown(x: Double): Double

@KsSymbolName("__kk_float_nextDown")
internal external fun __kkFloatNextDown(x: Float): Float

public fun sqrt(x: Double): Double = __kkMathSqrt(x)

public fun Double.pow(x: Double): Double = __kkMathPow(this, x)

public fun Double.pow(n: Int): Double = __kkMathPowInt(this, n)

public fun Double.IEEErem(divisor: Double): Double = __kkMathIEEErem(this, divisor)

public fun Double.nextTowards(to: Double): Double = __kkMathNextTowards(this, to)

public fun sin(x: Double): Double = __kkMathSin(x)

public fun cos(x: Double): Double = __kkMathCos(x)

public fun tan(x: Double): Double = __kkMathTan(x)

public fun asin(x: Double): Double = __kkMathAsin(x)

public fun acos(x: Double): Double = __kkMathAcos(x)

public fun atan(x: Double): Double = __kkMathAtan(x)

public fun atan2(y: Double, x: Double): Double = __kkMathAtan2(y, x)

public fun exp(x: Double): Double = __kkMathExp(x)

public fun expm1(x: Double): Double = __kkMathExpm1(x)

public fun ln(x: Double): Double = __kkMathLn(x)

public fun ln1p(x: Double): Double = __kkMathLn1p(x)

public fun log2(x: Double): Double = __kkMathLog2(x)

public fun log10(x: Double): Double = __kkMathLog10(x)

public fun log(x: Double, base: Double): Double = __kkMathLog(x, base)

public fun sinh(x: Double): Double = __kkMathSinh(x)

public fun cosh(x: Double): Double = __kkMathCosh(x)

public fun tanh(x: Double): Double = __kkMathTanh(x)

public fun acosh(x: Double): Double = __kkMathAcosh(x)

public fun asinh(x: Double): Double = __kkMathAsinh(x)

public fun atanh(x: Double): Double = __kkMathAtanh(x)

public fun cbrt(x: Double): Double = __kkMathCbrt(x)

public fun hypot(x: Double, y: Double): Double = __kkMathHypot(x, y)

public fun sqrt(x: Float): Float = __kkMathSqrtFloat(x)

public fun Float.pow(x: Float): Float = __kkMathPowFloat(this, x)

public fun Float.pow(n: Int): Float = __kkMathPowFloatInt(this, n)

public fun Float.IEEErem(divisor: Float): Float = __kkMathIEEEremFloat(this, divisor)

public fun Float.nextTowards(to: Float): Float = __kkMathNextTowardsFloat(this, to)

public fun sin(x: Float): Float = __kkMathSinFloat(x)

public fun cos(x: Float): Float = __kkMathCosFloat(x)

public fun tan(x: Float): Float = __kkMathTanFloat(x)

public fun asin(x: Float): Float = __kkMathAsinFloat(x)

public fun acos(x: Float): Float = __kkMathAcosFloat(x)

public fun atan(x: Float): Float = __kkMathAtanFloat(x)

public fun atan2(y: Float, x: Float): Float = __kkMathAtan2Float(y, x)

public fun exp(x: Float): Float = __kkMathExpFloat(x)

public fun expm1(x: Float): Float = __kkMathExpm1Float(x)

public fun ln(x: Float): Float = __kkMathLnFloat(x)

public fun ln1p(x: Float): Float = __kkMathLn1pFloat(x)

public fun log2(x: Float): Float = __kkMathLog2Float(x)

public fun log10(x: Float): Float = __kkMathLog10Float(x)

public fun log(x: Float, base: Float): Float = __kkMathLogFloat(x, base)

public fun sinh(x: Float): Float = __kkMathSinhFloat(x)

public fun cosh(x: Float): Float = __kkMathCoshFloat(x)

public fun tanh(x: Float): Float = __kkMathTanhFloat(x)

public fun acosh(x: Float): Float = __kkMathAcoshFloat(x)

public fun asinh(x: Float): Float = __kkMathAsinhFloat(x)

public fun atanh(x: Float): Float = __kkMathAtanhFloat(x)

public fun cbrt(x: Float): Float = __kkMathCbrtFloat(x)

public fun hypot(x: Float, y: Float): Float = __kkMathHypotFloat(x, y)

public fun Float.roundToInt(): Int = __kkFloatRoundToInt(this)

public fun Double.roundToInt(): Int = __kkDoubleRoundToInt(this)

public fun Float.roundToLong(): Long = __kkFloatRoundToLong(this)

public fun Double.roundToLong(): Long = __kkDoubleRoundToLong(this)

public val Double.ulp: Double get() = __kkDoubleUlp(this)

public val Float.ulp: Float get() = __kkFloatUlp(this)

public fun Double.nextUp(): Double = __kkDoubleNextUp(this)

public fun Float.nextUp(): Float = __kkFloatNextUp(this)

public fun Double.nextDown(): Double = __kkDoubleNextDown(this)

public fun Float.nextDown(): Float = __kkFloatNextDown(this)
