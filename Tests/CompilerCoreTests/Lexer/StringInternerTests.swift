import XCTest
@testable import CompilerCore

final class StringInternerTests: XCTestCase {

    // MARK: - InternedString

    func testInternedStringInvalidDefault() {
        let invalid = InternedString.invalid
        XCTAssertEqual(invalid.rawValue, -1)
    }

    func testInternedStringDefaultInitIsInvalid() {
        let s = InternedString()
        XCTAssertEqual(s.rawValue, -1)
    }

    func testInternedStringWithRawValue() {
        let s = InternedString(rawValue: 42)
        XCTAssertEqual(s.rawValue, 42)
    }

    func testInternedStringHashable() {
        let a = InternedString(rawValue: 1)
        let b = InternedString(rawValue: 1)
        let c = InternedString(rawValue: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)

        var set = Set<InternedString>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
        set.insert(c)
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - StringInterner basic operations

    func testInternReturnsSameIDForSameString() {
        let interner = StringInterner()
        let id1 = interner.intern("hello")
        let id2 = interner.intern("hello")
        XCTAssertEqual(id1, id2)
    }

    func testInternReturnsDifferentIDForDifferentStrings() {
        let interner = StringInterner()
        let id1 = interner.intern("hello")
        let id2 = interner.intern("world")
        XCTAssertNotEqual(id1, id2)
    }

    func testResolveReturnsOriginalString() {
        let interner = StringInterner()
        let id = interner.intern("test string")
        let resolved = interner.resolve(id)
        XCTAssertEqual(resolved, "test string")
    }

    func testResolveInvalidIDReturnsEmpty() {
        let interner = StringInterner()
        let result = interner.resolve(InternedString.invalid)
        XCTAssertEqual(result, "")
    }

    func testResolveOutOfBoundsReturnsEmpty() {
        let interner = StringInterner()
        let result = interner.resolve(InternedString(rawValue: 9999))
        XCTAssertEqual(result, "")
    }

    func testInternEmptyString() {
        let interner = StringInterner()
        let id = interner.intern("")
        let resolved = interner.resolve(id)
        XCTAssertEqual(resolved, "")
    }

    func testInternMultipleStrings() {
        let interner = StringInterner()
        let words = ["apple", "banana", "cherry", "date", "elderberry"]
        var ids: [InternedString] = []
        for word in words {
            ids.append(interner.intern(word))
        }
        // All IDs should be unique
        XCTAssertEqual(Set(ids).count, words.count)
        // All should resolve back
        for (i, word) in words.enumerated() {
            XCTAssertEqual(interner.resolve(ids[i]), word)
        }
    }

    func testInternIDsAreSequential() {
        let interner = StringInterner()
        let id0 = interner.intern("a")
        let id1 = interner.intern("b")
        let id2 = interner.intern("c")
        XCTAssertEqual(id0.rawValue, 0)
        XCTAssertEqual(id1.rawValue, 1)
        XCTAssertEqual(id2.rawValue, 2)
    }

    func testInternUnicodeStrings() {
        let interner = StringInterner()
        let id1 = interner.intern("日本語")
        let id2 = interner.intern("emoji 🎉")
        let id3 = interner.intern("日本語")
        XCTAssertEqual(id1, id3)
        XCTAssertNotEqual(id1, id2)
        XCTAssertEqual(interner.resolve(id1), "日本語")
        XCTAssertEqual(interner.resolve(id2), "emoji 🎉")
    }

    func testInternSpecialCharacters() {
        let interner = StringInterner()
        let id = interner.intern("hello\nworld\ttab")
        XCTAssertEqual(interner.resolve(id), "hello\nworld\ttab")
    }

    // MARK: - Thread safety

    func testConcurrentInternDoesNotCrash() {
        let interner = StringInterner()
        let expectation = XCTestExpectation(description: "Concurrent intern")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            DispatchQueue.global().async {
                for j in 0..<100 {
                    let _ = interner.intern("string_\(i)_\(j)")
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify all strings can be resolved
        for i in 0..<10 {
            for j in 0..<100 {
                let id = interner.intern("string_\(i)_\(j)")
                XCTAssertEqual(interner.resolve(id), "string_\(i)_\(j)")
            }
        }
    }

    func testConcurrentResolveDoesNotCrash() {
        let interner = StringInterner()
        var ids: [InternedString] = []
        for i in 0..<100 {
            ids.append(interner.intern("value_\(i)"))
        }

        let expectation = XCTestExpectation(description: "Concurrent resolve")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                for id in ids {
                    let _ = interner.resolve(id)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }
}
