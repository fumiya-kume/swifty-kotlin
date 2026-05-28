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

private let reducePickB: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, acc, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? charRaw : acc
}

private let reduceChecksum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, acc, charRaw, _ in
    acc + charRaw
}

private let reduceIndexedPickIndexOne: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, acc, charRaw, _ in
    index == 1 ? charRaw : acc
}

private let reduceIndexedIndexChecksum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, acc, charRaw, _ in
    acc + charRaw + index
}

private let reduceRightIndexedPickIndexOne: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, acc, _ in
    index == 1 ? charRaw : acc
}

private let reduceRightIndexedIndexChecksum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, acc, _ in
    acc + charRaw + index
}

private let reduceRightPickB: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, charRaw, acc, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? charRaw : acc
}

private let reduceRightChecksum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, charRaw, acc, _ in
    acc + charRaw
}

private let sumByWeightedA: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("a").value) ? 10 : 1
}

private let sumByDoubleWeightedA: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    kk_double_to_bits(charRaw == Int(Unicode.Scalar("a").value) ? 1.5 : 0.25)
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

    // MARK: - STDLIB-TEXT-FN-046: CharSequence.reduce

    func testReduceWalksLeftToRight() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduce(
            source,
            unsafeBitCast(reducePickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceUsesFirstCharacterAsInitialAccumulator() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduce(
            source,
            unsafeBitCast(reduceChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    func testReduceReturnsSingleCharForSingleCharString() {
        let source = registerRuntimeObject(RuntimeStringBox("z"))
        var thrown = 0

        let result = kk_string_reduce(
            source,
            unsafeBitCast(reducePickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("z").value))
    }

    func testReduceSetsThrownForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduce(
            source,
            unsafeBitCast(reducePickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - reduceIndexed

    func testReduceIndexedPicksCharAtIndexOne() {
        // "abc": index 0 = 'a' (initial acc), index 1 = 'b', index 2 = 'c'
        // lambda: return char at index 1
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceIndexed(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceIndexedUsesFirstCharacterAsInitialAccumulator() {
        // "abc": acc starts at 'a'(97), then index=1 acc+char+index = 97+98+1=196, then index=2 196+99+2=297
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceIndexed(
            source,
            unsafeBitCast(reduceIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 297)
    }

    func testReduceIndexedSetsThrownForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduceIndexed(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testReduceIndexedReturnsSingleCharWithoutInvokingLambda() {
        let source = registerRuntimeObject(RuntimeStringBox("z"))
        var thrown = 0

        let result = kk_string_reduceIndexed(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("z").value))
    }

    // MARK: - reduceIndexedOrNull

    func testReduceIndexedOrNullPicksCharAtIndexOne() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceIndexedOrNull(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceIndexedOrNullReturnsNullSentinelForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduceIndexedOrNull(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceIndexedOrNullUsesFirstCharacterAsInitialAccumulator() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceIndexedOrNull(
            source,
            unsafeBitCast(reduceIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 297)
    }

    func testReduceIndexedOrNullReturnsSingleCharWithoutInvokingLambda() {
        let source = registerRuntimeObject(RuntimeStringBox("z"))
        var thrown = 0

        let result = kk_string_reduceIndexedOrNull(
            source,
            unsafeBitCast(reduceIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("z").value))
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

    func testReduceRightIndexedOrNullWalksRightToLeftWithIndexes() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightIndexedOrNull(
            source,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedOrNullReturnsNullSentinelForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduceRightIndexedOrNull(
            source,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedOrNullUsesLastCharacterAsInitialAccumulator() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightIndexedOrNull(
            source,
            unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightOrNullWalksRightToLeft() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightOrNull(
            source,
            unsafeBitCast(reduceRightPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightOrNullReturnsNullSentinelForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_reduceRightOrNull(
            source,
            unsafeBitCast(reduceRightPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightOrNullUsesLastCharacterAsInitialAccumulator() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var thrown = 0

        let result = kk_string_reduceRightOrNull(
            source,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    func testSumByAppliesSelectorToEveryCharacter() {
        let source = registerRuntimeObject(RuntimeStringBox("aba"))
        var thrown = 0

        let result = kk_string_sumBy(
            source,
            unsafeBitCast(sumByWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 21)
    }

    func testSumByReturnsZeroForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_sumBy(
            source,
            unsafeBitCast(sumByWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testSumByDoubleAppliesSelectorToEveryCharacter() {
        let source = registerRuntimeObject(RuntimeStringBox("aba"))
        var thrown = 0

        let result = kk_string_sumByDouble(
            source,
            unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 3.25, accuracy: 0.000001)
    }

    func testSumByDoubleReturnsZeroForEmptyString() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        var thrown = 0

        let result = kk_string_sumByDouble(
            source,
            unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 0.0, accuracy: 0.000001)
    }

    // MARK: - STDLIB-TEXT-FN-039: CharSequence.onEach(action)

    func testOnEachRunsActionForEachChar() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        var collected: [UInt32] = []
        let action: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
            // Use a side channel: push charRaw to collected via a global
            RuntimeStringHOFTests._onEachCollector.append(UInt32(charRaw))
            return 0
        }
        RuntimeStringHOFTests._onEachCollector = []
        var thrown = 0
        let result = kk_string_onEach(
            source,
            unsafeBitCast(action, to: Int.self),
            0,
            &thrown
        )
        collected = RuntimeStringHOFTests._onEachCollector
        XCTAssertEqual(thrown, 0)
        // onEach returns the original string unchanged
        XCTAssertEqual(runtimeStringValue(result), "abc")
        // action ran for each character in order
        XCTAssertEqual(collected, [
            Unicode.Scalar("a").value,
            Unicode.Scalar("b").value,
            Unicode.Scalar("c").value,
        ])
    }

    func testOnEachReturnsOriginalStringUnchanged() {
        let source = registerRuntimeObject(RuntimeStringBox("hello"))
        let identity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in 0 }
        var thrown = 0
        let result = kk_string_onEach(
            source,
            unsafeBitCast(identity, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "hello")
    }

    func testOnEachEmptyStringDoesNotCallAction() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        let shouldNotRun: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
            // If called, mark failure by returning a non-zero sentinel we detect
            // via the global collector
            RuntimeStringHOFTests._onEachCollector.append(99)
            return 0
        }
        RuntimeStringHOFTests._onEachCollector = []
        var thrown = 0
        let result = kk_string_onEach(
            source,
            unsafeBitCast(shouldNotRun, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "")
        XCTAssertTrue(RuntimeStringHOFTests._onEachCollector.isEmpty)
    }

    // MARK: - STDLIB-TEXT-FN-040: String.onEachIndexed

    func testOnEachIndexedVisitsAllCharsWithCorrectIndices() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        let action: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, charRaw, _ in
            RuntimeStringHOFTests._onEachIndexedCollector.append((index, UInt32(charRaw)))
            return 0
        }
        RuntimeStringHOFTests._onEachIndexedCollector = []
        var thrown = 0

        let result = kk_string_onEachIndexed(
            source,
            unsafeBitCast(action, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "abc")
        XCTAssertEqual(RuntimeStringHOFTests._onEachIndexedCollector.map(\.0), [0, 1, 2])
        XCTAssertEqual(RuntimeStringHOFTests._onEachIndexedCollector.map(\.1), [
            Unicode.Scalar("a").value,
            Unicode.Scalar("b").value,
            Unicode.Scalar("c").value,
        ])
    }

    func testOnEachIndexedReturnsOriginalStringUnchanged() {
        let source = registerRuntimeObject(RuntimeStringBox("hello"))
        let action: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _ in 0 }
        var thrown = 0

        let result = kk_string_onEachIndexed(
            source,
            unsafeBitCast(action, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "hello")
    }

    func testOnEachIndexedEmptyStringDoesNotCallAction() {
        let source = registerRuntimeObject(RuntimeStringBox(""))
        let shouldNotRun: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, charRaw, _ in
            RuntimeStringHOFTests._onEachIndexedCollector.append((index, UInt32(charRaw)))
            return 0
        }
        RuntimeStringHOFTests._onEachIndexedCollector = []
        var thrown = 0

        let result = kk_string_onEachIndexed(
            source,
            unsafeBitCast(shouldNotRun, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "")
        XCTAssertTrue(RuntimeStringHOFTests._onEachIndexedCollector.isEmpty)
    }

    func testOnEachIndexedPropagatesThrownException() {
        let source = registerRuntimeObject(RuntimeStringBox("abc"))
        let throwOnB: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, charRaw, outThrown in
            if charRaw == Int(Unicode.Scalar("b").value) {
                outThrown?.pointee = registerRuntimeObject(RuntimeStringBox("boom"))
                return 0
            }
            RuntimeStringHOFTests._onEachIndexedCollector.append((index, UInt32(charRaw)))
            return 0
        }
        RuntimeStringHOFTests._onEachIndexedCollector = []
        var thrown = 0

        _ = kk_string_onEachIndexed(
            source,
            unsafeBitCast(throwOnB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(RuntimeStringHOFTests._onEachIndexedCollector.map(\.0), [0])
        XCTAssertEqual(RuntimeStringHOFTests._onEachIndexedCollector.map(\.1), [Unicode.Scalar("a").value])
    }

    // Thread-unsafe side-channel used only from single-threaded tests above.
    nonisolated(unsafe) private static var _onEachCollector: [UInt32] = []
    nonisolated(unsafe) private static var _onEachIndexedCollector: [(Int, UInt32)] = []

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
