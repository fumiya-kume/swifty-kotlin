@testable import CompilerCore
import XCTest

private final class CapturedIDBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(String, InternedString)] = []

    func append(contentsOf ids: [(String, InternedString)]) {
        lock.lock()
        storage.append(contentsOf: ids)
        lock.unlock()
    }

    func snapshot() -> [(String, InternedString)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

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

    func testInternIDsAreMonotonicallyIncreasing() {
        let interner = StringInterner()
        let id0 = interner.intern("a")
        let id1 = interner.intern("b")
        let id2 = interner.intern("c")
        // IDs should be distinct and increase monotonically,
        // but exact raw values are an implementation detail.
        XCTAssertNotEqual(id0, InternedString.invalid)
        XCTAssertNotEqual(id1, InternedString.invalid)
        XCTAssertNotEqual(id2, InternedString.invalid)
        XCTAssertNotEqual(id0, id1)
        XCTAssertNotEqual(id1, id2)
        XCTAssertNotEqual(id0, id2)
        XCTAssertLessThan(id0.rawValue, id1.rawValue)
        XCTAssertLessThan(id1.rawValue, id2.rawValue)
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

        // Capture IDs returned during concurrent phase so we verify
        // the actual values produced under contention, not re-interned ones.
        let capturedIDs = CapturedIDBuffer()

        for i in 0 ..< 10 {
            DispatchQueue.global().async {
                var localIDs: [(String, InternedString)] = []
                for j in 0 ..< 100 {
                    let str = "string_\(i)_\(j)"
                    let id = interner.intern(str)
                    localIDs.append((str, id))
                }
                capturedIDs.append(contentsOf: localIDs)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify IDs captured during the concurrent phase resolve correctly
        for (str, id) in capturedIDs.snapshot() {
            XCTAssertEqual(interner.resolve(id), str)
        }
    }

    func testConcurrentResolveDoesNotCrash() {
        let interner = StringInterner()
        let ids: [InternedString] = (0 ..< 100).map { interner.intern("value_\($0)") }

        let expectation = XCTestExpectation(description: "Concurrent resolve")
        expectation.expectedFulfillmentCount = 10

        for _ in 0 ..< 10 {
            DispatchQueue.global().async {
                for id in ids {
                    _ = interner.resolve(id)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }
}
