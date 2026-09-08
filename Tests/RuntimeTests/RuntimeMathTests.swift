#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

@Suite
struct RuntimeMathTests {
    // MARK: - Double

    @Test func testSqrtDouble() {
        #expect(doubleFromBits(__kk_math_sqrt(doubleToBits(4.0))) == 2.0)
    }

    @Test func testPowDouble() {
        #expect(doubleFromBits(__kk_math_pow(doubleToBits(2.0), doubleToBits(3.0))) == 8.0)
    }

    @Test func testExpm1Double() {
        #expect(abs(doubleFromBits(__kk_math_expm1(doubleToBits(0.0))) - 0.0) <= 1e-12)
        #expect(abs(doubleFromBits(__kk_math_expm1(doubleToBits(1.0))) - expm1(1.0)) <= 1e-12)
    }

    @Test func testLn1pDouble() {
        #expect(abs(doubleFromBits(__kk_math_ln1p(doubleToBits(0.0))) - 0.0) <= 1e-12)
        #expect(abs(doubleFromBits(__kk_math_ln1p(doubleToBits(1.0))) - log1p(1.0)) <= 1e-12)
    }

    @Test func testCeilDouble() {
        #expect(doubleFromBits(__kk_math_ceil(doubleToBits(2.3))) == 3.0)
        #expect(doubleFromBits(__kk_math_ceil(doubleToBits(-2.3))) == -2.0)
    }

    @Test func testFloorDouble() {
        #expect(doubleFromBits(__kk_math_floor(doubleToBits(2.3))) == 2.0)
        #expect(doubleFromBits(__kk_math_floor(doubleToBits(-2.3))) == -3.0)
    }

    @Test func testRoundDouble() {
        // kotlin.math.round uses half-to-even (banker's rounding)
        #expect(doubleFromBits(__kk_math_round(doubleToBits(2.3))) == 2.0)
        #expect(doubleFromBits(__kk_math_round(doubleToBits(2.5))) == 2.0)  // half-to-even: rounds to 2
        #expect(doubleFromBits(__kk_math_round(doubleToBits(3.5))) == 4.0)  // half-to-even: rounds to 4
        #expect(doubleFromBits(__kk_math_round(doubleToBits(-0.5))) == 0.0) // half-to-even: rounds to 0 (not -1)
        #expect(doubleFromBits(__kk_math_round(doubleToBits(Double.nan))).isNaN)
    }

