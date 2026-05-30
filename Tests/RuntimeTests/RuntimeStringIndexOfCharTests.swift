@testable import Runtime
import XCTest

/// STDLIB-TEXT-FN-020: Verifies the dedicated Char-overload runtime entry
/// `kk_string_indexOf_char` behaves consistently with Kotlin's
/// `CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false)`.
final class RuntimeStringIndexOfCharTests: XCTestCase {
    private func makeRuntimeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func charRaw(_ char: Character) -> Int {
        kk_box_char(Int(char.unicodeScalars.first!.value))
    }

    func testIndexOfCharBasicMatchAtStart() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("h"), 0, 0), 0)
    }

    func testIndexOfCharBasicMatchInMiddle() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("l"), 0, 0), 2)
    }

    func testIndexOfCharNotFoundReturnsNegativeOne() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("z"), 0, 0), -1)
    }

    func testIndexOfCharRespectsStartIndex() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("l"), 3, 0), 3)
    }

    func testIndexOfCharStartIndexBeyondLengthReturnsNegativeOne() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("l"), 10, 0), -1)
    }

    func testIndexOfCharIgnoreCaseFindsUppercase() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("L"), 0, 1), 2)
    }

    func testIndexOfCharCaseSensitiveDoesNotFindUppercase() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("L"), 0, 0), -1)
    }

    func testIndexOfCharNegativeStartIndexIsClamped() {
        let strRaw = makeRuntimeStringRaw("hello")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("h"), -5, 0), 0)
    }

    func testIndexOfCharOnEmptyStringReturnsNegativeOne() {
        let strRaw = makeRuntimeStringRaw("")
        XCTAssertEqual(kk_string_indexOf_char(strRaw, charRaw("a"), 0, 0), -1)
    }
}
