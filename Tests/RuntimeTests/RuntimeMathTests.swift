@testable import Runtime
import XCTest

final class RuntimeMathTests: IsolatedRuntimeXCTestCase {
    // MARK: - Int

    func testAbsInt() {
        XCTAssertEqual(kk_math_abs_int(-12), 12)
        XCTAssertEqual(kk_math_abs_int(12), 12)
        XCTAssertEqual(kk_math_abs_int(Int.min), Int.min)
    }

    // MARK: - Double

    func testAbsDouble() {
        XCTAssertEqual(doubleFromBits(kk_math_abs(doubleToBits(-3.5))), 3.5)
        XCTAssertTrue(doubleFromBits(kk_math_abs(doubleToBits(Double.nan))).isNaN)
    }

    func testSqrtDouble() {
        XCTAssertEqual(doubleFromBits(kk_math_sqrt(doubleToBits(4.0))), 2.0)
    }

    func testPowDouble() {
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(2.0), doubleToBits(3.0))), 8.0)
    }

    func testCeilDouble() {
        XCTAssertEqual(doubleFromBits(kk_math_ceil(doubleToBits(2.3))), 3.0)
        XCTAssertEqual(doubleFromBits(kk_math_ceil(doubleToBits(-2.3))), -2.0)
    }

    func testFloorDouble() {
        XCTAssertEqual(doubleFromBits(kk_math_floor(doubleToBits(2.3))), 2.0)
        XCTAssertEqual(doubleFromBits(kk_math_floor(doubleToBits(-2.3))), -3.0)
    }

    func testRoundDouble() {
        // kotlin.math.round uses half-to-even (banker's rounding)
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(2.3))), 2.0)
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(2.5))), 2.0)  // half-to-even: rounds to 2
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(3.5))), 4.0)  // half-to-even: rounds to 4
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(-0.5))), 0.0) // half-to-even: rounds to 0 (not -1)
        XCTAssertTrue(doubleFromBits(kk_math_round(doubleToBits(Double.nan))).isNaN)
    }

    func testRoundFloat() {
        // kotlin.math.round(Float) also uses half-to-even
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.3))), Float(2.0))
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.5))), Float(2.0))
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(3.5))), Float(4.0))
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(-0.5))), Float(0.0))
        XCTAssertTrue(floatFromBits(kk_math_round_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - roundToInt / roundToLong edge cases

    func testFloatRoundToIntEdgeCases() {
        // NaN -> 0
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.nan)), 0)
        // +Infinity saturates to Int32.max
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.infinity)), Int(Int32.max))
        // -Infinity saturates to Int32.min
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-Float.infinity)), Int(Int32.min))
        // Negative tie: -1.5 rounds to -1 (toward +inf), not -2
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-1.5)), -1)
        // Negative tie: -0.5 rounds to 0 (toward +inf), not -1
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-0.5)), 0)
        // Positive tie: 0.5 rounds to 1
        XCTAssertEqual(kk_float_roundToInt(floatToBits(0.5)), 1)
        // Positive tie: 1.5 rounds to 2
        XCTAssertEqual(kk_float_roundToInt(floatToBits(1.5)), 2)
        // Normal values
        XCTAssertEqual(kk_float_roundToInt(floatToBits(2.3)), 2)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-2.3)), -2)
        // Saturation beyond Int32 bounds
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float(3e9))), Int(Int32.max))
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float(-3e9))), Int(Int32.min))
    }

    func testDoubleRoundToIntEdgeCases() {
        // NaN -> 0
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.nan)), 0)
        // +Infinity saturates to Int32.max
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.infinity)), Int(Int32.max))
        // -Infinity saturates to Int32.min
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-Double.infinity)), Int(Int32.min))
        // Negative tie: -1.5 rounds to -1
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-1.5)), -1)
        // Negative tie: -0.5 rounds to 0
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-0.5)), 0)
        // Positive tie: 0.5 rounds to 1
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(0.5)), 1)
        // nextDown(0.5) should round to 0 (not 1)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(0.49999999999999994)), 0)
        // Saturation beyond Int32 bounds
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(3e9)), Int(Int32.max))
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-3e9)), Int(Int32.min))
    }

    func testFloatRoundToLongEdgeCases() {
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.nan)), 0)
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.infinity)), Int(Int64.max))
        XCTAssertEqual(kk_float_roundToLong(floatToBits(-Float.infinity)), Int(Int64.min))
        XCTAssertEqual(kk_float_roundToLong(floatToBits(-1.5)), -1)
        XCTAssertEqual(kk_float_roundToLong(floatToBits(-0.5)), 0)
        XCTAssertEqual(kk_float_roundToLong(floatToBits(0.5)), 1)
        // Saturation beyond Int64 bounds
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float(1e19))), Int(Int64.max))
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float(-1e19))), Int(Int64.min))
    }

    func testDoubleRoundToLongEdgeCases() {
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.nan)), 0)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.infinity)), Int(Int64.max))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(-Double.infinity)), Int(Int64.min))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(-1.5)), -1)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(-0.5)), 0)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(0.5)), 1)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(0.49999999999999994)), 0)
        // Saturation beyond Int64 bounds
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(1e19)), Int(Int64.max))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(-1e19)), Int(Int64.min))
    }

    // MARK: - Float trig / rounding (STDLIB-500..509)

    func testSinFloat() {
        let result = floatFromBits(kk_math_sin_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    }

    func testCosFloat() {
        let result = floatFromBits(kk_math_cos_float(floatToBits(0.0)))
        XCTAssertEqual(result, 1.0, accuracy: 1e-6)
    }

    func testTanFloat() {
        let result = floatFromBits(kk_math_tan_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    }

    func testAsinFloat() {
        let result = floatFromBits(kk_math_asin_float(floatToBits(1.0)))
        XCTAssertEqual(result, Float.pi / 2, accuracy: 1e-6)
    }

    func testAcosFloat() {
        let result = floatFromBits(kk_math_acos_float(floatToBits(1.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    }

    func testAtanFloat() {
        let result = floatFromBits(kk_math_atan_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    }

    func testAtan2Float() {
        let result = floatFromBits(kk_math_atan2_float(floatToBits(1.0), floatToBits(1.0)))
        XCTAssertEqual(result, Float.pi / 4, accuracy: 1e-6)
    }

    func testSqrtFloat() {
        XCTAssertEqual(floatFromBits(kk_math_sqrt_float(floatToBits(4.0))), 2.0)
    }

    func testRoundFloat() {
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.3))), 2.0)
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.5))), 3.0)
    }

    func testCeilFloat() {
        XCTAssertEqual(floatFromBits(kk_math_ceil_float(floatToBits(2.3))), 3.0)
        XCTAssertEqual(floatFromBits(kk_math_ceil_float(floatToBits(-2.3))), -2.0)
    }

    func testFloorFloat() {
        XCTAssertEqual(floatFromBits(kk_math_floor_float(floatToBits(2.3))), 2.0)
        XCTAssertEqual(floatFromBits(kk_math_floor_float(floatToBits(-2.3))), -3.0)
    }

    // MARK: - Float abs / exp / ln / log / sign / hypot (STDLIB-430)

    func testAbsFloat() {
        XCTAssertEqual(floatFromBits(kk_math_abs_float(floatToBits(-3.14))), Float(3.14), accuracy: 1e-5)
        XCTAssertTrue(floatFromBits(kk_math_abs_float(floatToBits(Float.nan))).isNaN)
    }

    func testExpFloat() {
        XCTAssertEqual(floatFromBits(kk_math_exp_float(floatToBits(0.0))), 1.0, accuracy: 1e-6)
        XCTAssertEqual(floatFromBits(kk_math_exp_float(floatToBits(1.0))), Float(M_E), accuracy: 1e-5)
    }

    func testLnFloat() {
        XCTAssertEqual(floatFromBits(kk_math_ln_float(floatToBits(1.0))), 0.0, accuracy: 1e-6)
        XCTAssertEqual(floatFromBits(kk_math_ln_float(floatToBits(Float(M_E)))), 1.0, accuracy: 1e-5)
    }

    func testLog2Float() {
        XCTAssertEqual(floatFromBits(kk_math_log2_float(floatToBits(8.0))), 3.0, accuracy: 1e-6)
    }

    func testLog10Float() {
        XCTAssertEqual(floatFromBits(kk_math_log10_float(floatToBits(100.0))), 2.0, accuracy: 1e-6)
    }

    func testLogFloat() {
        XCTAssertEqual(floatFromBits(kk_math_log_float(floatToBits(8.0), floatToBits(2.0))), 3.0, accuracy: 1e-5)
    }

    func testSignFloat() {
        XCTAssertEqual(floatFromBits(kk_math_sign_float(floatToBits(-5.0))), -1.0)
        XCTAssertEqual(floatFromBits(kk_math_sign_float(floatToBits(5.0))), 1.0)
        XCTAssertEqual(floatFromBits(kk_math_sign_float(floatToBits(0.0))), 0.0)
        XCTAssertTrue(floatFromBits(kk_math_sign_float(floatToBits(Float.nan))).isNaN)
    }

    func testHypotFloat() {
        XCTAssertEqual(floatFromBits(kk_math_hypot_float(floatToBits(3.0), floatToBits(4.0))), 5.0, accuracy: 1e-6)
    }

    // MARK: - roundToInt / roundToLong (STDLIB-510..511)

    func testFloatRoundToInt() {
        XCTAssertEqual(kk_float_roundToInt(floatToBits(2.5)), 3)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(3.5)), 4)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-1.5)), -1)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-2.5)), -2)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.nan)), 0)
    }

    func testDoubleRoundToInt() {
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(2.5)), 3)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(3.5)), 4)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-1.5)), -1)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-2.5)), -2)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.nan)), 0)
    }

    func testFloatRoundToLong() {
        XCTAssertEqual(kk_float_roundToLong(floatToBits(2.5)), 3)
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.nan)), 0)
    }

    func testDoubleRoundToLong() {
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(2.5)), 3)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.nan)), 0)
    }

    // MARK: - ulp / nextUp / nextDown (STDLIB-512..513)

    func testDoubleUlp() {
        let result = doubleFromBits(kk_double_ulp(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).ulp)
    }

    func testDoubleNextUp() {
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).nextUp)
    }

    func testDoubleNextDown() {
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).nextDown)
    }

    func testFloatUlp() {
        let result = floatFromBits(kk_float_ulp(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).ulp)
    }

    func testFloatNextUp() {
        let result = floatFromBits(kk_float_nextUp(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).nextUp)
    }

    func testFloatNextDown() {
        let result = floatFromBits(kk_float_nextDown(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).nextDown)
    }

    // MARK: - Conversions

    func testIntToFloatConversion() {
        XCTAssertEqual(floatFromBits(kk_int_to_float(0)), 0.0)
        XCTAssertEqual(floatFromBits(kk_int_to_float(42)), 42.0)
        XCTAssertEqual(floatFromBits(kk_int_to_float(-17)), -17.0)
    }

    func testIntToByteConversion() {
        XCTAssertEqual(kk_int_to_byte(42), 42)
        XCTAssertEqual(kk_int_to_byte(127), 127)
        XCTAssertEqual(kk_int_to_byte(300), 44)
        XCTAssertEqual(kk_int_to_byte(-129), 127)
    }

    func testIntToShortConversion() {
        XCTAssertEqual(kk_int_to_short(42), 42)
        XCTAssertEqual(kk_int_to_short(32767), 32767)
        XCTAssertEqual(kk_int_to_short(32768), -32768)
        XCTAssertEqual(kk_int_to_short(70000), 4464)
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
