@testable import Runtime
import XCTest

final class RuntimeCharTests: IsolatedRuntimeXCTestCase {
    func testCharCaseConversionPreservesUnicodeMappings() {
        XCTAssertEqual(runtimeStringValue(kk_char_uppercase(scalarValue(of: "ß"))), "SS")
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(scalarValue(of: "ǆ"))), "ǅ")
        XCTAssertEqual(runtimeStringValue(kk_char_lowercase(scalarValue(of: "İ"))), "i\u{0307}")
    }

    func testLowercaseCharUsesFirstScalarOfLowercaseMapping() {
        XCTAssertEqual(kk_char_lowercaseChar(scalarValue(of: "İ")), scalarValue(of: "i"))
        XCTAssertEqual(kk_char_lowercaseChar(scalarValue(of: "A")), scalarValue(of: "a"))
        XCTAssertEqual(kk_char_lowercaseChar(scalarValue(of: "5")), scalarValue(of: "5"))
    }

    func testUppercaseCharUsesOneToOneUppercaseMapping() {
        XCTAssertEqual(kk_char_uppercaseChar(scalarValue(of: "a")), scalarValue(of: "A"))
        XCTAssertEqual(kk_char_uppercaseChar(scalarValue(of: "ω")), scalarValue(of: "Ω"))
        XCTAssertEqual(kk_char_uppercaseChar(scalarValue(of: "ß")), scalarValue(of: "ß"))
        XCTAssertEqual(kk_char_uppercaseChar(scalarValue(of: "1")), scalarValue(of: "1"))
    }


    // MARK: - STDLIB-003-ABI-001: Char.digitToInt(radix: Int)

    func testDigitToIntRadix_base10() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "5"), 10, &thrown), 5)
        XCTAssertEqual(thrown, 0)
    }

    func testDigitToIntRadix_base16_lowerHex() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "a"), 16, &thrown), 10)
        XCTAssertEqual(thrown, 0)
    }

    func testDigitToIntRadix_base16_upperHex() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "F"), 16, &thrown), 15)
        XCTAssertEqual(thrown, 0)
    }

    func testDigitToIntRadix_base2() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "1"), 2, &thrown), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "0"), 2, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testDigitToIntRadix_throwsForInvalidRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "5"), 1, &thrown)
        XCTAssertNotEqual(thrown, 0, "radix < 2 should throw")

        thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "5"), 37, &thrown)
        XCTAssertNotEqual(thrown, 0, "radix > 36 should throw")
    }

    func testDigitToIntRadix_throwsForCharNotInRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "2"), 2, &thrown)
        XCTAssertNotEqual(thrown, 0, "'2' is not a valid base-2 digit")
    }

    func testDigitToIntRadix_base36() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "z"), 36, &thrown), 35)
        XCTAssertEqual(thrown, 0)
    }

    // MARK: - STDLIB-003-ABI-002: Char.Companion.digitToChar(digit: Int, radix: Int)

    func testDigitToCharRadix_singleDigit() {
        var thrown = 0
        let code = kk_char_digitToChar_radix(5, 10, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("5" as UnicodeScalar).value))
    }

    func testDigitToCharRadix_hexLetter() {
        var thrown = 0
        let code = kk_char_digitToChar_radix(10, 16, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("a" as UnicodeScalar).value))
    }

    func testDigitToCharRadix_throwsForInvalidRadix() {
        var thrown = 0
        _ = kk_char_digitToChar_radix(0, 1, &thrown)
        XCTAssertNotEqual(thrown, 0, "radix < 2 should throw")

        thrown = 0
        _ = kk_char_digitToChar_radix(0, 37, &thrown)
        XCTAssertNotEqual(thrown, 0, "radix > 36 should throw")
    }

    func testDigitToCharRadix_throwsForDigitOutOfRange() {
        var thrown = 0
        _ = kk_char_digitToChar_radix(-1, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "negative digit should throw")

        thrown = 0
        _ = kk_char_digitToChar_radix(10, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "digit >= radix should throw")
    }

    func testDigitToCharRadix_base36() {
        var thrown = 0
        let code = kk_char_digitToChar_radix(35, 36, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("z" as UnicodeScalar).value))
    }

    // MARK: - STDLIB-003-ABI-003: Char(code: Int)

    func testCharFromCode_validCode() {
        var thrown = 0
        XCTAssertEqual(kk_char_fromCode(65, &thrown), 65) // 'A'
        XCTAssertEqual(thrown, 0)
    }

    func testCharFromCode_zero() {
        var thrown = 0
        XCTAssertEqual(kk_char_fromCode(0, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCharFromCode_maxValidCode() {
        var thrown = 0
        XCTAssertEqual(kk_char_fromCode(0xFFFF, &thrown), 0xFFFF)
        XCTAssertEqual(thrown, 0)
    }

    func testCharFromCode_throwsForNegativeCode() {
        var thrown = 0
        _ = kk_char_fromCode(-1, &thrown)
        XCTAssertNotEqual(thrown, 0, "negative code should throw")
    }

    func testCharFromCode_throwsForCodeAbove0xFFFF() {
        var thrown = 0
        _ = kk_char_fromCode(0x10000, &thrown)
        XCTAssertNotEqual(thrown, 0, "code > 0xFFFF should throw")
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func scalarValue(of character: Character) -> Int {
        Int(character.unicodeScalars.first?.value ?? 0)
    }
}
