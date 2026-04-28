// STDLIB-003: Char API edge case coverage
// Tests surrogate boundaries, radix edge cases, category boundaries,
// and predicates on chars with no case mapping.

@testable import Runtime
import XCTest

final class RuntimeCharEdgeCaseTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    // MARK: - Char.MIN_VALUE / MAX_VALUE boundaries
    // Kotlin Char.MIN_VALUE = '\u0000', Char.MAX_VALUE = '\uFFFF'

    func testMinValueCodePoint() {
        // Char.MIN_VALUE is '\u0000' (NUL), code = 0
        XCTAssertEqual(kk_char_code(0), 0)
    }

    func testMaxValueCodePoint() {
        // Char.MAX_VALUE is '\uFFFF', code = 65535
        XCTAssertEqual(kk_char_code(0xFFFF), 0xFFFF)
    }

    func testNulCharIsNotLetter() {
        XCTAssertFalse(boolValue(kk_char_isLetter(0)))
    }

    func testNulCharIsNotDigit() {
        XCTAssertFalse(boolValue(kk_char_isDigit(0)))
    }

    func testNulCharIsNotWhitespace() {
        XCTAssertFalse(boolValue(kk_char_isWhitespace(0)))
    }

    // MARK: - Surrogate boundaries

    // High surrogate range: U+D800 - U+DBFF
    func testHighSurrogateRangeLowerBound() {
        XCTAssertTrue(boolValue(kk_char_isHighSurrogate(0xD800)))
        XCTAssertTrue(boolValue(kk_char_isSurrogate(0xD800)))
        XCTAssertFalse(boolValue(kk_char_isLowSurrogate(0xD800)))
    }

    func testHighSurrogateRangeUpperBound() {
        XCTAssertTrue(boolValue(kk_char_isHighSurrogate(0xDBFF)))
        XCTAssertTrue(boolValue(kk_char_isSurrogate(0xDBFF)))
        XCTAssertFalse(boolValue(kk_char_isLowSurrogate(0xDBFF)))
    }

    func testJustBelowHighSurrogateIsNotSurrogate() {
        // U+D7FF is just below surrogate range
        XCTAssertFalse(boolValue(kk_char_isSurrogate(0xD7FF)))
        XCTAssertFalse(boolValue(kk_char_isHighSurrogate(0xD7FF)))
        XCTAssertFalse(boolValue(kk_char_isLowSurrogate(0xD7FF)))
    }

    // Low surrogate range: U+DC00 - U+DFFF
    func testLowSurrogateRangeLowerBound() {
        XCTAssertTrue(boolValue(kk_char_isLowSurrogate(0xDC00)))
        XCTAssertTrue(boolValue(kk_char_isSurrogate(0xDC00)))
        XCTAssertFalse(boolValue(kk_char_isHighSurrogate(0xDC00)))
    }

    func testLowSurrogateRangeUpperBound() {
        XCTAssertTrue(boolValue(kk_char_isLowSurrogate(0xDFFF)))
        XCTAssertTrue(boolValue(kk_char_isSurrogate(0xDFFF)))
        XCTAssertFalse(boolValue(kk_char_isHighSurrogate(0xDFFF)))
    }

    func testJustAboveLowSurrogateIsNotSurrogate() {
        // U+E000 is first private-use area character, just above surrogate range
        XCTAssertFalse(boolValue(kk_char_isSurrogate(0xE000)))
        XCTAssertFalse(boolValue(kk_char_isHighSurrogate(0xE000)))
        XCTAssertFalse(boolValue(kk_char_isLowSurrogate(0xE000)))
    }

    func testNonSurrogateAscii() {
        XCTAssertFalse(boolValue(kk_char_isSurrogate(Int(("A" as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isHighSurrogate(Int(("A" as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isLowSurrogate(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - isUpperCase / isLowerCase on chars with no case mapping

    func testDigitHasNoCase() {
        XCTAssertFalse(boolValue(kk_char_isUpperCase(Int(("5" as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isLowerCase(Int(("5" as UnicodeScalar).value))))
    }

    func testPunctuationHasNoCase() {
        XCTAssertFalse(boolValue(kk_char_isUpperCase(Int(("!" as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isLowerCase(Int(("!" as UnicodeScalar).value))))
    }

    func testSpaceHasNoCase() {
        XCTAssertFalse(boolValue(kk_char_isUpperCase(Int((" " as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isLowerCase(Int((" " as UnicodeScalar).value))))
    }

    func testUpperCaseAsciiLetter() {
        XCTAssertTrue(boolValue(kk_char_isUpperCase(Int(("A" as UnicodeScalar).value))))
        XCTAssertFalse(boolValue(kk_char_isLowerCase(Int(("A" as UnicodeScalar).value))))
    }

    func testLowerCaseAsciiLetter() {
        XCTAssertFalse(boolValue(kk_char_isUpperCase(Int(("a" as UnicodeScalar).value))))
        XCTAssertTrue(boolValue(kk_char_isLowerCase(Int(("a" as UnicodeScalar).value))))
    }

    // MARK: - uppercaseChar() / lowercaseChar() on chars with no case mapping

    func testUppercaseOfDigitIsIdentity() {
        // '5'.uppercase() returns "5" (unchanged)
        XCTAssertEqual(runtimeStringValue(kk_char_uppercase(Int(("5" as UnicodeScalar).value))), "5")
    }

    func testLowercaseOfDigitIsIdentity() {
        XCTAssertEqual(runtimeStringValue(kk_char_lowercase(Int(("5" as UnicodeScalar).value))), "5")
    }

    func testUppercaseOfPunctuationIsIdentity() {
        XCTAssertEqual(runtimeStringValue(kk_char_uppercase(Int(("!" as UnicodeScalar).value))), "!")
    }

    func testLowercaseOfPunctuationIsIdentity() {
        XCTAssertEqual(runtimeStringValue(kk_char_lowercase(Int(("!" as UnicodeScalar).value))), "!")
    }

    func testUppercaseAscii() {
        XCTAssertEqual(runtimeStringValue(kk_char_uppercase(Int(("a" as UnicodeScalar).value))), "A")
    }

    func testLowercaseAscii() {
        XCTAssertEqual(runtimeStringValue(kk_char_lowercase(Int(("A" as UnicodeScalar).value))), "a")
    }

    func testLowercaseWithTurkishLocale() {
        let locale = kk_locale_new_language_country(runtimeString("tr"), runtimeString("TR"))
        let result = kk_char_lowercase_locale(Int(("I" as UnicodeScalar).value), locale)
        XCTAssertEqual(runtimeStringValue(result), "\u{0131}")
    }

    // MARK: - titlecaseChar() edge cases

    func testTitlecaseOfNormalLetter() {
        // 'a' titlecase is 'A'
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(Int(("a" as UnicodeScalar).value))), "A")
    }

    func testTitlecaseOfDigitIsIdentity() {
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(Int(("5" as UnicodeScalar).value))), "5")
    }

    func testTitlecaseLigatureDzWithCaron() {
        // U+01C6 'ǆ' (lowercase DZ with caron) -> U+01C5 'ǅ' (titlecase)
        let dz = 0x01C6
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(dz)), "ǅ")
    }

    func testTitlecaseLigatureDzUpperCase() {
        // U+01C4 'Ǆ' (uppercase DZ with caron) -> U+01C5 'ǅ' (titlecase)
        let dzUpper = 0x01C4
        XCTAssertEqual(runtimeStringValue(kk_char_titlecase(dzUpper)), "ǅ")
    }

    // MARK: - isTitleCase

    func testTitleCaseLigatureIsRecognized() {
        // U+01C5 'ǅ' is categorized as a titlecase letter
        XCTAssertTrue(boolValue(kk_char_isTitleCase(0x01C5)))
    }

    func testUpperCaseLetterIsNotTitleCase() {
        XCTAssertFalse(boolValue(kk_char_isTitleCase(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - digitToInt (base-10 only at runtime; radix variant is a gap — see below)

    func testDigitToIntBoundariesAscii() {
        XCTAssertEqual(kk_char_digitToInt(Int(("0" as UnicodeScalar).value), nil), 0)
        XCTAssertEqual(kk_char_digitToInt(Int(("9" as UnicodeScalar).value), nil), 9)
    }

    func testDigitToIntRejectsLetter() {
        var thrown: Int = 0
        _ = kk_char_digitToInt(Int(("a" as UnicodeScalar).value), &thrown)
        XCTAssertNotEqual(thrown, 0, "Expected exception for non-digit char 'a'")
    }

    func testDigitToIntRejectsWhitespace() {
        var thrown: Int = 0
        _ = kk_char_digitToInt(Int((" " as UnicodeScalar).value), &thrown)
        XCTAssertNotEqual(thrown, 0, "Expected exception for whitespace char")
    }

    func testDigitToIntOrNullReturnsNullForLetter() {
        let result = kk_char_digitToIntOrNull(Int(("a" as UnicodeScalar).value))
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testDigitToIntOrNullReturnsNullForPunctuation() {
        let result = kk_char_digitToIntOrNull(Int(("!" as UnicodeScalar).value))
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    // MARK: - code property

    func testCodeReturnsUnicodeCodePoint() {
        XCTAssertEqual(kk_char_code(Int(("A" as UnicodeScalar).value)), 65)
        XCTAssertEqual(kk_char_code(Int(("a" as UnicodeScalar).value)), 97)
        XCTAssertEqual(kk_char_code(Int(("0" as UnicodeScalar).value)), 48)
        XCTAssertEqual(kk_char_code(Int((" " as UnicodeScalar).value)), 32)
    }

    // MARK: - directionality property

    func testDirectionalityReturnsKotlinEnumOrdinals() {
        XCTAssertEqual(kk_char_directionality(Int(("A" as UnicodeScalar).value)), 1)
        XCTAssertEqual(kk_char_directionality(0x05D0), 2)
        XCTAssertEqual(kk_char_directionality(0x0627), 3)
        XCTAssertEqual(kk_char_directionality(Int(("5" as UnicodeScalar).value)), 4)
        XCTAssertEqual(kk_char_directionality(Int((" " as UnicodeScalar).value)), 13)
    }

    // MARK: - isWhitespace edge cases

    func testTabIsWhitespace() {
        XCTAssertTrue(boolValue(kk_char_isWhitespace(Int(("\t" as UnicodeScalar).value))))
    }

    func testNewlineIsWhitespace() {
        XCTAssertTrue(boolValue(kk_char_isWhitespace(Int(("\n" as UnicodeScalar).value))))
    }

    func testCarriageReturnIsWhitespace() {
        XCTAssertTrue(boolValue(kk_char_isWhitespace(Int(("\r" as UnicodeScalar).value))))
    }

    func testNoBreakSpaceIsWhitespace() {
        // U+00A0 NO-BREAK SPACE — isWhitespace in Kotlin returns true
        XCTAssertTrue(boolValue(kk_char_isWhitespace(0x00A0)))
    }

    func testLetterIsNotWhitespace() {
        XCTAssertFalse(boolValue(kk_char_isWhitespace(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - isLetterOrDigit

    func testLetterOrDigitForLetter() {
        XCTAssertTrue(boolValue(kk_char_isLetterOrDigit(Int(("Z" as UnicodeScalar).value))))
    }

    func testLetterOrDigitForDigit() {
        XCTAssertTrue(boolValue(kk_char_isLetterOrDigit(Int(("3" as UnicodeScalar).value))))
    }

    func testLetterOrDigitForSpace() {
        XCTAssertFalse(boolValue(kk_char_isLetterOrDigit(Int((" " as UnicodeScalar).value))))
    }

    func testLetterOrDigitForUnicodeLetter() {
        // U+00E9 'é' is a letter
        XCTAssertTrue(boolValue(kk_char_isLetterOrDigit(0x00E9)))
    }

    // MARK: - category mapping

    func testCategoryForUppercaseLetter() {
        // 'A' -> UPPERCASE_LETTER = 1
        XCTAssertEqual(kk_char_category(Int(("A" as UnicodeScalar).value)), 1)
    }

    func testCategoryForLowercaseLetter() {
        // 'a' -> LOWERCASE_LETTER = 2
        XCTAssertEqual(kk_char_category(Int(("a" as UnicodeScalar).value)), 2)
    }

    func testCategoryForDecimalDigit() {
        // '5' -> DECIMAL_DIGIT_NUMBER = 9
        XCTAssertEqual(kk_char_category(Int(("5" as UnicodeScalar).value)), 9)
    }

    func testCategoryForTitlecaseLetter() {
        // U+01C5 'ǅ' -> TITLECASE_LETTER = 3
        XCTAssertEqual(kk_char_category(0x01C5), 3)
    }

    // MARK: - ASCII vs Unicode letter categorization

    func testAsciiLetterIsLetter() {
        XCTAssertTrue(boolValue(kk_char_isLetter(Int(("a" as UnicodeScalar).value))))
        XCTAssertTrue(boolValue(kk_char_isLetter(Int(("Z" as UnicodeScalar).value))))
    }

    func testUnicodeLetterIsLetter() {
        // U+00E9 'é'
        XCTAssertTrue(boolValue(kk_char_isLetter(0x00E9)))
        // U+4E2D '中' (CJK unified ideograph)
        XCTAssertTrue(boolValue(kk_char_isLetter(0x4E2D)))
    }

    func testAsciiDigitIsNotLetter() {
        XCTAssertFalse(boolValue(kk_char_isLetter(Int(("9" as UnicodeScalar).value))))
    }

    func testSurrogateCharacterIsNotLetter() {
        // Surrogates are not valid Unicode scalars, so isLetter should be false
        XCTAssertFalse(boolValue(kk_char_isLetter(0xD800)))
    }

    func testSurrogateCharacterIsNotDigit() {
        XCTAssertFalse(boolValue(kk_char_isDigit(0xD800)))
    }
}
