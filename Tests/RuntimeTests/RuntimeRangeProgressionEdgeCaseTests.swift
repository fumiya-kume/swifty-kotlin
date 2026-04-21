@testable import Runtime
import XCTest

/// STDLIB-022: Comprehensive edge-case coverage for IntRange, LongRange, CharRange,
/// UIntRange, ULongRange, their progressions (step / downTo / until / rangeUntil),
/// and ClosedRange / OpenEndRange contracts.
final class RuntimeRangeProgressionEdgeCaseTests: IsolatedRuntimeXCTestCase {

    // MARK: - Empty range (from > to)

    func testIntEmptyRange_isEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        XCTAssertEqual(kk_range_isEmpty(empty), 1, "from > to must be empty")
    }

    func testIntEmptyRange_containsFalse() {
        let empty = kk_op_rangeTo(10, 1)
        XCTAssertEqual(kk_range_contains(empty, 5), 0, "empty range must not contain anything")
    }

    func testIntEmptyRange_countIsZero() {
        let empty = kk_op_rangeTo(10, 1)
        XCTAssertEqual(kk_range_count(empty), 0)
    }

    func testIntEmptyRange_toListIsEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        let list = kk_range_toList(empty)
        XCTAssertEqual(kk_list_size(list), 0)
    }

    // MARK: - Single-element range (from == to)

    func testIntSingleElementRange_notEmpty() {
        let single = kk_op_rangeTo(7, 7)
        XCTAssertEqual(kk_range_isEmpty(single), 0)
        XCTAssertEqual(kk_range_count(single), 1)
    }

    func testIntSingleElementRange_contains() {
        let single = kk_op_rangeTo(7, 7)
        XCTAssertEqual(kk_range_contains(single, 7), 1)
        XCTAssertEqual(kk_range_contains(single, 6), 0)
        XCTAssertEqual(kk_range_contains(single, 8), 0)
    }

    func testIntSingleElementRange_toList() {
        let single = kk_op_rangeTo(7, 7)
        let list = kk_range_toList(single)
        XCTAssertEqual(kk_list_size(list), 1)
        XCTAssertEqual(kk_list_get(list, 0), 7)
    }

    // MARK: - Boundary values (Int.MIN / Int.MAX)

    func testIntBoundaryRange_minToMin() {
        let range = kk_op_rangeTo(Int.min, Int.min)
        XCTAssertEqual(kk_range_count(range), 1)
        XCTAssertEqual(kk_range_contains(range, Int.min), 1)
    }

    func testIntBoundaryRange_maxToMax() {
        let range = kk_op_rangeTo(Int.max, Int.max)
        XCTAssertEqual(kk_range_count(range), 1)
        XCTAssertEqual(kk_range_contains(range, Int.max), 1)
    }

    func testIntBoundaryRange_minToMaxContainsBothEnds() {
        let range = kk_op_rangeTo(Int.min, Int.max)
        XCTAssertEqual(kk_range_contains(range, Int.min), 1)
        XCTAssertEqual(kk_range_contains(range, Int.max), 1)
        XCTAssertEqual(kk_range_contains(range, 0), 1)
    }

    func testIntBoundaryRange_downToMaxMinDoesNotTrap() {
        // (Int.max downTo Int.min) — must not crash
        let range = kk_op_downTo(Int.max, Int.min)
        _ = kk_range_first(range)
        _ = kk_range_last(range)
    }

    // MARK: - Step > 1 (IntProgression)

    func testIntProgressionStepTwo() {
        let range = kk_op_step(kk_op_rangeTo(1, 10), 2, nil)
        // 1,3,5,7,9 — last aligned to 9
        XCTAssertEqual(kk_range_first(range), 1)
        XCTAssertEqual(kk_range_last(range), 9)
        XCTAssertEqual(kk_range_count(range), 5)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 5)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 4), 9)
    }

    func testIntProgressionStepExactlyFitsRange() {
        // (0..6) step 2 -> 0,2,4,6; last == 6 (exact fit)
        let range = kk_op_step(kk_op_rangeTo(0, 6), 2, nil)
        XCTAssertEqual(kk_range_last(range), 6)
        XCTAssertEqual(kk_range_count(range), 4)
    }

    func testIntProgressionStepLargerThanRange() {
        // (1..3) step 10 -> [1]; last == 1
        let range = kk_op_step(kk_op_rangeTo(1, 3), 10, nil)
        XCTAssertEqual(kk_range_count(range), 1)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 1)
        XCTAssertEqual(kk_list_get(list, 0), 1)
    }

    func testIntProgressionStep_lastAdjustedCorrectly() {
        // Kotlin rule: last = first + ((end - first) / step) * step
        // (2..11) step 3 -> 2,5,8,11; last == 11
        let range = kk_op_step(kk_op_rangeTo(2, 11), 3, nil)
        XCTAssertEqual(kk_range_last(range), 11)
        XCTAssertEqual(kk_range_count(range), 4)
    }

    func testIntProgressionStep_lastRoundedDown() {
        // (2..10) step 3 -> 2,5,8; last adjusted to 8, not 10
        let range = kk_op_step(kk_op_rangeTo(2, 10), 3, nil)
        XCTAssertEqual(kk_range_last(range), 8)
        XCTAssertEqual(kk_range_count(range), 3)
    }

    // MARK: - Negative step via downTo

    func testDownToBasic() {
        let range = kk_op_downTo(5, 1)
        XCTAssertEqual(kk_range_first(range), 5)
        XCTAssertEqual(kk_range_last(range), 1)
        XCTAssertEqual(kk_range_count(range), 5)
    }

    func testDownTo_iterationOrder() {
        let range = kk_op_downTo(5, 1)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 5)
        XCTAssertEqual(kk_list_get(list, 0), 5)
        XCTAssertEqual(kk_list_get(list, 4), 1)
    }

    func testDownTo_containsInReverse() {
        let range = kk_op_downTo(10, 1)
        XCTAssertEqual(kk_range_contains(range, 10), 1)
        XCTAssertEqual(kk_range_contains(range, 5), 1)
        XCTAssertEqual(kk_range_contains(range, 1), 1)
        XCTAssertEqual(kk_range_contains(range, 0), 0)
        XCTAssertEqual(kk_range_contains(range, 11), 0)
    }

    func testDownToStep_containsOnlyReachableElements() {
        // (10 downTo 1 step 3) -> 10,7,4,1
        let range = kk_op_step(kk_op_downTo(10, 1), 3, nil)
        XCTAssertEqual(kk_range_contains(range, 10), 1)
        XCTAssertEqual(kk_range_contains(range, 7), 1)
        XCTAssertEqual(kk_range_contains(range, 4), 1)
        XCTAssertEqual(kk_range_contains(range, 1), 1)
        XCTAssertEqual(kk_range_contains(range, 9), 0, "9 is not reachable from 10 with step 3")
        XCTAssertEqual(kk_range_contains(range, 3), 0)
    }

    func testDownTo_isEmpty_whenFromLtTo() {
        // downTo with from < to is empty (negative step, first < last)
        let empty = kk_op_downTo(1, 5)
        XCTAssertEqual(kk_range_isEmpty(empty), 1)
        XCTAssertEqual(kk_range_count(empty), 0)
    }

    // MARK: - until / rangeUntil (open-end)

    func testUntilExcludesEndpoint() {
        // (1 until 5) should contain 1..4, not 5
        let range = kk_op_rangeUntil(1, 5)
        XCTAssertEqual(kk_range_contains(range, 4), 1)
        XCTAssertEqual(kk_range_contains(range, 5), 0, "until must exclude endpoint")
    }

    func testUntilCount() {
        // (1 until 5) -> [1,2,3,4]; count = 4
        let range = kk_op_rangeUntil(1, 5)
        XCTAssertEqual(kk_range_count(range), 4)
    }

    func testUntilSameEndpoints_isEmpty() {
        // (5 until 5) is empty
        let range = kk_op_rangeUntil(5, 5)
        XCTAssertEqual(kk_range_isEmpty(range), 1)
        XCTAssertEqual(kk_range_count(range), 0)
    }

    func testUntilEndLessThanStart_isEmpty() {
        // (5 until 3) is empty
        let range = kk_op_rangeUntil(5, 3)
        XCTAssertEqual(kk_range_isEmpty(range), 1)
    }

    func testUntilToList() {
        let range = kk_op_rangeUntil(1, 5)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 4)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 3), 4)
    }

    func testUntilWithStep() {
        // (1 until 10 step 3) -> 1,4,7; last aligned to 7
        let range = kk_op_step(kk_op_rangeUntil(1, 10), 3, nil)
        XCTAssertEqual(kk_range_count(range), 3)
        let list = kk_range_toList(range)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 2), 7)
    }

    // MARK: - reversed()

    func testReversedOfAscendingRange() {
        let range = kk_op_rangeTo(1, 5)
        let rev = kk_range_reversed(range)
        XCTAssertEqual(kk_range_first(rev), 5)
        XCTAssertEqual(kk_range_last(rev), 1)
        XCTAssertEqual(kk_range_count(rev), 5)
        let list = kk_range_toList(rev)
        XCTAssertEqual(kk_list_get(list, 0), 5)
        XCTAssertEqual(kk_list_get(list, 4), 1)
    }

    func testReversedOfDescendingRange() {
        let range = kk_op_downTo(5, 1)
        let rev = kk_range_reversed(range)
        XCTAssertEqual(kk_range_first(rev), 1)
        XCTAssertEqual(kk_range_last(rev), 5)
        let list = kk_range_toList(rev)
        XCTAssertEqual(kk_list_get(list, 0), 1)
        XCTAssertEqual(kk_list_get(list, 4), 5)
    }

    func testReversedOfEmptyRange_staysEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        let rev = kk_range_reversed(empty)
        XCTAssertEqual(kk_range_count(rev), 0)
    }

    // MARK: - step 0 / invalid step handling

    func testStepZeroThrowsIllegalArgumentException() {
        // STDLIB-022: kk_op_step with step=0 must throw IllegalArgumentException.
        // Previous behavior silently returned the range unchanged; this is now corrected.
        var thrown = 0
        let range = kk_op_rangeTo(1, 10)
        _ = kk_op_step(range, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=0 must throw IllegalArgumentException (STDLIB-022)")
    }

    // MARK: - IntProgression fromClosedRange

    func testIntProgressionFromClosedRange_positiveStep() {
        // (1..10 step 3) -> first=1, last=10, count=4
        let p = kk_int_progression_fromClosedRange(0, 1, 10, 3, nil)
        XCTAssertEqual(kk_range_first(p), 1)
        XCTAssertEqual(kk_range_last(p), 10)
        XCTAssertEqual(kk_range_count(p), 4)
    }

    func testIntProgressionFromClosedRange_negativeStep_downTo() {
        // (10..1 step -3) -> first=10, last=1, count=4
        let p = kk_int_progression_fromClosedRange(0, 10, 1, -3, nil)
        XCTAssertEqual(kk_range_first(p), 10)
        XCTAssertEqual(kk_range_last(p), 1)
        XCTAssertEqual(kk_range_count(p), 4)
    }

    func testIntProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = kk_int_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=0 must throw IllegalArgumentException")
    }

    func testIntProgressionFromClosedRange_stepIntMinThrows() {
        var thrown = 0
        _ = kk_int_progression_fromClosedRange(0, 1, 10, Int.min, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=Int.min must throw")
    }

    // MARK: - LongRange edge cases

    func testLongRange_emptyWhenFromGtTo() {
        let empty = kk_long_rangeTo(100, 1)
        XCTAssertEqual(kk_long_range_isEmpty(empty), 1)
    }

    func testLongRange_singleElement() {
        let r = kk_long_rangeTo(42, 42)
        XCTAssertEqual(kk_long_range_isEmpty(r), 0)
        XCTAssertEqual(kk_long_range_contains(r, 42), 1)
        XCTAssertEqual(kk_long_range_contains(r, 41), 0)
    }

    func testLongRange_containsBothEnds() {
        let r = kk_long_rangeTo(1, 10)
        XCTAssertEqual(kk_long_range_contains(r, 1), 1)
        XCTAssertEqual(kk_long_range_contains(r, 10), 1)
        XCTAssertEqual(kk_long_range_contains(r, 0), 0)
        XCTAssertEqual(kk_long_range_contains(r, 11), 0)
    }

    func testLongRange_step2ContainsOnlyEvenFromFirst() {
        // (1..10 step 2) -> 1,3,5,7,9; step-reachable from 1
        let p = kk_long_progression_fromClosedRange(0, 1, 10, 2, nil)
        XCTAssertEqual(kk_long_range_contains(p, 1), 1)
        XCTAssertEqual(kk_long_range_contains(p, 3), 1)
        XCTAssertEqual(kk_long_range_contains(p, 9), 1)
        XCTAssertEqual(kk_long_range_contains(p, 2), 0)
        XCTAssertEqual(kk_long_range_contains(p, 10), 0, "10 is not reachable from 1 with step 2")
    }

    func testLongRange_reversed() {
        let r = kk_long_rangeTo(1, 5)
        let rev = kk_long_range_reversed(r)
        XCTAssertEqual(kk_long_range_first(rev), 5)
        XCTAssertEqual(kk_long_range_last(rev), 1)
    }

    func testLongProgression_stepZeroThrows() {
        var thrown = 0
        _ = kk_long_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=0 must throw for LongProgression")
    }

    // MARK: - CharRange edge cases

    func testCharRange_toListAscending() {
        // ('a'..'e') -> ['a','b','c','d','e']
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let range = kk_op_rangeTo(aBoxed, eBoxed)
        let list = kk_char_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 5)
    }

    func testCharRange_emptyWhenFromGtTo() {
        // ('z'..'a') -> empty
        let zBoxed = kk_box_char(Int(Unicode.Scalar("z").value))
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let range = kk_op_rangeTo(zBoxed, aBoxed)
        let list = kk_char_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 0, "CharRange from > to must produce empty list")
    }

    func testCharRange_singleElement() {
        let cBoxed = kk_box_char(Int(Unicode.Scalar("c").value))
        let range = kk_op_rangeTo(cBoxed, cBoxed)
        let list = kk_char_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 1)
    }

    func testCharRange_take() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let zBoxed = kk_box_char(Int(Unicode.Scalar("z").value))
        let range = kk_op_rangeTo(aBoxed, zBoxed)
        let taken = kk_char_range_take(range, 3)
        XCTAssertEqual(kk_list_size(taken), 3)
    }

    func testCharRange_drop() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let range = kk_op_rangeTo(aBoxed, eBoxed)
        // ('a'..'e') drop 2 -> ['c','d','e']
        let dropped = kk_char_range_drop(range, 2)
        XCTAssertEqual(kk_list_size(dropped), 3)
    }

    func testCharRange_sorted_descendingInput() {
        // Sorted should still return ascending order
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        // Descending range with step -1
        let range = kk_op_downTo(eBoxed, aBoxed)
        let sorted = kk_char_range_sorted(range)
        XCTAssertEqual(kk_list_size(sorted), 5)
        // first element should be 'a' (smallest)
        let firstChar = kk_unbox_char(kk_list_get(sorted, 0))
        let lastChar = kk_unbox_char(kk_list_get(sorted, 4))
        XCTAssertEqual(firstChar, Int(Unicode.Scalar("a").value))
        XCTAssertEqual(lastChar, Int(Unicode.Scalar("e").value))
    }

    // MARK: - UIntRange edge cases

    func testUIntRange_emptyWhenFromGtTo() {
        let empty = kk_uint_rangeTo(10, 1) // unsigned: 10u > 1u, empty
        XCTAssertEqual(kk_uint_range_isEmpty(empty), 1)
    }

    func testUIntRange_singleElement() {
        let r = kk_uint_rangeTo(5, 5)
        XCTAssertEqual(kk_uint_range_isEmpty(r), 0)
        XCTAssertEqual(kk_uint_range_contains(r, 5), 1)
        XCTAssertEqual(kk_uint_range_contains(r, 4), 0)
    }

    func testUIntRange_step2_lastAligned() {
        // (1u..10u step 2) -> 1,3,5,7,9; last aligned to 9
        let p = kk_uint_step(kk_uint_rangeTo(1, 10), 2)
        XCTAssertEqual(kk_range_first(p), 1)
        XCTAssertEqual(kk_range_last(p), 9)
        XCTAssertEqual(kk_range_count(p), 5)
    }

    func testUIntRange_downTo() {
        // (5u downTo 1u) -> 5,4,3,2,1
        let range = kk_uint_downTo(5, 1)
        XCTAssertEqual(kk_range_count(range), 5)
        let list = kk_uint_range_toList(range)
        XCTAssertEqual(kk_list_get(list, 0), 5)
        XCTAssertEqual(kk_list_get(list, 4), 1)
    }

    func testUIntRange_downTo_isEmpty_whenFromLtTo() {
        let empty = kk_uint_downTo(1, 5)
        XCTAssertEqual(kk_uint_range_isEmpty(empty), 1)
    }

    func testUIntRange_reversed() {
        let r = kk_uint_rangeTo(1, 5)
        let rev = kk_uint_range_reversed(r)
        XCTAssertEqual(kk_range_first(rev), 5)
        XCTAssertEqual(kk_range_last(rev), 1)
        XCTAssertEqual(kk_range_count(rev), 5)
    }

    func testUIntProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = kk_uint_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=0 must throw for UIntProgression")
    }

    func testUIntRange_largeUnsignedValues_beyondIntMax() {
        // Values near UInt.max stored as negative Int bit patterns
        let uintMax = Int(bitPattern: UInt.max)
        let uintMaxMinus1 = Int(bitPattern: UInt.max - 1)
        let r = kk_uint_rangeTo(uintMaxMinus1, uintMax)
        XCTAssertEqual(kk_uint_range_contains(r, uintMaxMinus1), 1)
        XCTAssertEqual(kk_uint_range_contains(r, uintMax), 1)
        XCTAssertEqual(kk_range_count(r), 2)
    }

    // MARK: - ULongRange edge cases

    func testULongRange_emptyWhenFromGtTo() {
        let empty = kk_ulong_rangeTo(10, 1)
        XCTAssertEqual(kk_range_isEmpty(empty), 1, "ULongRange from > to must be empty")
    }

    func testULongRange_singleElement() {
        let r = kk_ulong_rangeTo(42, 42)
        XCTAssertEqual(kk_range_count(r), 1)
    }

    func testULongRange_step2_lastAligned() {
        // (1UL..10UL step 2) -> 1,3,5,7,9; last aligned to 9
        let p = kk_ulong_step(kk_ulong_rangeTo(1, 10), 2)
        XCTAssertEqual(kk_range_first(p), 1)
        XCTAssertEqual(kk_range_last(p), 9)
        XCTAssertEqual(kk_range_count(p), 5)
    }

    func testULongRange_downTo_iterationOrder() {
        // (5UL downTo 1UL) -> 5,4,3,2,1
        let range = kk_ulong_downTo(5, 1)
        let list = kk_ulong_range_toList(range)
        XCTAssertEqual(kk_list_size(list), 5)
        XCTAssertEqual(kk_list_get(list, 0), 5)
        XCTAssertEqual(kk_list_get(list, 4), 1)
    }

    func testULongRange_downTo_step3_lastAligned() {
        // (10UL downTo 1UL step 3) -> 10,7,4,1; last aligned to 1
        let range = kk_ulong_step(kk_ulong_downTo(10, 1), 3)
        XCTAssertEqual(kk_range_first(range), 10)
        XCTAssertEqual(kk_range_last(range), 1)
        XCTAssertEqual(kk_range_count(range), 4)
    }

    func testULongRange_reversed() {
        let r = kk_ulong_rangeTo(1, 5)
        let rev = kk_ulong_range_reversed(r)
        XCTAssertEqual(kk_range_first(rev), 5)
        XCTAssertEqual(kk_range_last(rev), 1)
        XCTAssertEqual(kk_range_count(rev), 5)
    }

    func testULongProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = kk_ulong_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=0 must throw for ULongProgression")
    }

    func testULongProgressionFromClosedRange_stepIntMinThrows() {
        var thrown = 0
        _ = kk_ulong_progression_fromClosedRange(0, 1, 10, Int.min, &thrown)
        XCTAssertNotEqual(thrown, 0, "step=Int.min must throw for ULongProgression")
    }

    func testULongRange_largeValues_beyondIntMax() {
        // Values beyond Int.max (represented as negative Int with UInt semantics)
        let bigStart = Int(bitPattern: UInt(4_294_967_295))   // UInt32.max
        let bigEnd = Int(bitPattern: UInt(4_294_967_298))
        let r = kk_ulong_rangeTo(bigStart, bigEnd)
        let list = kk_ulong_range_toList(r)
        XCTAssertEqual(kk_list_size(list), 4)
        XCTAssertEqual(kk_list_get(list, 0), bigStart)
        XCTAssertEqual(kk_list_get(list, 3), bigEnd)
    }

    // MARK: - ClosedRange contract (IntRange)

    func testClosedRangeContract_firstIncluded() {
        let r = kk_op_rangeTo(3, 7)
        XCTAssertEqual(kk_range_contains(r, kk_range_first(r)), 1, "first must be contained in ClosedRange")
    }

    func testClosedRangeContract_lastIncluded() {
        let r = kk_op_rangeTo(3, 7)
        XCTAssertEqual(kk_range_contains(r, kk_range_last(r)), 1, "last must be contained in ClosedRange")
    }

    func testClosedRangeContract_adjacentToFirstExcluded() {
        let r = kk_op_rangeTo(3, 7)
        XCTAssertEqual(kk_range_contains(r, kk_range_first(r) - 1), 0, "first-1 must not be contained")
    }

    func testClosedRangeContract_adjacentToLastExcluded() {
        let r = kk_op_rangeTo(3, 7)
        XCTAssertEqual(kk_range_contains(r, kk_range_last(r) + 1), 0, "last+1 must not be contained")
    }

    // MARK: - OpenEndRange contract (rangeUntil / ..<)

    func testOpenEndRangeContract_endExcluded() {
        let r = kk_op_rangeUntil(3, 7)
        XCTAssertEqual(kk_range_contains(r, 7), 0, "end must NOT be contained in OpenEndRange (..<)")
    }

    func testOpenEndRangeContract_startIncluded() {
        let r = kk_op_rangeUntil(3, 7)
        XCTAssertEqual(kk_range_contains(r, 3), 1, "start must be contained in OpenEndRange")
    }

    func testOpenEndRangeContract_endMinus1Included() {
        let r = kk_op_rangeUntil(3, 7)
        XCTAssertEqual(kk_range_contains(r, 6), 1, "end-1 must be contained in OpenEndRange")
    }

    func testOpenEndRangeContract_endExclusiveMatchesUpperBound() {
        let closed = kk_op_rangeTo(3, 7)
        XCTAssertEqual(kk_range_endExclusive(closed), 8, "ClosedRange endExclusive should be last + 1")

        let open = kk_op_rangeUntil(3, 7)
        XCTAssertEqual(kk_range_endExclusive(open), 7, "OpenEndRange endExclusive should match the exclusive upper bound")
    }

    // MARK: - Iterator protocol correctness

    func testIterator_stepsCorrectly_ascending() {
        let range = kk_op_rangeTo(1, 4)
        let iter = kk_range_iterator(range)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        XCTAssertEqual(values, [1, 2, 3, 4])
    }

    func testIterator_stepsCorrectly_descending() {
        let range = kk_op_downTo(4, 1)
        let iter = kk_range_iterator(range)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        XCTAssertEqual(values, [4, 3, 2, 1])
    }

    func testIterator_emptyRange_hasNextFalseImmediately() {
        let empty = kk_op_rangeTo(5, 1)
        let iter = kk_range_iterator(empty)
        XCTAssertEqual(kk_range_hasNext(iter), 0, "hasNext on empty range must be false immediately")
    }

    func testIterator_withStep_yieldsAlignedValues() {
        // (1..10 step 3) -> 1,4,7,10
        let range = kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        let iter = kk_range_iterator(range)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        XCTAssertEqual(values, [1, 4, 7, 10])
    }

    // MARK: - sum / isEmpty on progressions

    func testProgressionSum_empty() {
        let empty = kk_op_rangeTo(5, 1)
        XCTAssertEqual(kk_range_sum(empty), 0)
    }

    func testProgressionSum_singleElement() {
        let single = kk_op_rangeTo(7, 7)
        XCTAssertEqual(kk_range_sum(single), 7)
    }

    func testProgressionSum_ascending() {
        // 1+2+3+4+5 = 15
        let r = kk_op_rangeTo(1, 5)
        XCTAssertEqual(kk_range_sum(r), 15)
    }

    func testProgressionSum_descendingWithStep() {
        // (10 downTo 1 step 3) -> 10,7,4,1 -> sum=22
        let r = kk_op_step(kk_op_downTo(10, 1), 3, nil)
        XCTAssertEqual(kk_range_sum(r), 22)
    }
}
