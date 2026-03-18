@testable import Runtime
import XCTest

/// Runtime-level tests for range step alignment, empty progressions,
/// and non-trapping behavior on extreme Int ranges.
final class RuntimeRangeStepTests: IsolatedRuntimeXCTestCase {

    // MARK: - Step alignment (positive step)

    func testStepAlignmentPositiveStep() {
        // (1..10) step 3 -> elements: 1, 4, 7, 10; last aligned to 10
        let range = kk_op_rangeTo(1, 10)
        let stepped = kk_op_step(range, 3)
        XCTAssertEqual(kk_range_first(stepped), 1)
        XCTAssertEqual(kk_range_last(stepped), 10)
        XCTAssertEqual(kk_range_count(stepped), 4)
    }

    func testStepAlignmentPositiveStepUneven() {
        // (1..9) step 2 -> elements: 1, 3, 5, 7, 9; last aligned to 9
        let range = kk_op_rangeTo(1, 9)
        let stepped = kk_op_step(range, 2)
        XCTAssertEqual(kk_range_first(stepped), 1)
        XCTAssertEqual(kk_range_last(stepped), 9)
        XCTAssertEqual(kk_range_count(stepped), 5)
    }

    func testStepAlignmentPositiveStepAlignedDown() {
        // (1..10) step 4 -> elements: 1, 5, 9; last aligned to 9
        let range = kk_op_rangeTo(1, 10)
        let stepped = kk_op_step(range, 4)
        XCTAssertEqual(kk_range_first(stepped), 1)
        XCTAssertEqual(kk_range_last(stepped), 9)
        XCTAssertEqual(kk_range_count(stepped), 3)
    }

    // MARK: - Step alignment (negative step / downTo)

    func testStepAlignmentNegativeStep() {
        // (10 downTo 1) step 3 -> elements: 10, 7, 4, 1; last aligned to 1
        let range = kk_op_downTo(10, 1)
        let stepped = kk_op_step(range, 3)
        XCTAssertEqual(kk_range_first(stepped), 10)
        XCTAssertEqual(kk_range_last(stepped), 1)
        XCTAssertEqual(kk_range_count(stepped), 4)
    }

    func testStepAlignmentNegativeStepAlignedUp() {
        // (10 downTo 1) step 4 -> elements: 10, 6, 2; last aligned to 2
        let range = kk_op_downTo(10, 1)
        let stepped = kk_op_step(range, 4)
        XCTAssertEqual(kk_range_first(stepped), 10)
        XCTAssertEqual(kk_range_last(stepped), 2)
        XCTAssertEqual(kk_range_count(stepped), 3)
    }

    // MARK: - Empty progressions preserve last

    func testEmptyProgressionPositiveStep() {
        // (10 until 10) step 2 -> empty; first=10, last=9 (from rangeUntil)
        let range = kk_op_rangeUntil(10, 10)
        let stepped = kk_op_step(range, 2)
        XCTAssertEqual(kk_range_first(stepped), 10)
        XCTAssertEqual(kk_range_last(stepped), 9)
        XCTAssertEqual(kk_range_count(stepped), 0)
    }

    func testEmptyProgressionPositiveStepReversed() {
        // (5..3) step 2 -> empty (first > last for positive step)
        let range = kk_op_rangeTo(5, 3)
        let stepped = kk_op_step(range, 2)
        XCTAssertEqual(kk_range_count(stepped), 0)
    }

    func testEmptyProgressionNegativeStep() {
        // (1 downTo 3) step 3 -> empty (first < last for negative step)
        let range = kk_op_downTo(1, 3)
        let stepped = kk_op_step(range, 3)
        XCTAssertEqual(kk_range_count(stepped), 0)
    }

    // MARK: - Non-trapping on extreme Int ranges

    func testExtremeRangeCountDoesNotTrap() {
        // Int.min..Int.max should not trap
        let range = kk_op_rangeTo(Int.min, Int.max)
        // count is (Int.max - Int.min) / 1 + 1, which uses wrapping arithmetic
        let count = kk_range_count(range)
        // The exact count wraps around: (Int.max &- Int.min) = UInt.max as Int = -1,
        // then -1 / 1 + 1 = 0.  The important thing is it does NOT trap.
        // We just verify it doesn't crash.
        _ = count
    }

    func testExtremeRangeStepDoesNotTrap() {
        // (Int.min..Int.max) step 2 should not trap
        let range = kk_op_rangeTo(Int.min, Int.max)
        let stepped = kk_op_step(range, 2)
        // Should not crash; just verify we get a valid range back
        _ = kk_range_first(stepped)
        _ = kk_range_last(stepped)
    }

    func testExtremeRangeDownToDoesNotTrap() {
        // (Int.max downTo Int.min) step 2 should not trap
        let range = kk_op_downTo(Int.max, Int.min)
        let stepped = kk_op_step(range, 2)
        _ = kk_range_first(stepped)
        _ = kk_range_last(stepped)
    }

    func testStepSingleElementRange() {
        // (5..5) step 1 -> [5]
        let range = kk_op_rangeTo(5, 5)
        let stepped = kk_op_step(range, 1)
        XCTAssertEqual(kk_range_first(stepped), 5)
        XCTAssertEqual(kk_range_last(stepped), 5)
        XCTAssertEqual(kk_range_count(stepped), 1)
    }

    func testRangeToListWithStep() {
        // (1..10) step 3 -> [1, 4, 7, 10]
        let range = kk_op_rangeTo(1, 10)
        let stepped = kk_op_step(range, 3)
        let list = kk_range_toList(stepped)
        XCTAssertEqual(kk_list_size(list), 4)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 1), 4)
        XCTAssertEqual(kk_list_get(list, 2), 7)
        XCTAssertEqual(kk_list_get(list, 3), 10)
    }

    func testDownToToListWithStep() {
        // (10 downTo 1) step 3 -> [10, 7, 4, 1]
        let range = kk_op_downTo(10, 1)
        let stepped = kk_op_step(range, 3)
        let list = kk_range_toList(stepped)
        XCTAssertEqual(kk_list_size(list), 4)
        XCTAssertEqual(kk_list_get(list, 0), 10)
        XCTAssertEqual(kk_list_get(list, 1), 7)
        XCTAssertEqual(kk_list_get(list, 2), 4)
        XCTAssertEqual(kk_list_get(list, 3), 1)
    }

    func testEmptyRangeToListIsEmpty() {
        // (10 until 10) -> empty
        let range = kk_op_rangeUntil(10, 10)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 0)
    }
}
