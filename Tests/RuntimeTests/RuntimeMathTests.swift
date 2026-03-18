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
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(2.3))), 2.0)
        XCTAssertEqual(doubleFromBits(kk_math_round(doubleToBits(2.5))), 3.0)
    }

    func testRoundToIntLongSpecialValues() {
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.nan)), Int(0))
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.infinity)), Int(Int32.max))
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-Float.infinity)), Int(Int32.min))
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-1.5)), -1)

        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.nan)), Int(0))
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.infinity)), Int(Int32.max))
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-Double.infinity)), Int(Int32.min))
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-1.5)), -1)

        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.nan)), Int(0))
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.infinity)), Int(Int64.max))
        XCTAssertEqual(kk_float_roundToLong(floatToBits(-Float.infinity)), Int(Int64.min))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.nan)), Int(0))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.infinity)), Int(Int64.max))
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(-Double.infinity)), Int(Int64.min))
    }

    // MARK: - Float trig / rounding (STDLIB-500..509)
    func testSinFloat() {
        let result = floatFromBits(kk_math_sin_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    func testCosFloat() {
        let result = floatFromBits(kk_math_cos_float(floatToBits(0.0)))
        XCTAssertEqual(result, 1.0, accuracy: 1e-6)
    func testTanFloat() {
        let result = floatFromBits(kk_math_tan_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    func testAsinFloat() {
        let result = floatFromBits(kk_math_asin_float(floatToBits(1.0)))
        XCTAssertEqual(result, Float.pi / 2, accuracy: 1e-6)
    func testAcosFloat() {
        let result = floatFromBits(kk_math_acos_float(floatToBits(1.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    func testAtanFloat() {
        let result = floatFromBits(kk_math_atan_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
    func testAtan2Float() {
        let result = floatFromBits(kk_math_atan2_float(floatToBits(1.0), floatToBits(1.0)))
        XCTAssertEqual(result, Float.pi / 4, accuracy: 1e-6)
    func testSqrtFloat() {
        XCTAssertEqual(floatFromBits(kk_math_sqrt_float(floatToBits(4.0))), 2.0)
    func testRoundFloat() {
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.3))), 2.0)
        XCTAssertEqual(floatFromBits(kk_math_round_float(floatToBits(2.5))), 3.0)
    func testCeilFloat() {
        XCTAssertEqual(floatFromBits(kk_math_ceil_float(floatToBits(2.3))), 3.0)
        XCTAssertEqual(floatFromBits(kk_math_ceil_float(floatToBits(-2.3))), -2.0)
    func testFloorFloat() {
        XCTAssertEqual(floatFromBits(kk_math_floor_float(floatToBits(2.3))), 2.0)
        XCTAssertEqual(floatFromBits(kk_math_floor_float(floatToBits(-2.3))), -3.0)
    // MARK: - roundToInt / roundToLong (STDLIB-510..511)
    func testFloatRoundToInt() {
        XCTAssertEqual(kk_float_roundToInt(floatToBits(2.5)), 3)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(3.5)), 4)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-1.5)), -1)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(-2.5)), -2)
        XCTAssertEqual(kk_float_roundToInt(floatToBits(Float.nan)), 0)
    func testDoubleRoundToInt() {
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(2.5)), 3)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(3.5)), 4)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-1.5)), -1)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(-2.5)), -2)
        XCTAssertEqual(kk_double_roundToInt(doubleToBits(Double.nan)), 0)
    func testFloatRoundToLong() {
        XCTAssertEqual(kk_float_roundToLong(floatToBits(2.5)), 3)
        XCTAssertEqual(kk_float_roundToLong(floatToBits(Float.nan)), 0)
    func testDoubleRoundToLong() {
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(2.5)), 3)
        XCTAssertEqual(kk_double_roundToLong(doubleToBits(Double.nan)), 0)
    // MARK: - ulp / nextUp / nextDown (STDLIB-512..513)
    func testDoubleUlp() {
        let result = doubleFromBits(kk_double_ulp(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).ulp)
    func testDoubleNextUp() {
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).nextUp)
    func testDoubleNextDown() {
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(1.0)))
        XCTAssertEqual(result, Double(1.0).nextDown)
    func testFloatUlp() {
        let result = floatFromBits(kk_float_ulp(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).ulp)
    func testFloatNextUp() {
        let result = floatFromBits(kk_float_nextUp(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).nextUp)
    func testFloatNextDown() {
        let result = floatFromBits(kk_float_nextDown(floatToBits(1.0)))
        XCTAssertEqual(result, Float(1.0).nextDown)
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
        Int(truncatingIfNeeded: value.bitPattern)
        Int(value.bitPattern)
    }

    private func floatFromBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw))
    }
}
