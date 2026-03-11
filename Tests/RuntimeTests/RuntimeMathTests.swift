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

    private func floatFromBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw))
    }
}
