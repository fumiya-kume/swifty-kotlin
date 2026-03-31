@testable import Runtime
import XCTest

final class RuntimeBigIntegerTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func bigInteger(_ text: String) -> Int {
        var thrown = 0
        let raw = kk_biginteger_fromString(runtimeString(text), &thrown)
        XCTAssertEqual(thrown, 0, "Expected \(text) to parse as BigInteger")
        return raw
    }

    func testStringToBigIntegerAcceptsSignedDigits() {
        var thrown = 0
        let raw = kk_string_toBigInteger(runtimeString("-12345678901234567890"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "-12345678901234567890")
    }

    func testStringToBigIntegerRejectsDecimalPoint() {
        var thrown = 0
        _ = kk_string_toBigInteger(runtimeString("12.5"), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testBigIntegerAndHandlesPositiveOperands() {
        let lhs = bigInteger("12")
        let rhs = bigInteger("10")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "8")
    }

    func testBigIntegerAndHandlesLargePositiveOperands() {
        let lhs = bigInteger("18446744073709551615")
        let rhs = bigInteger("255")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "255")
    }

    func testBigIntegerAndUsesTwosComplementForNegativeOperands() {
        let negativeOne = bigInteger("-1")
        let mask = bigInteger("255")
        let result = kk_biginteger_and(negativeOne, mask)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "255")
    }

    func testBigIntegerAndHandlesNegativeAndPositiveBits() {
        let lhs = bigInteger("-2")
        let rhs = bigInteger("3")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "2")
    }
}
