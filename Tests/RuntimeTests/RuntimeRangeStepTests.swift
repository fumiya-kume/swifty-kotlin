@testable import Runtime
import Testing

/// Runtime-level tests for range step alignment, empty progressions,
/// and non-trapping behavior on extreme Int ranges.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeRangeStepTests {
    // MARK: - Step alignment (positive step)

    @Test func testStepAlignmentPositiveStep() {
        // (1..10) step 3 -> elements: 1, 4, 7, 10; last aligned to 10
        let range = kk_op_rangeTo(1, 10)
        let stepped = __kk_op_step(range, 3, nil)
        #expect(kk_range_first(stepped) == 1)
        #expect(kk_range_last(stepped) == 10)
        #expect(kk_range_count(stepped) == 4)
    }

    @Test func testStepAlignmentPositiveStepUneven() {
        // (1..9) step 2 -> elements: 1, 3, 5, 7, 9; last aligned to 9
        let range = kk_op_rangeTo(1, 9)
        let stepped = __kk_op_step(range, 2, nil)
        #expect(kk_range_first(stepped) == 1)
        #expect(kk_range_last(stepped) == 9)
        #expect(kk_range_count(stepped) == 5)
    }

    @Test func testStepAlignmentPositiveStepAlignedDown() {
        // (1..10) step 4 -> elements: 1, 5, 9; last aligned to 9
        let range = kk_op_rangeTo(1, 10)
        let stepped = __kk_op_step(range, 4, nil)
        #expect(kk_range_first(stepped) == 1)
        #expect(kk_range_last(stepped) == 9)
        #expect(kk_range_count(stepped) == 3)
    }

    // MARK: - Step alignment (negative step / downTo)

    @Test func testStepAlignmentNegativeStep() {
        // (10 downTo 1) step 3 -> elements: 10, 7, 4, 1; last aligned to 1
        let range = __kk_op_downTo(10, 1)
        let stepped = __kk_op_step(range, 3, nil)
        #expect(kk_range_first(stepped) == 10)
        #expect(kk_range_last(stepped) == 1)
        #expect(kk_range_count(stepped) == 4)
    }

    @Test func testStepAlignmentNegativeStepAlignedUp() {
        // (10 downTo 1) step 4 -> elements: 10, 6, 2; last aligned to 2
        let range = __kk_op_downTo(10, 1)
        let stepped = __kk_op_step(range, 4, nil)
        #expect(kk_range_first(stepped) == 10)
        #expect(kk_range_last(stepped) == 2)
        #expect(kk_range_count(stepped) == 3)
    }

    // MARK: - Empty progressions preserve last

    @Test func testEmptyProgressionPositiveStep() {
        // (10 until 10) step 2 -> empty; first=10, last=9 (from rangeUntil)
        let range = __kk_op_rangeUntil(10, 10)
        let stepped = __kk_op_step(range, 2, nil)
        #expect(kk_range_first(stepped) == 10)
        #expect(kk_range_last(stepped) == 9)
        #expect(kk_range_count(stepped) == 0)
    }

    @Test func testEmptyProgressionPositiveStepReversed() {
        // (5..3) step 2 -> empty (first > last for positive step)
        let range = kk_op_rangeTo(5, 3)
        let stepped = __kk_op_step(range, 2, nil)
        #expect(kk_range_count(stepped) == 0)
    }

    @Test func testEmptyProgressionNegativeStep() {
        // (1 downTo 3) step 3 -> empty (first < last for negative step)
        let range = __kk_op_downTo(1, 3)
        let stepped = __kk_op_step(range, 3, nil)
        #expect(kk_range_count(stepped) == 0)
    }

    // MARK: - Non-trapping on extreme Int ranges

    @Test func testExtremeRangeCountDoesNotTrap() {
        // Int.min..Int.max should not trap
        let range = kk_op_rangeTo(Int.min, Int.max)
        // count is (Int.max - Int.min) / 1 + 1, which uses wrapping arithmetic
        let count = kk_range_count(range)
        // The exact count wraps around: (Int.max &- Int.min) = UInt.max as Int = -1,
        // then -1 / 1 + 1 = 0.  The important thing is it does NOT trap.
        // We just verify it doesn't crash.
        _ = count
    }

    @Test func testExtremeRangeStepDoesNotTrap() {
        // (Int.min..Int.max) step 2 should not trap
        let range = kk_op_rangeTo(Int.min, Int.max)
        let stepped = __kk_op_step(range, 2, nil)
        // Should not crash; just verify we get a valid range back
        _ = kk_range_first(stepped)
        _ = kk_range_last(stepped)
    }

    @Test func testExtremeRangeDownToDoesNotTrap() {
        // (Int.max downTo Int.min) step 2 should not trap
        let range = __kk_op_downTo(Int.max, Int.min)
        let stepped = __kk_op_step(range, 2, nil)
        _ = kk_range_first(stepped)
        _ = kk_range_last(stepped)
    }

    @Test func testStepSingleElementRange() {
        // (5..5) step 1 -> [5]
        let range = kk_op_rangeTo(5, 5)
        let stepped = __kk_op_step(range, 1, nil)
        #expect(kk_range_first(stepped) == 5)
        #expect(kk_range_last(stepped) == 5)
        #expect(kk_range_count(stepped) == 1)
    }

    @Test func testRangeToListWithStep() {
        // (1..10) step 3 -> [1, 4, 7, 10]
        let range = kk_op_rangeTo(1, 10)
        let stepped = __kk_op_step(range, 3, nil)
        let list = kk_range_toList(stepped)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 1) == 4)
        #expect(kk_list_get(list, 2) == 7)
        #expect(kk_list_get(list, 3) == 10)
    }

    @Test func testDownToToListWithStep() {
        // (10 downTo 1) step 3 -> [10, 7, 4, 1]
        let range = __kk_op_downTo(10, 1)
        let stepped = __kk_op_step(range, 3, nil)
        let list = kk_range_toList(stepped)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 10)
        #expect(kk_list_get(list, 1) == 7)
        #expect(kk_list_get(list, 2) == 4)
        #expect(kk_list_get(list, 3) == 1)
    }

    @Test func testEmptyRangeToListIsEmpty() {
        // (10 until 10) -> empty
        let range = __kk_op_rangeUntil(10, 10)
        let list = kk_range_toList(range)
        #expect(kk_list_size(list) == 0)
    }

    @Test func testRangeContainsBoundaries() {
        let range = kk_op_rangeTo(1, 10)
        #expect(kk_op_contains(range, 1) == 1)
        #expect(kk_op_contains(range, 10) == 1)
        #expect(kk_op_contains(range, 0) == 0)
        #expect(kk_op_contains(range, 11) == 0)
    }

    @Test func testRangeToIntArray() {
        let range = kk_op_rangeTo(1, 10)
        let array = runtimeArrayBox(from: kk_range_toIntArray(range))
        #expect(array != nil)
        #expect(array?.elements.count == 10)
        #expect(array?.elements[0] == 1)
        #expect(array?.elements[9] == 10)
    }

    @Test func testRangeReversedToList() {
        let range = kk_op_rangeTo(1, 5)
        let reversed = kk_range_reversed(range)
        #expect(kk_range_first(reversed) == 5)
        #expect(kk_range_last(reversed) == 1)
        #expect(kk_range_count(reversed) == 5)

        let list = kk_range_toList(reversed)
        #expect(kk_list_size(list) == 5)
        #expect(kk_list_get(list, 0) == 5)
        #expect(kk_list_get(list, 4) == 1)
    }

    // MARK: - Progression fromClosedRange tests (STDLIB-RANGE-039)

    @Test func testIntProgressionFromClosedRange() {
        let progression = __kk_int_progression_fromClosedRange(0, 1, 10, 2, nil)
        #expect(kk_range_first(progression) == 1)
        #expect(kk_range_last(progression) == 9)
        #expect(kk_range_count(progression) == 5) // 1,3,5,7,9
    }

    @Test func testLongProgressionFromClosedRange() {
        let progression = __kk_long_progression_fromClosedRange(0, 1, 10, 3, nil)
        #expect(kk_range_first(progression) == 1)
        #expect(kk_range_last(progression) == 10)
        #expect(kk_range_count(progression) == 4) // 1,4,7,10
    }

    @Test func testUIntProgressionFromClosedRange() {
        let progression = __kk_uint_progression_fromClosedRange(0, 1, 10, 2, nil)
        #expect(kk_range_first(progression) == 1)
        #expect(kk_range_last(progression) == 9)
        let list = kk_uint_range_toList(progression)
        #expect(kk_list_size(list) == 5)
    }

    @Test func testULongProgressionFromClosedRange() {
        let progression = __kk_ulong_progression_fromClosedRange(0, 1, 10, 3, nil)
        #expect(kk_range_first(progression) == 1)
        #expect(kk_range_last(progression) == 10)
        let list = kk_ulong_range_toList(progression)
        #expect(kk_list_size(list) == 4)
    }

    // MARK: - UIntProgression tests (STDLIB-RANGE-039)

    @Test func testUIntRangeTo() {
        let range = __kk_uint_rangeTo(1, 10)
        #expect(kk_range_first(range) == 1)
        #expect(kk_range_last(range) == 10)
        let list = kk_uint_range_toList(range)
        #expect(kk_list_size(list) == 10)
    }

    @Test func testUIntDownTo() {
        let range = __kk_uint_downTo(10, 1)
        #expect(kk_range_first(range) == 10)
        #expect(kk_range_last(range) == 1)
        #expect(kk_range_count(range) == 10)
    }

    @Test func testUIntStep() {
        let range = __kk_uint_rangeTo(1, 10)
        let stepped = __kk_uint_step(range, 3)
        #expect(kk_range_first(stepped) == 1)
        #expect(kk_range_last(stepped) == 10)
        let list = kk_uint_range_toList(stepped)
        #expect(kk_list_size(list) == 4) // 1,4,7,10
    }

    @Test func testUIntRangeReversed() {
        let range = __kk_uint_rangeTo(1, 5)
        let reversed = kk_uint_range_reversed(range)
        #expect(kk_range_first(reversed) == 5)
        #expect(kk_range_last(reversed) == 1)
        #expect(kk_range_count(reversed) == 5)
    }

    @Test func testUIntRangeContainsAndIsEmpty() {
        let range = __kk_uint_rangeTo(1, 10)
        #expect(kk_uint_range_contains(range, 5) == 1)
        #expect(kk_uint_range_contains(range, 15) == 0)
        #expect(kk_uint_range_isEmpty(range) == 0)
        #expect(kk_uint_range_isEmpty(__kk_uint_rangeTo(10, 1)) == 1)
    }

    @Test func testUIntRangeStartEndAliases() {
        let range = __kk_uint_rangeTo(2, 6)
        #expect(kk_uint_range_first(range) == 2)
        #expect(kk_uint_range_last(range) == 6)
    }

    @Test func testUIntRangeToUIntArray() {
        let range = __kk_uint_step(__kk_uint_rangeTo(1, 7), 3)
        let array = kk_uint_range_toUIntArray(range)
        #expect(kk_list_size(array) == 3)
        #expect(kk_list_get(array, 0) == 1)
        #expect(kk_list_get(array, 1) == 4)
        #expect(kk_list_get(array, 2) == 7)
    }

    @Test func testUIntRangeIteratorUsesUnsignedIterator() {
        let start = Int(bitPattern: UInt.max - 2)
        let end = Int(bitPattern: UInt.max)
        let range = __kk_uint_rangeTo(start, end)
        let iterator = __kk_uint_range_iterator(range)
        #expect(__kk_uint_range_hasNext(iterator) == 1)
        #expect(__kk_uint_range_next(iterator) == start)
        #expect(__kk_uint_range_hasNext(iterator) == 1)
        #expect(__kk_uint_range_next(iterator) == Int(bitPattern: UInt.max - 1))
        #expect(__kk_uint_range_hasNext(iterator) == 1)
        #expect(__kk_uint_range_next(iterator) == Int(bitPattern: UInt.max))
        #expect(__kk_uint_range_hasNext(iterator) == 0)
    }

    @Test func testUIntUntilToList() {
        let range = __kk_uint_step(__kk_op_rangeUntil(1, 5), 1)
        let list = kk_uint_range_toList(range)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 3) == 4)
    }

    // MARK: - ULongProgression tests (STDLIB-RANGE-039)

    @Test func testULongRangeTo() {
        let range = kk_ulong_rangeTo(1, 10)
        #expect(kk_range_first(range) == 1)
        #expect(kk_range_last(range) == 10)
        let list = kk_ulong_range_toList(range)
        #expect(kk_list_size(list) == 10)
    }

    @Test func testULongDownTo() {
        let range = __kk_ulong_downTo(10, 1)
        #expect(kk_range_first(range) == 10)
        #expect(kk_range_last(range) == 1)
        #expect(kk_range_count(range) == 10)
    }

    @Test func testULongStep() {
        let range = kk_ulong_rangeTo(1, 10)
        let stepped = __kk_ulong_step(range, 3)
        #expect(kk_range_first(stepped) == 1)
        #expect(kk_range_last(stepped) == 10)
        let list = kk_ulong_range_toList(stepped)
        #expect(kk_list_size(list) == 4) // 1,4,7,10
    }

    @Test func testULongRangeReversed() {
        let range = kk_ulong_rangeTo(1, 5)
        let reversed = kk_ulong_range_reversed(range)
        #expect(kk_range_first(reversed) == 5)
        #expect(kk_range_last(reversed) == 1)
        #expect(kk_range_count(reversed) == 5)
    }

    @Test func testULongRangeToULongArray() {
        let range = __kk_ulong_step(kk_ulong_rangeTo(1, 7), 3)
        let array = kk_ulong_range_toULongArray(range)
        #expect(kk_list_size(array) == 3)
        #expect(kk_list_get(array, 0) == 1)
        #expect(kk_list_get(array, 1) == 4)
        #expect(kk_list_get(array, 2) == 7)
    }

    // MARK: - IntRange Additional Features (STDLIB-RANGE-034)

    @Test func testRangeContains() {
        let range = kk_op_rangeTo(1, 10)
        #expect(kk_range_contains(range, 5) == 1)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 0) == 0)
        #expect(kk_range_contains(range, 11) == 0)
    }

    @Test func testRangeContainsWithStep() {
        let range = __kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 4) == 1)
        #expect(kk_range_contains(range, 7) == 1)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 2) == 0)
        #expect(kk_range_contains(range, 5) == 0)
    }

    @Test func testRangeContainsNegativeStep() {
        let range = __kk_op_downTo(10, 1)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 5) == 1)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 0) == 0)
        #expect(kk_range_contains(range, 11) == 0)
    }

    @Test func testRangeContainsWithNegativeStep() {
        let range = __kk_op_step(__kk_op_downTo(10, 1), 3, nil)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 7) == 1)
        #expect(kk_range_contains(range, 4) == 1)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 9) == 0)
        #expect(kk_range_contains(range, 6) == 0)
    }

    @Test func testRangeStartEnd() {
        let range = kk_op_rangeTo(2, 8)
        #expect(kk_range_first(range) == 2)
        #expect(kk_range_last(range) == 8)
    }

    @Test func testRangeStartEndWithDownTo() {
        let range = __kk_op_downTo(8, 2)
        #expect(kk_range_first(range) == 8)
        #expect(kk_range_last(range) == 2)
    }

    @Test func testRangeReversedWithStep() {
        let range = __kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        let reversed = kk_range_reversed(range)
        #expect(kk_range_first(reversed) == 10)
        #expect(kk_range_last(reversed) == 1)
        #expect(kk_range_count(reversed) == 4)

        let list = kk_range_toList(reversed)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 10)
        #expect(kk_list_get(list, 1) == 7)
        #expect(kk_list_get(list, 2) == 4)
        #expect(kk_list_get(list, 3) == 1)
    }

    @Test func testRangeReversedWithNegativeStep() {
        let range = __kk_op_step(__kk_op_downTo(10, 1), 3, nil)
        let reversed = kk_range_reversed(range)
        #expect(kk_range_first(reversed) == 1)
        #expect(kk_range_last(reversed) == 10)
        #expect(kk_range_count(reversed) == 4)

        let list = kk_range_toList(reversed)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 1) == 4)
        #expect(kk_list_get(list, 2) == 7)
        #expect(kk_list_get(list, 3) == 10)
    }

    // MARK: - STDLIB-022: step=0 and step<0 must throw IllegalArgumentException

    @Test func testStepZeroThrowsIllegalArgumentException() {
        // Kotlin spec: step(0) throws IllegalArgumentException
        // "Step must be positive, was: 0."
        var thrown = 0
        let range = kk_op_rangeTo(1, 10)
        _ = __kk_op_step(range, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw IllegalArgumentException (STDLIB-022)")
    }

    @Test func testStepNegativeThrowsIllegalArgumentException() {
        // Kotlin spec: step() only accepts positive values; negative steps are invalid
        // (downTo handles descending ranges internally using a negative internal step)
        var thrown = 0
        let range = kk_op_rangeTo(1, 10)
        _ = __kk_op_step(range, -1, &thrown)
        #expect(thrown != 0, "step=-1 must throw IllegalArgumentException (STDLIB-022)")
    }

    @Test func testStepNegativeLargeThrowsIllegalArgumentException() {
        var thrown = 0
        let range = kk_op_rangeTo(1, 100)
        _ = __kk_op_step(range, -5, &thrown)
        #expect(thrown != 0, "step=-5 must throw IllegalArgumentException (STDLIB-022)")
    }

    @Test func testStepZeroOnDownToRangeThrowsIllegalArgumentException() {
        // step=0 on a descending (downTo) range should also throw
        var thrown = 0
        let range = __kk_op_downTo(10, 1)
        _ = __kk_op_step(range, 0, &thrown)
        #expect(thrown != 0, "step=0 on downTo range must throw IllegalArgumentException (STDLIB-022)")
    }

    @Test func testStepPositiveDoesNotThrow() {
        // Positive step must not set outThrown
        var thrown = 0
        let range = kk_op_rangeTo(1, 10)
        _ = __kk_op_step(range, 2, &thrown)
        #expect(thrown == 0, "Positive step must not throw")
    }

    @Test func testStepDownToPositiveStepDoesNotThrow() {
        // downTo with positive step value must not throw
        var thrown = 0
        let range = __kk_op_downTo(10, 1)
        _ = __kk_op_step(range, 3, &thrown)
        #expect(thrown == 0, "downTo with positive step must not throw")
    }
}
