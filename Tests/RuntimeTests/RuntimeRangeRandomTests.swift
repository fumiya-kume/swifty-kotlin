@testable import Runtime
import XCTest

final class RuntimeRangeRandomTests: XCTestCase {
    func testIntRangeRandomReturnsValueInsideBounds() {
        let range = kk_op_rangeTo(1, 5)
        var thrown = 0
        let value = kk_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, 1)
        XCTAssertLessThanOrEqual(value, 5)
    }

    func testIntRangeRandomHandlesFullSpan() {
        let range = kk_op_rangeTo(Int.min, Int.max)
        var thrown = 0
        let value = kk_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, Int.min)
        XCTAssertLessThanOrEqual(value, Int.max)
    }

    func testIntRangeRandomRespectsStep() {
        let range = kk_op_step(kk_op_rangeTo(1, 10), 2, nil)
        for _ in 0..<20 {
            var thrown = 0
            let value = kk_range_random(range, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertGreaterThanOrEqual(value, 1)
            XCTAssertLessThanOrEqual(value, 10)
            XCTAssertEqual(value % 2, 1)
        }
    }

    func testRandomNextIntRangeObjectReturnsValueInsideBounds() {
        let random = kk_random_create_seeded(42)
        let range = kk_op_rangeTo(10, 15)
        var thrown = 0
        let value = kk_random_nextInt_rangeObject(random, range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, 10)
        XCTAssertLessThanOrEqual(value, 15)
    }

    func testRandomNextIntRangeObjectThrowsForEmptyRange() {
        let random = kk_random_create_seeded(42)
        let range = kk_op_rangeTo(15, 10)
        var thrown = 0
        let value = kk_random_nextInt_rangeObject(random, range, &thrown)
        XCTAssertEqual(value, 0)
        XCTAssertNotEqual(thrown, 0, "nextInt(range) must throw for an empty range")
    }

    func testLongRangeRandomReturnsValueInsideBounds() {
        let lower = Int(Int32.max) + 1
        let upper = Int(Int32.max) + 100
        let range = kk_long_rangeTo(lower, upper)
        var thrown = 0
        let value = kk_long_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, lower)
        XCTAssertLessThanOrEqual(value, upper)
    }

    func testCharRangeRandomReturnsValueInsideBounds() {
        let lower = kk_box_char(Int(Unicode.Scalar("a").value))
        let upper = kk_box_char(Int(Unicode.Scalar("f").value))
        let range = kk_char_rangeTo(lower, upper)
        var thrown = 0
        let value = kk_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, Int(Unicode.Scalar("a").value))
        XCTAssertLessThanOrEqual(value, Int(Unicode.Scalar("f").value))
    }

    func testUIntRangeRandomReturnsValueInsideBounds() {
        let lower = Int(bitPattern: UInt(4_294_967_292))
        let upper = Int(bitPattern: UInt(4_294_967_295))
        let range = kk_uint_rangeTo(lower, upper)
        var thrown = 0
        let value = kk_uint_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        let unsignedValue = UInt(bitPattern: value)
        XCTAssertGreaterThanOrEqual(unsignedValue, UInt(4_294_967_292))
        XCTAssertLessThanOrEqual(unsignedValue, UInt(4_294_967_295))
    }

    func testULongRangeRandomHandlesFullSpan() {
        let range = kk_ulong_rangeTo(0, Int(bitPattern: UInt.max))
        var thrown = 0
        _ = kk_ulong_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
    }

    func testRangeRandomWithRandomOverloadsReturnValuesInsideBounds() {
        let random = kk_random_create_seeded(123)
        var thrown = 0

        let intValue = kk_range_random_random(kk_op_rangeTo(1, 5), random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(intValue, 1)
        XCTAssertLessThanOrEqual(intValue, 5)

        let longValue = kk_long_range_random_random(kk_long_rangeTo(10, 15), random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(longValue, 10)
        XCTAssertLessThanOrEqual(longValue, 15)

        let charValue = kk_char_range_random_random(
            kk_char_rangeTo(
                kk_box_char(Int(Unicode.Scalar("a").value)),
                kk_box_char(Int(Unicode.Scalar("f").value))
            ),
            random,
            &thrown
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(charValue, Int(Unicode.Scalar("a").value))
        XCTAssertLessThanOrEqual(charValue, Int(Unicode.Scalar("f").value))

        let uintValue = kk_uint_range_random_random(kk_uint_rangeTo(1, 5), random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(UInt(bitPattern: uintValue), 1)
        XCTAssertLessThanOrEqual(UInt(bitPattern: uintValue), 5)

        let ulongValue = kk_ulong_range_random_random(kk_ulong_rangeTo(1, 5), random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(UInt(bitPattern: ulongValue), 1)
        XCTAssertLessThanOrEqual(UInt(bitPattern: ulongValue), 5)
    }
}
