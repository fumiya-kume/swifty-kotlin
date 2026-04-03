import Foundation
@testable import Runtime
import XCTest

final class RuntimeNumberFormatTests: IsolatedRuntimeXCTestCase {
    func testIntegerFormatUsesLocaleGrouping() {
        let locale = kk_locale_new(runtimeString("de_DE"))
        let formatter = kk_numberformat_getIntegerInstance(locale)
        XCTAssertEqual(stringValue(kk_numberformat_formatLong(formatter, 1_234_567)), "1.234.567")
    }

    func testNumberFormatUsesLocaleDecimalSeparator() {
        let locale = kk_locale_new(runtimeString("de_DE"))
        let formatter = kk_numberformat_getNumberInstance(locale)
        XCTAssertEqual(stringValue(kk_numberformat_formatDouble(formatter, 1_234.5)), "1.234,5")
    }

    func testCurrencyFormatIncludesLocaleCurrencySymbol() {
        let locale = kk_locale_new(runtimeString("en_US"))
        let formatter = kk_numberformat_getCurrencyInstance(locale)
        XCTAssertEqual(stringValue(kk_numberformat_formatDouble(formatter, 1_234.5)), "$1,234.50")
    }

    func testPercentFormatUsesPercentStyle() {
        let locale = kk_locale_new(runtimeString("en_US"))
        let formatter = kk_numberformat_getPercentInstance(locale)
        XCTAssertEqual(stringValue(kk_numberformat_formatDouble(formatter, 0.125)), "12%")
    }

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
}
