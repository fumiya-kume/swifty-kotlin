@testable import Runtime
import XCTest

private let isLetterB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? 1 : 0
}

private let isLetterZ: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("z").value) ? 1 : 0
}

final class RuntimeStringIndexOfLastTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testIndexOfLastReturnsLastMatchingIndex() {
        let source = registerRuntimeObject(RuntimeStringBox("abcabc"))
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0

        let result = kk_string_indexOfLast(source, predicate, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 4)
    }

    func testIndexOfLastReturnsNegativeOneWhenNoMatch() {
        let source = registerRuntimeObject(RuntimeStringBox("abcabc"))
        let predicate = unsafeBitCast(isLetterZ, to: Int.self)
        var thrown = 0

        let result = kk_string_indexOfLast(source, predicate, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfLastReturnsNegativeOneForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0

        let result = kk_string_indexOfLast(source, predicate, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfLastReturnsSingleCharIndexWhenOnlyOneMatch() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0

        let result = kk_string_indexOfLast(source, predicate, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 1)
    }
}
