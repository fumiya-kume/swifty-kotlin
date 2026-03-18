@testable import Runtime
import XCTest

/// Edge case tests for the kk_int_countOneBits, kk_int_countLeadingZeroBits,
/// kk_int_countTrailingZeroBits runtime functions (STDLIB-604, STDLIB-605, STDLIB-606).
///
/// These implement Kotlin `Int.countOneBits`, `Int.countLeadingZeroBits`, and
/// `Int.countTrailingZeroBits` with Kotlin Int (32-bit signed) semantics:
/// the Swift Int argument is truncated to Int32 before querying bit properties.
final class RuntimeBitCountTests: IsolatedRuntimeXCTestCase {

    // MARK: - Shared constants

    /// 0xAAAAAAAA as a signed Int, converted via two's complement.
    private static let alternating0xAAAAAAAA = Int(Int32(bitPattern: 0xAAAA_AAAA))

    // MARK: - countOneBits (STDLIB-604)

    func testCountOneBits_zero() {
        XCTAssertEqual(kk_int_countOneBits(0), 0)
    }

    func testCountOneBits_one() {
        XCTAssertEqual(kk_int_countOneBits(1), 1)
    }

    func testCountOneBits_minusOne() {
        // Kotlin: (-1).countOneBits() == 32 (all 32 bits set)
        XCTAssertEqual(kk_int_countOneBits(-1), 32)
    }

    func testCountOneBits_int32Max() {
        // Int32.max == 0x7FFF_FFFF -> 31 bits set
        XCTAssertEqual(kk_int_countOneBits(Int(Int32.max)), 31)
    }

    func testCountOneBits_int32Min() {
        // Int32.min == 0x8000_0000 -> 1 bit set (sign bit)
        XCTAssertEqual(kk_int_countOneBits(Int(Int32.min)), 1)
    }

    func testCountOneBits_powersOfTwo() {
        // Each power of two has exactly 1 bit set
        for shift in 0..<31 {
            let value = 1 << shift
            XCTAssertEqual(
                kk_int_countOneBits(value), 1,
                "Expected 1 bit set for 1 << \(shift)"
            )
        }
    }

    func testCountOneBits_alternatingPattern_0x55555555() {
        // 0x55555555 = 0101...0101 -> 16 bits set
        XCTAssertEqual(kk_int_countOneBits(0x5555_5555), 16)
    }

    func testCountOneBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA = 1010...1010 -> 16 bits set
        XCTAssertEqual(kk_int_countOneBits(Self.alternating0xAAAAAAAA), 16)
    }

    // MARK: - countLeadingZeroBits (STDLIB-605)

    func testCountLeadingZeroBits_zero() {
        // All 32 bits are zero
        XCTAssertEqual(kk_int_countLeadingZeroBits(0), 32)
    }

    func testCountLeadingZeroBits_one() {
        // 0x00000001 -> 31 leading zeros
        XCTAssertEqual(kk_int_countLeadingZeroBits(1), 31)
    }

    func testCountLeadingZeroBits_minusOne() {
        // 0xFFFFFFFF -> MSB is set, 0 leading zeros
        XCTAssertEqual(kk_int_countLeadingZeroBits(-1), 0)
    }

    func testCountLeadingZeroBits_int32Max() {
        // 0x7FFFFFFF -> MSB is 0, 1 leading zero
        XCTAssertEqual(kk_int_countLeadingZeroBits(Int(Int32.max)), 1)
    }

    func testCountLeadingZeroBits_int32Min() {
        // 0x80000000 -> MSB is set, 0 leading zeros
        XCTAssertEqual(kk_int_countLeadingZeroBits(Int(Int32.min)), 0)
    }

    func testCountLeadingZeroBits_powersOfTwo() {
        // 1 << n has (31 - n) leading zeros
        for shift in 0..<31 {
            let value = 1 << shift
            XCTAssertEqual(
                kk_int_countLeadingZeroBits(value), 31 - shift,
                "Expected \(31 - shift) leading zeros for 1 << \(shift)"
            )
        }
    }

    func testCountLeadingZeroBits_alternatingPattern_0x55555555() {
        // 0x55555555 -> MSB (bit 31) is 0, bit 30 is 1 -> 1 leading zero
        XCTAssertEqual(kk_int_countLeadingZeroBits(0x5555_5555), 1)
    }

    func testCountLeadingZeroBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA -> MSB is set -> 0 leading zeros
        XCTAssertEqual(kk_int_countLeadingZeroBits(Self.alternating0xAAAAAAAA), 0)
    }

    // MARK: - countTrailingZeroBits (STDLIB-606)

    func testCountTrailingZeroBits_zero() {
        // All 32 bits are zero -> 32 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(0), 32)
    }

    func testCountTrailingZeroBits_one() {
        // 0x00000001 -> LSB is set, 0 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(1), 0)
    }

    func testCountTrailingZeroBits_minusOne() {
        // 0xFFFFFFFF -> LSB is set, 0 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(-1), 0)
    }

    func testCountTrailingZeroBits_int32Max() {
        // 0x7FFFFFFF -> LSB is set, 0 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(Int(Int32.max)), 0)
    }

    func testCountTrailingZeroBits_int32Min() {
        // 0x80000000 -> only MSB set, 31 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(Int(Int32.min)), 31)
    }

    func testCountTrailingZeroBits_powersOfTwo() {
        // 1 << n has exactly n trailing zeros
        for shift in 0..<31 {
            let value = 1 << shift
            XCTAssertEqual(
                kk_int_countTrailingZeroBits(value), shift,
                "Expected \(shift) trailing zeros for 1 << \(shift)"
            )
        }
    }

    func testCountTrailingZeroBits_alternatingPattern_0x55555555() {
        // 0x55555555 -> LSB is set -> 0 trailing zeros
        XCTAssertEqual(kk_int_countTrailingZeroBits(0x5555_5555), 0)
    }

    func testCountTrailingZeroBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA -> LSB is 0, bit 1 is set -> 1 trailing zero
        XCTAssertEqual(kk_int_countTrailingZeroBits(Self.alternating0xAAAAAAAA), 1)
    }
}
