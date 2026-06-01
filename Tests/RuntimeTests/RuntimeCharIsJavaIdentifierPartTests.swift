// STDLIB-TEXT-PROP-009: Char.isJavaIdentifierPart runtime tests
// Tests that kk_char_isJavaIdentifierPart matches java.lang.Character.isJavaIdentifierPart semantics.

@testable import Runtime
import XCTest

final class RuntimeCharIsJavaIdentifierPartTests: XCTestCase {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (always valid identifier parts)

    func testLetterIsIdentifierPart() {
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("A"))))
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("z"))))
    }

    func testUnicodeLetterIsIdentifierPart() {
        // U+00E9 'é' - lowercase letter
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (other letter)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0x4E2D)))
    }

    // MARK: - Digits (valid identifier parts)

    func testDecimalDigitIsIdentifierPart() {
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("0"))))
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("9"))))
    }

    // MARK: - Connector punctuation (underscore etc.)

    func testUnderscoreIsIdentifierPart() {
        // '_' is connector punctuation (Pc)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("_"))))
    }

    // MARK: - Currency symbols

    func testDollarSignIsIdentifierPart() {
        // '$' is currency symbol (Sc)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(scalar("$"))))
    }

    // MARK: - Characters that are NOT identifier parts

    func testSpaceIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierPart(scalar(" "))))
    }

    func testPlusIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierPart(scalar("+"))))
    }

    func testAtSignIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierPart(scalar("@"))))
    }

    func testPeriodIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierPart(scalar("."))))
    }

    // MARK: - Surrogate code units

    func testSurrogateIsIdentifierPart() {
        // Java treats surrogates as identifier parts
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0xD800)))
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0xDFFF)))
    }

    // MARK: - Letter number (Nl category)

    func testLetterNumberIsIdentifierPart() {
        // U+2160 'Ⅰ' - Roman numeral one (letter number Nl)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0x2160)))
    }

    // MARK: - Non-spacing combining marks (Mn category)

    func testCombiningMarkIsIdentifierPart() {
        // U+0300 COMBINING GRAVE ACCENT (non-spacing mark Mn)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierPart(0x0300)))
    }
}
