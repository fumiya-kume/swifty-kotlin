@testable import Runtime
import XCTest

final class RuntimeCharTests: IsolatedRuntimeXCTestCase {
    func testCharCaseConversionPreservesUnicodeMappings() {
        XCTAssertEqual(runtimeStringValue(kk_char_uppercase(scalarValue(of: "ß"))), "SS")
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(scalarValue(of: "ǆ"))), "ǅ")
        XCTAssertEqual(runtimeStringValue(kk_char_lowercase(scalarValue(of: "İ"))), "i\u{0307}")
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func scalarValue(of character: Character) -> Int {
        Int(character.unicodeScalars.first?.value ?? 0)
    }
}
