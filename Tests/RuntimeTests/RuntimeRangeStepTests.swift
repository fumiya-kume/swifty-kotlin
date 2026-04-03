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

    func testRangeContainsBoundaries() {
        let range = kk_op_rangeTo(1, 10)
        XCTAssertEqual(kk_op_contains(range, 1), 1)
        XCTAssertEqual(kk_op_contains(range, 10), 1)
        XCTAssertEqual(kk_op_contains(range, 0), 0)
        XCTAssertEqual(kk_op_contains(range, 11), 0)
    }

    func testRangeToIntArray() {
        let range = kk_op_rangeTo(1, 10)
        let array = runtimeArrayBox(from: kk_range_toIntArray(range))
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.elements.count, 10)
        XCTAssertEqual(array?.elements[0], 1)
        XCTAssertEqual(array?.elements[9], 10)
    }

    func testRangeReversedToList() {
        let range = kk_op_rangeTo(1, 5)
        let reversed = kk_range_reversed(range)
        XCTAssertEqual(kk_range_first(reversed), 5)
        XCTAssertEqual(kk_range_last(reversed), 1)
        XCTAssertEqual(kk_range_count(reversed), 5)

        let list = kk_range_toList(reversed)
        XCTAssertEqual(kk_list_size(list), 5)
        XCTAssertEqual(kk_list_get(list, 0), 5)
        XCTAssertEqual(kk_list_get(list, 4), 1)
    }

    // MARK: - Progression fromClosedRange tests (STDLIB-RANGE-039)

    func testIntProgressionFromClosedRange() {
        let progression = kk_int_progression_fromClosedRange(0, 1, 10, 2, nil)
        XCTAssertEqual(kk_range_first(progression), 1)
        XCTAssertEqual(kk_range_last(progression), 9)
        XCTAssertEqual(kk_range_count(progression), 5) // 1,3,5,7,9
    }

    func testLongProgressionFromClosedRange() {
        let progression = kk_long_progression_fromClosedRange(0, 1, 10, 3, nil)
        XCTAssertEqual(kk_range_first(progression), 1)
        XCTAssertEqual(kk_range_last(progression), 10)
        XCTAssertEqual(kk_range_count(progression), 4) // 1,4,7,10
    }

    func testUIntProgressionFromClosedRange() {
        let progression = kk_uint_progression_fromClosedRange(0, 1, 10, 2, nil)
        XCTAssertEqual(kk_range_first(progression), 1)
        XCTAssertEqual(kk_range_last(progression), 9)
        let list = kk_uint_range_toList(progression)
        XCTAssertEqual(kk_list_size(list), 5)
    }

    func testULongProgressionFromClosedRange() {
        let progression = kk_ulong_progression_fromClosedRange(0, 1, 10, 3, nil)
        XCTAssertEqual(kk_range_first(progression), 1)
        XCTAssertEqual(kk_range_last(progression), 10)
        let list = kk_ulong_range_toList(progression)
        XCTAssertEqual(kk_list_size(list), 4)
    }

    // MARK: - UIntProgression tests (STDLIB-RANGE-039)

    func testUIntRangeTo() {
        let range = kk_uint_rangeTo(1, 10)
        XCTAssertEqual(kk_range_first(range), 1)
        XCTAssertEqual(kk_range_last(range), 10)
        let list = kk_uint_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 10)
    }

    func testUIntDownTo() {
        let range = kk_uint_downTo(10, 1)
        XCTAssertEqual(kk_range_first(range), 10)
        XCTAssertEqual(kk_range_last(range), 1)
        XCTAssertEqual(kk_range_count(range), 10)
    }

    func testUIntStep() {
        let range = kk_uint_rangeTo(1, 10)
        let stepped = kk_uint_step(range, 3)
        XCTAssertEqual(kk_range_first(stepped), 1)
        XCTAssertEqual(kk_range_last(stepped), 10)
        let list = kk_uint_range_toList(stepped)
        XCTAssertEqual(kk_list_size(list), 4) // 1,4,7,10
    }

    func testUIntRangeReversed() {
        let range = kk_uint_rangeTo(1, 5)
        let reversed = kk_uint_range_reversed(range)
        XCTAssertEqual(kk_range_first(reversed), 5)
        XCTAssertEqual(kk_range_last(reversed), 1)
        XCTAssertEqual(kk_range_count(reversed), 5)
    }

    func testUIntRangeContainsAndIsEmpty() {
        let range = kk_uint_rangeTo(1, 10)
        XCTAssertEqual(kk_uint_range_contains(range, 5), 1)
        XCTAssertEqual(kk_uint_range_contains(range, 15), 0)
        XCTAssertEqual(kk_uint_range_isEmpty(range), 0)
        XCTAssertEqual(kk_uint_range_isEmpty(kk_uint_rangeTo(10, 1)), 1)
    }

    func testUIntRangeStartEndAliases() {
        let range = kk_uint_rangeTo(2, 6)
        XCTAssertEqual(kk_uint_range_first(range), 2)
        XCTAssertEqual(kk_uint_range_last(range), 6)
    }

    func testUIntRangeToUIntArray() {
        let range = kk_uint_step(kk_uint_rangeTo(1, 7), 3)
        let array = kk_uint_range_toUIntArray(range)
        XCTAssertEqual(kk_list_size(array), 3)
        XCTAssertEqual(kk_list_get(array, 0), 1)
        XCTAssertEqual(kk_list_get(array, 1), 4)
        XCTAssertEqual(kk_list_get(array, 2), 7)
    }

    func testUIntRangeIteratorUsesUnsignedIterator() {
        let start = Int(bitPattern: UInt.max - 2)
        let end = Int(bitPattern: UInt.max)
        let range = kk_uint_rangeTo(start, end)
        let iterator = kk_uint_range_iterator(range)
        XCTAssertEqual(kk_uint_range_hasNext(iterator), 1)
        XCTAssertEqual(kk_uint_range_next(iterator), start)
        XCTAssertEqual(kk_uint_range_hasNext(iterator), 1)
        XCTAssertEqual(kk_uint_range_next(iterator), Int(bitPattern: UInt.max - 1))
        XCTAssertEqual(kk_uint_range_hasNext(iterator), 1)
        XCTAssertEqual(kk_uint_range_next(iterator), Int(bitPattern: UInt.max))
        XCTAssertEqual(kk_uint_range_hasNext(iterator), 0)
    }

    func testUIntUntilToList() {
        let range = kk_uint_step(kk_op_rangeUntil(1, 5), 1)
        let list = kk_uint_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 4)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 3), 4)
    }

    // MARK: - ULongProgression tests (STDLIB-RANGE-039)

    func testULongRangeTo() {
        let range = kk_ulong_rangeTo(1, 10)
        XCTAssertEqual(kk_range_first(range), 1)
        XCTAssertEqual(kk_range_last(range), 10)
        let list = kk_ulong_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 10)
    }

    func testULongDownTo() {
        let range = kk_ulong_downTo(10, 1)
        XCTAssertEqual(kk_range_first(range), 10)
        XCTAssertEqual(kk_range_last(range), 1)
        XCTAssertEqual(kk_range_count(range), 10)
    }

    func testULongStep() {
        let range = kk_ulong_rangeTo(1, 10)
        let stepped = kk_ulong_step(range, 3)
        XCTAssertEqual(kk_range_first(stepped), 1)
        XCTAssertEqual(kk_range_last(stepped), 10)
        let list = kk_ulong_range_toList(stepped)
        XCTAssertEqual(kk_list_size(list), 4) // 1,4,7,10
    }

    func testULongRangeReversed() {
        let range = kk_ulong_rangeTo(1, 5)
        let reversed = kk_ulong_range_reversed(range)
        XCTAssertEqual(kk_range_first(reversed), 5)
        XCTAssertEqual(kk_range_last(reversed), 1)
        XCTAssertEqual(kk_range_count(reversed), 5)
    }

    func testULongRangeToULongArray() {
        let range = kk_ulong_step(kk_ulong_rangeTo(1, 7), 3)
        let array = kk_ulong_range_toULongArray(range)
        XCTAssertEqual(kk_list_size(array), 3)
        XCTAssertEqual(kk_list_get(array, 0), 1)
        XCTAssertEqual(kk_list_get(array, 1), 4)
        XCTAssertEqual(kk_list_get(array, 2), 7)
    }
}
