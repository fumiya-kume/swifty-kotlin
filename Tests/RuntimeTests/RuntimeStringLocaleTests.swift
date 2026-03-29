@testable import Runtime
import XCTest

final class RuntimeStringLocaleTests: IsolatedRuntimeXCTestCase {
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

    func testLocaleLowercaseUsesTurkishRules() {
        let result = kk_string_lowercase_locale(runtimeString("I"), kk_locale_new(runtimeString("tr")))
        XCTAssertEqual(stringValue(result), "ı")
    }

    func testLocaleUppercaseUsesTurkishRules() {
        let result = kk_string_uppercase_locale(runtimeString("i"), kk_locale_new(runtimeString("tr")))
        XCTAssertEqual(stringValue(result), "İ")
    }

    func testLocaleCompareToMatchesBasicOrdering() {
        let result = kk_string_compareTo_locale(
            runtimeString("abc"),
            runtimeString("abd"),
            kk_locale_new(runtimeString("en_US"))
        )
        XCTAssertEqual(result, -1)
    }
}
