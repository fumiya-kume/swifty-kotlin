@testable import Runtime
import XCTest

final class RuntimeRangeRandomTests: IsolatedRuntimeXCTestCase {
    private func seededRandom(_ seed: Int = 12345) -> Int {
        kk_random_create_seeded(seed)
    }

    func testIntRangeRandomReturnsValueInsideBounds() {
        let range = kk_op_rangeTo(1, 5)
        let random = seededRandom()
        var thrown = 0
        let value = kk_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, 1)
        XCTAssertLessThanOrEqual(value, 5)
    }

    func testIntRangeRandomHandlesFullSpan() {
        let range = kk_op_rangeTo(Int.min, Int.max)
        let random = seededRandom()
        var thrown = 0
        let value = kk_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, Int.min)
        XCTAssertLessThanOrEqual(value, Int.max)
    }

    func testIntRangeRandomRespectsStep() {
        let range = kk_op_step(kk_op_rangeTo(1, 10), 2, nil)
        let random = seededRandom()
        for _ in 0..<20 {
            var thrown = 0
            let value = kk_range_random(range, random, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertGreaterThanOrEqual(value, 1)
            XCTAssertLessThanOrEqual(value, 10)
            XCTAssertEqual(value % 2, 1)
        }
    }

    func testLongRangeRandomReturnsValueInsideBounds() {
        let lower = Int(Int32.max) + 1
        let upper = Int(Int32.max) + 100
        let range = kk_long_rangeTo(lower, upper)
        let random = seededRandom()
        var thrown = 0
        let value = kk_long_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, lower)
        XCTAssertLessThanOrEqual(value, upper)
    }

    func testCharRangeRandomReturnsValueInsideBounds() {
        let lower = kk_box_char(Int(Unicode.Scalar("a").value))
        let upper = kk_box_char(Int(Unicode.Scalar("f").value))
        let range = kk_char_rangeTo(lower, upper)
        let random = seededRandom()
        var thrown = 0
        let value = kk_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, Int(Unicode.Scalar("a").value))
        XCTAssertLessThanOrEqual(value, Int(Unicode.Scalar("f").value))
    }

    func testUIntRangeRandomReturnsValueInsideBounds() {
        let lower = Int(bitPattern: UInt(4_294_967_292))
        let upper = Int(bitPattern: UInt(4_294_967_295))
        let range = kk_uint_rangeTo(lower, upper)
        let random = seededRandom()
        var thrown = 0
        let value = kk_uint_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
        let unsignedValue = UInt(bitPattern: value)
        XCTAssertGreaterThanOrEqual(unsignedValue, UInt(4_294_967_292))
        XCTAssertLessThanOrEqual(unsignedValue, UInt(4_294_967_295))
    }

    func testULongRangeRandomHandlesFullSpan() {
        let range = kk_ulong_rangeTo(0, Int(bitPattern: UInt.max))
        let random = seededRandom()
        var thrown = 0
        _ = kk_ulong_range_random(range, random, &thrown)
        XCTAssertEqual(thrown, 0)
    }
}
