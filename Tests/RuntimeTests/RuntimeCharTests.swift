@testable import Runtime
import XCTest

final class RuntimeCharTests: XCTestCase {
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

    func testTitlecaseCharUsesOneToOneTitlecaseMapping() {
        XCTAssertEqual(kk_char_titlecaseChar(scalarValue(of: "a")), scalarValue(of: "A"))
        XCTAssertEqual(kk_char_titlecaseChar(scalarValue(of: "ǆ")), scalarValue(of: "ǅ"))
        XCTAssertEqual(kk_char_titlecaseChar(scalarValue(of: "ß")), scalarValue(of: "ß"))
        XCTAssertEqual(kk_char_titlecaseChar(scalarValue(of: "+")), scalarValue(of: "+"))
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

    /// Official doc samples for Char.digitToInt(radix).
    func testDigitToIntRadix_matchesOfficialDocSamples() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "3"), 8, &thrown), 3)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "A"), 16, &thrown), 10)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(scalarValue(of: "k"), 36, &thrown), 20)
        XCTAssertEqual(thrown, 0)
    }

    /// Kotlin accepts Unicode decimal digits (category Nd) when their value < radix.
    /// e.g. Arabic-Indic '٥' (U+0665) and fullwidth '５' (U+FF15) both equal 5.
    func testDigitToIntRadix_acceptsUnicodeDecimalDigits() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(0x0665, 10, &thrown), 5) // Arabic-Indic five
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(0x0669, 10, &thrown), 9) // Arabic-Indic nine
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(0xFF15, 10, &thrown), 5) // fullwidth digit five
        XCTAssertEqual(thrown, 0)
        // Devanagari digit three '३' (U+0969) equals 3, valid in radix 8.
        XCTAssertEqual(kk_char_digitToInt_radix(0x0969, 8, &thrown), 3)
        XCTAssertEqual(thrown, 0)
        // Devanagari digit one '१' (U+0967) equals 1.
        XCTAssertEqual(kk_char_digitToInt_radix(0x0967, 10, &thrown), 1)
        XCTAssertEqual(thrown, 0)
    }

    /// Kotlin accepts fullwidth Latin letters as digits >= 10.
    /// e.g. fullwidth 'Ａ' (U+FF21) and 'ａ' (U+FF41) equal 10 in radix 16.
    func testDigitToIntRadix_acceptsFullwidthLatinLetters() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToInt_radix(0xFF21, 16, &thrown), 10) // fullwidth 'A'
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(0xFF41, 16, &thrown), 10) // fullwidth 'a'
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToInt_radix(0xFF3A, 36, &thrown), 35) // fullwidth 'Z'
        XCTAssertEqual(thrown, 0)
    }

    /// A Unicode decimal digit whose value is not below the radix must be rejected.
    func testDigitToIntRadix_rejectsUnicodeDigitOutOfRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(0x0669, 8, &thrown) // Arabic-Indic nine, radix 8
        XCTAssertNotEqual(thrown, 0, "'٩' (9) is not a valid base-8 digit")
    }

    /// Non-Latin letters are never valid digits > 9 (doc note: only Latin letters).
    func testDigitToIntRadix_rejectsNonLatinLetter() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(0x03B2, 36, &thrown) // Greek small beta 'β'
        XCTAssertNotEqual(thrown, 0, "'β'.digitToInt(36) should fail per the docs")
    }

    // MARK: - STDLIB-003-ABI-002: Char.Companion.digitToChar(digit: Int, radix: Int)

    func testDigitToCharRadix_singleDigit() {
        var thrown = 0
        let code = kk_char_digitToChar_radix(5, 10, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("5" as UnicodeScalar).value))
    }

    func testDigitToCharRadix_hexLetter() {
        // Kotlin: 10.digitToChar(16) == 'A' (UPPERCASE per the official docs sample).
        var thrown = 0
        let code = kk_char_digitToChar_radix(10, 16, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("A" as UnicodeScalar).value))
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
        // Kotlin: 35.digitToChar(36) == 'Z' (UPPERCASE per the official docs sample).
        var thrown = 0
        let code = kk_char_digitToChar_radix(35, 36, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(code, Int(("Z" as UnicodeScalar).value))
    }

    /// Documented samples from kotlin.text.digitToChar: digits >= 10 map to the
    /// UPPERCASE Latin letters, not lowercase.
    func testDigitToCharRadix_matchesOfficialDocSamples() {
        var thrown = 0
        XCTAssertEqual(kk_char_digitToChar_radix(5, 10, &thrown), Int(("5" as UnicodeScalar).value))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToChar_radix(3, 8, &thrown), Int(("3" as UnicodeScalar).value))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToChar_radix(10, 16, &thrown), Int(("A" as UnicodeScalar).value))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_char_digitToChar_radix(20, 36, &thrown), Int(("K" as UnicodeScalar).value))
        XCTAssertEqual(thrown, 0)
    }

    /// Every digit value 10..35 must map to 'A'..'Z' (round-trips with digitToInt).
    func testDigitToCharRadix_allLetterDigitsAreUppercase() {
        for digit in 10 ... 35 {
            var thrown = 0
            let code = kk_char_digitToChar_radix(digit, 36, &thrown)
            XCTAssertEqual(thrown, 0)
            let expected = Int(("A" as UnicodeScalar).value) + digit - 10
            XCTAssertEqual(code, expected, "digit \(digit) should map to '\(Character(UnicodeScalar(expected)!))'")
            XCTAssertTrue(code >= Int(("A" as UnicodeScalar).value) && code <= Int(("Z" as UnicodeScalar).value))
        }
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
