import Foundation
@testable import Runtime
import XCTest

/// Documentation-derived conformance tests for Double/Float `toString()`.
///
/// Expected values are taken from Kotlin's documented behaviour (matching
/// java.lang.Double.toString / java.lang.Float.toString), where decimal
/// notation is used for magnitudes in `[1e-3, 1e7)` and scientific notation
/// (`d.dddEexp`) otherwise. These assertions are independent of kotlinc, so
/// they guard the runtime formatter in CI even without the diff harness.
final class RuntimeFloatingPointToStringTests: XCTestCase {
    func testDoubleDecimalRange() {
        XCTAssertEqual(runtimeFormatFloatingPoint(0.0), "0.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(-0.0), "-0.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.0), "1.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(-1.0), "-1.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(100.0), "100.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(0.5), "0.5")
        XCTAssertEqual(runtimeFormatFloatingPoint(0.1), "0.1")
        XCTAssertEqual(runtimeFormatFloatingPoint(0.001), "0.001")
        XCTAssertEqual(runtimeFormatFloatingPoint(9_999_999.0), "9999999.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(0.1 + 0.2), "0.30000000000000004")
    }

    func testDoubleScientificRange() {
        // |x| < 1e-3 or >= 1e7 switches to scientific notation.
        XCTAssertEqual(runtimeFormatFloatingPoint(0.0001), "1.0E-4")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.0e7), "1.0E7")
        XCTAssertEqual(runtimeFormatFloatingPoint(10_000_000.0), "1.0E7")
        XCTAssertEqual(runtimeFormatFloatingPoint(123_456_789.0), "1.23456789E8")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.0e20), "1.0E20")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.0e-20), "1.0E-20")
        XCTAssertEqual(runtimeFormatFloatingPoint(Double.greatestFiniteMagnitude), "1.7976931348623157E308")
    }

    func testDoubleSpecialValues() {
        XCTAssertEqual(runtimeFormatFloatingPoint(Double.nan), "NaN")
        XCTAssertEqual(runtimeFormatFloatingPoint(Double.infinity), "Infinity")
        XCTAssertEqual(runtimeFormatFloatingPoint(-Double.infinity), "-Infinity")
    }

    func testFloatDecimalRange() {
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(0.0)), "0.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(-0.0)), "-0.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(1.0)), "1.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(100.0)), "100.0")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(0.1)), "0.1")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(0.001)), "0.001")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(9_999_999.0)), "9999999.0")
    }

    func testFloatScientificRange() {
        // Float must use the same 1e-3 / 1e7 thresholds as Double; Swift's
        // String(describing:) keeps these in fixed notation, so the formatter
        // is responsible for switching to scientific form.
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(0.0001)), "1.0E-4")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(1.0e7)), "1.0E7")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float(10_000_000.0)), "1.0E7")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float.greatestFiniteMagnitude), "3.4028235E38")
    }

    func testFloatSpecialValues() {
        XCTAssertEqual(runtimeFormatFloatingPoint(Float.nan), "NaN")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float.infinity), "Infinity")
        XCTAssertEqual(runtimeFormatFloatingPoint(-Float.infinity), "-Infinity")
    }
}
