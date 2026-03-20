@testable import Runtime
import XCTest

final class RuntimeRandomTests: IsolatedRuntimeXCTestCase {
    // MARK: - nextLong

    func testNextLongReturnsValueIn64BitRange() {
        // Verify nextLong handles 64-bit ranges by calling the bounded variant
        // with bounds above Int32.max to prove it isn't silently truncating.
        var thrown: Int = 0
        let lowerBound = Int(Int32.max) + 1   // 2_147_483_648
        let upperBound = Int(Int32.max) + 100  // 2_147_483_747
        let result = kk_random_nextLong_range(0, lowerBound, upperBound, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= lowerBound && result < upperBound,
                       "nextLong range should produce a value in [\(lowerBound), \(upperBound)), got \(result)")
    }

    // MARK: - nextLong(until)

    func testNextLongUntilReturnsWithinRange() {
        var thrown: Int = 0
        let result = kk_random_nextLong_until(0, 100, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= 0 && result < 100)
    }

    func testNextLongUntilThrowsOnNonPositive() {
        var thrown: Int = 0
        _ = kk_random_nextLong_until(0, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=0 should produce an exception")
    }

    func testNextLongUntilThrowsOnNegative() {
        var thrown: Int = 0
        _ = kk_random_nextLong_until(0, -5, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=-5 should produce an exception")
    }

    // MARK: - nextLong(from, until)

    func testNextLongRangeReturnsWithinRange() {
        var thrown: Int = 0
        let result = kk_random_nextLong_range(0, 10, 20, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= 10 && result < 20)
    }

    func testNextLongRangeThrowsOnEmptyRange() {
        var thrown: Int = 0
        _ = kk_random_nextLong_range(0, 10, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "from==until should produce an exception")
    }

    func testNextLongRangeThrowsOnInvertedRange() {
        var thrown: Int = 0
        _ = kk_random_nextLong_range(0, 20, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "from>until should produce an exception")
    }

    // MARK: - nextFloat

    func testNextFloatReturnsRawBitsInUnitRange() {
        let bits = kk_random_nextFloat(0)
        // The result is raw Float bits (no boxing), consistent with math functions.
        let f = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
        XCTAssertTrue(f >= 0.0 && f < 1.0, "nextFloat should return a value in [0, 1), got \(f)")
    }
}
