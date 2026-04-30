@testable import Runtime
import XCTest

private let firstNotNullOfStringForB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    if charRaw == Int(Unicode.Scalar("b").value) {
        return registerRuntimeObject(RuntimeStringBox("bee"))
    }
    return runtimeNullSentinelInt
}

private let firstNotNullOfAlwaysNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let firstNotNullOfAlwaysZeroNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    0
}

private let reduceRightIndexedPickIndexOne: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, acc, _ in
    index == 1 ? charRaw : acc
}

private let reduceRightIndexedIndexChecksum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, acc, _ in
    acc + charRaw + index
}

final class RuntimeStringHOFTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testFirstNotNullOfReturnsFirstNonNullResult() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOf(
            source,
            unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfSetsThrownWhenNoResultMatches() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOf(
            source,
            unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfTreatsZeroAsNullFromNullableLambda() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOf(
            source,
            unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfOrNullReturnsFirstNonNullResult() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOfOrNull(
            source,
            unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfOrNullReturnsNullSentinelWhenNoResultMatches() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOfOrNull(
            source,
            unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testFirstNotNullOfOrNullTreatsZeroAsNullFromNullableLambda() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_firstNotNullOfOrNull(
            source,
            unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedWalksRightToLeftWithIndexes() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightIndexed(
            source,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedUsesLastCharacterAsInitialAccumulator() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightIndexed(
            source,
            unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightIndexedSetsThrownForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduceRightIndexed(
            source,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
