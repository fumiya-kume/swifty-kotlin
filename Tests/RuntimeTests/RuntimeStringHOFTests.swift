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

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
