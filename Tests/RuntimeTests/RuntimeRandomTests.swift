@testable import Runtime
import XCTest

final class RuntimeRandomTests: XCTestCase {
    // MARK: - Default

    func testRandomDefaultReturnsDefaultReceiver() {
        XCTAssertEqual(kk_random_default(), 0)
    }

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

    // MARK: - range.random(random)

    func testRangeRandomReturnsValuesWithinRange() {
        let random = kk_random_create_seeded(7)
        var thrown: Int = 0

        let intRange = kk_op_rangeTo(10, 20)
        let intValue = kk_range_random_random(intRange, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_range_contains(intRange, intValue), 1)

        thrown = 0
        let longRange = kk_long_rangeTo(100, 110)
        let longValue = kk_long_range_random_random(longRange, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_long_range_contains(longRange, longValue), 1)

        thrown = 0
        let uintRange = kk_uint_rangeTo(10, 20)
        let uintValue = kk_uint_range_random_random(uintRange, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_uint_range_contains(uintRange, uintValue), 1)

        thrown = 0
        let ulongRange = kk_ulong_rangeTo(100, 110)
        let ulongValue = kk_ulong_range_random_random(ulongRange, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_ulong_range_contains(ulongRange, ulongValue), 1)

        thrown = 0
        let charRange = kk_char_rangeTo(kk_box_char(Int(Character("a").unicodeScalars.first!.value)),
                                        kk_box_char(Int(Character("z").unicodeScalars.first!.value)))
        let charValue = kk_range_random_random(charRange, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_range_contains(charRange, charValue), 1)
    }

    // MARK: - nextFloat

    func testNextFloatReturnsRawBitsInUnitRange() {
        let bits = kk_random_nextFloat(0)
        // The result is raw Float bits (no boxing), consistent with math functions.
        let f = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
        XCTAssertTrue(f >= 0.0 && f < 1.0, "nextFloat should return a value in [0, 1), got \(f)")
    }

    // MARK: - nextFloat(until)

    func testNextFloatUntilReturnsWithinRange() {
        var thrown: Int = 0
        let untilBits = Int(Float(10.0).bitPattern)
        let bits = kk_random_nextFloat_until(0, untilBits, &thrown)
        XCTAssertEqual(thrown, 0)
        let f = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
        XCTAssertTrue(f >= 0.0 && f < 10.0, "nextFloat(until=10) should return a value in [0, 10), got \(f)")
    }

    func testNextFloatUntilThrowsOnZero() {
        var thrown: Int = 0
        let untilBits = Int(Float(0.0).bitPattern)
        _ = kk_random_nextFloat_until(0, untilBits, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=0 should produce an exception")
    }

    func testNextFloatUntilThrowsOnNegative() {
        var thrown: Int = 0
        let untilBits = Int(Float(-5.0).bitPattern)
        _ = kk_random_nextFloat_until(0, untilBits, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=-5 should produce an exception")
    }
}
