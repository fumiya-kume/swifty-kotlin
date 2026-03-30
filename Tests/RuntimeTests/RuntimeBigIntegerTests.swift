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
}