    @Test func testRoundFloat() {
        // kotlin.math.round(Float) also uses half-to-even
        #expect(floatFromBits(__kk_math_round_float(floatToBits(2.3))) == Float(2.0))
        #expect(floatFromBits(__kk_math_round_float(floatToBits(2.5))) == Float(2.0))
        #expect(floatFromBits(__kk_math_round_float(floatToBits(3.5))) == Float(4.0))
        #expect(floatFromBits(__kk_math_round_float(floatToBits(-0.5))) == Float(0.0))
        #expect(floatFromBits(__kk_math_round_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - roundToInt / roundToLong edge cases

    @Test func testFloatRoundToIntEdgeCases() {
        var thrown = 0
        // NaN -> throws IllegalArgumentException (Kotlin contract)
        _ = __kk_float_roundToInt(floatToBits(Float.nan), &thrown)
        #expect(thrown != 0, "roundToInt(NaN) must throw IllegalArgumentException")
        // +Infinity saturates to Int32.max (no throw)
        thrown = 0
        #expect(__kk_float_roundToInt(floatToBits(Float.infinity), &thrown) == Int(Int32.max))
        #expect(thrown == 0, "roundToInt(+Inf) must saturate, not throw")
        // -Infinity saturates to Int32.min
        #expect(__kk_float_roundToInt(floatToBits(-Float.infinity), nil) == Int(Int32.min))
        // Negative tie: -1.5 rounds to -1 (toward +inf), not -2
        #expect(__kk_float_roundToInt(floatToBits(-1.5), nil) == -1)
        // Negative tie: -0.5 rounds to 0 (toward +inf), not -1
        #expect(__kk_float_roundToInt(floatToBits(-0.5), nil) == 0)
        // Positive tie: 0.5 rounds to 1
        #expect(__kk_float_roundToInt(floatToBits(0.5), nil) == 1)
        // Positive tie: 1.5 rounds to 2
        #expect(__kk_float_roundToInt(floatToBits(1.5), nil) == 2)
        // Normal values
        #expect(__kk_float_roundToInt(floatToBits(2.3), nil) == 2)
        #expect(__kk_float_roundToInt(floatToBits(-2.3), nil) == -2)
        // Saturation beyond Int32 bounds
        #expect(__kk_float_roundToInt(floatToBits(Float(3e9)), nil) == Int(Int32.max))
        #expect(__kk_float_roundToInt(floatToBits(Float(-3e9)), nil) == Int(Int32.min))
    }

    @Test func testDoubleRoundToIntEdgeCases() {
        var thrown = 0
        // NaN -> throws IllegalArgumentException (Kotlin contract)
        _ = __kk_double_roundToInt(doubleToBits(Double.nan), &thrown)
        #expect(thrown != 0, "roundToInt(NaN) must throw IllegalArgumentException")
        // +Infinity saturates to Int32.max (no throw)
        thrown = 0
        #expect(__kk_double_roundToInt(doubleToBits(Double.infinity), &thrown) == Int(Int32.max))
        #expect(thrown == 0, "roundToInt(+Inf) must saturate, not throw")
        // -Infinity saturates to Int32.min
        #expect(__kk_double_roundToInt(doubleToBits(-Double.infinity), nil) == Int(Int32.min))
        // Negative tie: -1.5 rounds to -1
        #expect(__kk_double_roundToInt(doubleToBits(-1.5), nil) == -1)
        // Negative tie: -0.5 rounds to 0
        #expect(__kk_double_roundToInt(doubleToBits(-0.5), nil) == 0)
        // Positive tie: 0.5 rounds to 1
        #expect(__kk_double_roundToInt(doubleToBits(0.5), nil) == 1)
        // nextDown(0.5) should round to 0 (not 1)
        #expect(__kk_double_roundToInt(doubleToBits(0.49999999999999994), nil) == 0)
        // Saturation beyond Int32 bounds
        #expect(__kk_double_roundToInt(doubleToBits(3e9), nil) == Int(Int32.max))
        #expect(__kk_double_roundToInt(doubleToBits(-3e9), nil) == Int(Int32.min))
    }

    @Test func testFloatRoundToLongEdgeCases() {
        var thrown = 0
        _ = __kk_float_roundToLong(floatToBits(Float.nan), &thrown)
        #expect(thrown != 0, "roundToLong(NaN) must throw IllegalArgumentException")
        #expect(__kk_float_roundToLong(floatToBits(Float.infinity), nil) == Int(Int64.max))
        #expect(__kk_float_roundToLong(floatToBits(-Float.infinity), nil) == Int(Int64.min))
        let rawMin = __kk_float_roundToLong(floatToBits(-Float.infinity), nil)
        #expect(kk_unbox_long(rawMin) == Int(Int64.min), "-Inf.roundToLong() must unbox to Long.MIN_VALUE")
        #expect(__kk_float_roundToLong(floatToBits(-1.5), nil) == -1)
        #expect(__kk_float_roundToLong(floatToBits(-0.5), nil) == 0)
        #expect(__kk_float_roundToLong(floatToBits(0.5), nil) == 1)
        // Saturation beyond Int64 bounds
        #expect(__kk_float_roundToLong(floatToBits(Float(1e19)), nil) == Int(Int64.max))
        #expect(__kk_float_roundToLong(floatToBits(Float(-1e19)), nil) == Int(Int64.min))
    }

    @Test func testDoubleRoundToLongEdgeCases() {
        var thrown = 0
        _ = __kk_double_roundToLong(doubleToBits(Double.nan), &thrown)
        #expect(thrown != 0, "roundToLong(NaN) must throw IllegalArgumentException")
        #expect(__kk_double_roundToLong(doubleToBits(Double.infinity), nil) == Int(Int64.max))
        #expect(__kk_double_roundToLong(doubleToBits(-Double.infinity), nil) == Int(Int64.min))
        // Int.min == runtimeNullSentinelInt: verify the raw return passes through
        // kk_unbox_long without being misread as null (regression for Long.MIN_VALUE bug).
        let rawMin = __kk_double_roundToLong(doubleToBits(-Double.infinity), nil)
        #expect(kk_unbox_long(rawMin) == Int(Int64.min), "-Inf.roundToLong() must unbox to Long.MIN_VALUE")
        #expect(__kk_double_roundToLong(doubleToBits(-1.5), nil) == -1)
        #expect(__kk_double_roundToLong(doubleToBits(-0.5), nil) == 0)
        #expect(__kk_double_roundToLong(doubleToBits(0.5), nil) == 1)
        #expect(__kk_double_roundToLong(doubleToBits(0.49999999999999994), nil) == 0)
        // Saturation beyond Int64 bounds
        #expect(__kk_double_roundToLong(doubleToBits(1e19), nil) == Int(Int64.max))
        #expect(__kk_double_roundToLong(doubleToBits(-1e19), nil) == Int(Int64.min))
    }

    // MARK: - Float trig / rounding (STDLIB-500..509)

    @Test func testSinFloat() {
        let result = floatFromBits(__kk_math_sin_float(floatToBits(0.0)))
        #expect(abs(result - 0.0) <= 1e-6)
    }

    @Test func testCosFloat() {
        let result = floatFromBits(__kk_math_cos_float(floatToBits(0.0)))
        #expect(abs(result - 1.0) <= 1e-6)
    }

    @Test func testTanFloat() {
        let result = floatFromBits(__kk_math_tan_float(floatToBits(0.0)))
        #expect(abs(result - 0.0) <= 1e-6)
    }

    @Test func testAsinFloat() {
        let result = floatFromBits(__kk_math_asin_float(floatToBits(1.0)))
        #expect(abs(result - Float.pi / 2) <= 1e-6)
    }

    @Test func testAcosFloat() {
        let result = floatFromBits(__kk_math_acos_float(floatToBits(1.0)))
        #expect(abs(result - 0.0) <= 1e-6)
    }

    @Test func testAtanFloat() {
        let result = floatFromBits(__kk_math_atan_float(floatToBits(0.0)))
        #expect(abs(result - 0.0) <= 1e-6)
    }

    @Test func testAtan2Float() {
        let result = floatFromBits(__kk_math_atan2_float(floatToBits(1.0), floatToBits(1.0)))
        #expect(abs(result - Float.pi / 4) <= 1e-6)
    }

    @Test func testSqrtFloat() {
        #expect(floatFromBits(__kk_math_sqrt_float(floatToBits(4.0))) == 2.0)
    }

    @Test func testCeilFloat() {
        #expect(floatFromBits(__kk_math_ceil_float(floatToBits(2.3))) == 3.0)
        #expect(floatFromBits(__kk_math_ceil_float(floatToBits(-2.3))) == -2.0)
    }

    @Test func testFloorFloat() {
        #expect(floatFromBits(__kk_math_floor_float(floatToBits(2.3))) == 2.0)
        #expect(floatFromBits(__kk_math_floor_float(floatToBits(-2.3))) == -3.0)
    }

    // MARK: - Float exp / ln / log / hypot (STDLIB-430)

    @Test func testExpFloat() {
        #expect(abs(floatFromBits(__kk_math_exp_float(floatToBits(0.0))) - 1.0) <= 1e-6)
        #expect(abs(floatFromBits(__kk_math_exp_float(floatToBits(1.0))) - Float(M_E)) <= 1e-5)
    }

    @Test func testExpm1Float() {
        #expect(abs(floatFromBits(__kk_math_expm1_float(floatToBits(0.0))) - 0.0) <= 1e-6)
        #expect(abs(floatFromBits(__kk_math_expm1_float(floatToBits(1.0))) - expm1f(1.0)) <= 1e-5)
    }

    @Test func testLnFloat() {
        #expect(abs(floatFromBits(__kk_math_ln_float(floatToBits(1.0))) - 0.0) <= 1e-6)
        #expect(abs(floatFromBits(__kk_math_ln_float(floatToBits(Float(M_E)))) - 1.0) <= 1e-5)
    }

    @Test func testLn1pFloat() {
        #expect(abs(floatFromBits(__kk_math_ln1p_float(floatToBits(0.0))) - 0.0) <= 1e-6)
        #expect(abs(floatFromBits(__kk_math_ln1p_float(floatToBits(1.0))) - log1pf(1.0)) <= 1e-6)
    }

    @Test func testLog2Float() {
        #expect(abs(floatFromBits(__kk_math_log2_float(floatToBits(8.0))) - 3.0) <= 1e-6)
    }

    @Test func testLog10Float() {
        #expect(abs(floatFromBits(__kk_math_log10_float(floatToBits(100.0))) - 2.0) <= 1e-6)
    }

    @Test func testLogFloat() {
        #expect(abs(floatFromBits(__kk_math_log_float(floatToBits(8.0), floatToBits(2.0))) - 3.0) <= 1e-5)
    }

    @Test func testHypotFloat() {
        #expect(abs(floatFromBits(__kk_math_hypot_float(floatToBits(3.0), floatToBits(4.0))) - 5.0) <= 1e-6)
    }

    // MARK: - STDLIB-MATH-112: numeric constants

    @Test func testDoublePositiveInfinity() {
        #expect(doubleFromBits(kk_double_positive_infinity()).isInfinite)
        #expect(doubleFromBits(kk_double_positive_infinity()) > 0)
    }

    @Test func testDoubleNegativeInfinity() {
        #expect(doubleFromBits(kk_double_negative_infinity()).isInfinite)
        #expect(doubleFromBits(kk_double_negative_infinity()) < 0)
    }

    @Test func testDoubleNaN() {
        #expect(doubleFromBits(kk_double_nan()).isNaN)
    }

    @Test func testDoubleMaxValue() {
        #expect(doubleFromBits(kk_double_max_value()) == Double.greatestFiniteMagnitude)
    }

    @Test func testDoubleMinValue() {
        #expect(doubleFromBits(kk_double_min_value()) == Double.leastNonzeroMagnitude)
    }

    // MARK: - roundToInt / roundToLong (STDLIB-510..511)

    @Test func testFloatRoundToInt() {
        #expect(__kk_float_roundToInt(floatToBits(2.5), nil) == 3)
        #expect(__kk_float_roundToInt(floatToBits(3.5), nil) == 4)
        #expect(__kk_float_roundToInt(floatToBits(-1.5), nil) == -1)
        #expect(__kk_float_roundToInt(floatToBits(-2.5), nil) == -2)
        var thrown = 0
        _ = __kk_float_roundToInt(floatToBits(Float.nan), &thrown)
        #expect(thrown != 0, "roundToInt(NaN) must throw IllegalArgumentException")
    }

    @Test func testDoubleRoundToInt() {
        #expect(__kk_double_roundToInt(doubleToBits(2.5), nil) == 3)
        #expect(__kk_double_roundToInt(doubleToBits(3.5), nil) == 4)
        #expect(__kk_double_roundToInt(doubleToBits(-1.5), nil) == -1)
        #expect(__kk_double_roundToInt(doubleToBits(-2.5), nil) == -2)
        var thrown = 0
        _ = __kk_double_roundToInt(doubleToBits(Double.nan), &thrown)
        #expect(thrown != 0, "roundToInt(NaN) must throw IllegalArgumentException")
    }

    @Test func testFloatRoundToLong() {
        #expect(__kk_float_roundToLong(floatToBits(2.5), nil) == 3)
        var thrown = 0
        _ = __kk_float_roundToLong(floatToBits(Float.nan), &thrown)
        #expect(thrown != 0, "roundToLong(NaN) must throw IllegalArgumentException")
    }

    @Test func testDoubleRoundToLong() {
        #expect(__kk_double_roundToLong(doubleToBits(2.5), nil) == 3)
        var thrown = 0
        _ = __kk_double_roundToLong(doubleToBits(Double.nan), &thrown)
        #expect(thrown != 0, "roundToLong(NaN) must throw IllegalArgumentException")
    }

    // MARK: - ulp / nextUp / nextDown (STDLIB-512..513)

    @Test func testDoubleUlp() {
        let result = doubleFromBits(__kk_double_ulp(doubleToBits(1.0)))
        #expect(result == Double(1.0).ulp)
    }

    @Test func testDoubleNextUp() {
        let result = doubleFromBits(__kk_double_nextUp(doubleToBits(1.0)))
        #expect(result == Double(1.0).nextUp)
    }

    @Test func testDoubleNextDown() {
        let result = doubleFromBits(__kk_double_nextDown(doubleToBits(1.0)))
        #expect(result == Double(1.0).nextDown)
    }

    @Test func testFloatUlp() {
        let result = floatFromBits(__kk_float_ulp(floatToBits(1.0)))
        #expect(result == Float(1.0).ulp)
    }

    @Test func testFloatNextUp() {
        let result = floatFromBits(__kk_float_nextUp(floatToBits(1.0)))
        #expect(result == Float(1.0).nextUp)
    }

    @Test func testFloatNextDown() {
        let result = floatFromBits(__kk_float_nextDown(floatToBits(1.0)))
        #expect(result == Float(1.0).nextDown)
    }

    // MARK: - Conversions

    @Test func testIntToFloatConversion() {
        #expect(floatFromBits(kk_int_to_float(0)) == 0.0)
        #expect(floatFromBits(kk_int_to_float(42)) == 42.0)
        #expect(floatFromBits(kk_int_to_float(-17)) == -17.0)
    }

    @Test func testIntToByteConversion() {
        #expect(kk_int_to_byte(42) == 42)
        #expect(kk_int_to_byte(127) == 127)
        #expect(kk_int_to_byte(300) == 44)
        #expect(kk_int_to_byte(-129) == 127)
    }

    @Test func testIntToShortConversion() {
        #expect(kk_int_to_short(42) == 42)
        #expect(kk_int_to_short(32767) == 32767)
        #expect(kk_int_to_short(32768) == -32768)
        #expect(kk_int_to_short(70000) == 4464)
    }

    private func doubleToBits(_ value: Double) -> Int {
        Int(truncatingIfNeeded: value.bitPattern)
    }

    private func doubleFromBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
    }

    private func floatToBits(_ value: Float) -> Int {
        Int(value.bitPattern)
    }

    private func floatFromBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw))
    }
}
#endif
