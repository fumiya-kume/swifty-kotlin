@testable import Runtime
import Testing

/// STDLIB-022: Comprehensive edge-case coverage for IntRange, LongRange, CharRange,
/// UIntRange, ULongRange, their progressions (step / downTo / until / rangeUntil),
/// and ClosedRange / OpenEndRange contracts.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeRangeProgressionEdgeCaseTests {
    // MARK: - Empty range (from > to)

    @Test func intEmptyRange_isEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: empty)!), "from > to must be empty")
    }

    @Test func intEmptyRange_containsFalse() {
        let empty = kk_op_rangeTo(10, 1)
        #expect(kk_range_contains(empty, 5) == 0, "empty range must not contain anything")
    }

    @Test func intEmptyRange_countIsZero() {
        let empty = kk_op_rangeTo(10, 1)
        #expect(kk_range_count(empty) == 0)
    }

    @Test func intEmptyRange_toListIsEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        let list = kk_range_toList(empty)
        #expect(kk_list_size(list) == 0)
    }

    // MARK: - Single-element range (from == to)

    @Test func intSingleElementRange_notEmpty() {
        let single = kk_op_rangeTo(7, 7)
        #expect(!(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: single)!)))
        #expect(kk_range_count(single) == 1)
    }

    @Test func intSingleElementRange_contains() {
        let single = kk_op_rangeTo(7, 7)
        #expect(kk_range_contains(single, 7) == 1)
        #expect(kk_range_contains(single, 6) == 0)
        #expect(kk_range_contains(single, 8) == 0)
    }

    @Test func intSingleElementRange_toList() {
        let single = kk_op_rangeTo(7, 7)
        let list = kk_range_toList(single)
        #expect(kk_list_size(list) == 1)
        #expect(kk_list_get(list, 0) == 7)
    }

    // MARK: - Boundary values (Int.MIN / Int.MAX)

    @Test func intBoundaryRange_minToMin() {
        let range = kk_op_rangeTo(Int.min, Int.min)
        #expect(kk_range_count(range) == 1)
        #expect(kk_range_contains(range, Int.min) == 1)
    }

    @Test func intBoundaryRange_maxToMax() {
        let range = kk_op_rangeTo(Int.max, Int.max)
        #expect(kk_range_count(range) == 1)
        #expect(kk_range_contains(range, Int.max) == 1)
    }

    @Test func intBoundaryRange_minToMaxContainsBothEnds() {
        let range = kk_op_rangeTo(Int.min, Int.max)
        #expect(kk_range_contains(range, Int.min) == 1)
        #expect(kk_range_contains(range, Int.max) == 1)
        #expect(kk_range_contains(range, 0) == 1)
    }

    @Test func intBoundaryRange_downToMaxMinDoesNotTrap() {
        // (Int.max downTo Int.min) — must not crash
        let range = __kk_op_downTo(Int.max, Int.min)
        _ = kk_range_first(range)
        _ = kk_range_last(range)
    }

    // MARK: - Step > 1 (IntProgression)

    @Test func intProgressionStepTwo() {
        let range = __kk_op_step(kk_op_rangeTo(1, 10), 2, nil)
        // 1,3,5,7,9 — last aligned to 9
        #expect(kk_range_first(range) == 1)
        #expect(kk_range_last(range) == 9)
        #expect(kk_range_count(range) == 5)
        let list = kk_range_toList(range)
        #expect(kk_list_size(list) == 5)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 4) == 9)
    }

    @Test func intProgressionStepExactlyFitsRange() {
        // (0..6) step 2 -> 0,2,4,6; last == 6 (exact fit)
        let range = __kk_op_step(kk_op_rangeTo(0, 6), 2, nil)
        #expect(kk_range_last(range) == 6)
        #expect(kk_range_count(range) == 4)
    }

    @Test func intProgressionStepLargerThanRange() {
        // (1..3) step 10 -> [1]; last == 1
        let range = __kk_op_step(kk_op_rangeTo(1, 3), 10, nil)
        #expect(kk_range_count(range) == 1)
        let list = kk_range_toList(range)
        #expect(kk_list_size(list) == 1)
        #expect(kk_list_get(list, 0) == 1)
    }

    @Test func intProgressionStep_lastAdjustedCorrectly() {
        // Kotlin rule: last = first + ((end - first) / step) * step
        // (2..11) step 3 -> 2,5,8,11; last == 11
        let range = __kk_op_step(kk_op_rangeTo(2, 11), 3, nil)
        #expect(kk_range_last(range) == 11)
        #expect(kk_range_count(range) == 4)
    }

    @Test func intProgressionStep_lastRoundedDown() {
        // (2..10) step 3 -> 2,5,8; last adjusted to 8, not 10
        let range = __kk_op_step(kk_op_rangeTo(2, 10), 3, nil)
        #expect(kk_range_last(range) == 8)
        #expect(kk_range_count(range) == 3)
    }

    // MARK: - Negative step via downTo

    @Test func downToBasic() {
        let range = __kk_op_downTo(5, 1)
        #expect(kk_range_first(range) == 5)
        #expect(kk_range_last(range) == 1)
        #expect(kk_range_count(range) == 5)
    }

    @Test func downTo_iterationOrder() {
        let range = __kk_op_downTo(5, 1)
        let list = kk_range_toList(range)
        #expect(kk_list_size(list) == 5)
        #expect(kk_list_get(list, 0) == 5)
        #expect(kk_list_get(list, 4) == 1)
    }

    @Test func downTo_containsInReverse() {
        let range = __kk_op_downTo(10, 1)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 5) == 1)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 0) == 0)
        #expect(kk_range_contains(range, 11) == 0)
    }

    @Test func downToStep_containsOnlyReachableElements() {
        // (10 downTo 1 step 3) -> 10,7,4,1
        let range = __kk_op_step(__kk_op_downTo(10, 1), 3, nil)
        #expect(kk_range_contains(range, 10) == 1)
        #expect(kk_range_contains(range, 7) == 1)
        #expect(kk_range_contains(range, 4) == 1)
        #expect(kk_range_contains(range, 1) == 1)
        #expect(kk_range_contains(range, 9) == 0, "9 is not reachable from 10 with step 3")
        #expect(kk_range_contains(range, 3) == 0)
    }

    @Test func downTo_isEmpty_whenFromLtTo() {
        // downTo with from < to is empty (negative step, first < last)
        let empty = __kk_op_downTo(1, 5)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: empty)!))
        #expect(kk_range_count(empty) == 0)
    }

    // MARK: - until / rangeUntil (open-end)

    @Test func untilExcludesEndpoint() {
        // (1 until 5) should contain 1..4, not 5
        let range = __kk_op_rangeUntil(1, 5)
        #expect(kk_range_contains(range, 4) == 1)
        #expect(kk_range_contains(range, 5) == 0, "until must exclude endpoint")
    }

    @Test func untilCount() {
        // (1 until 5) -> [1,2,3,4]; count = 4
        let range = __kk_op_rangeUntil(1, 5)
        #expect(kk_range_count(range) == 4)
    }

    @Test func untilSameEndpoints_isEmpty() {
        // (5 until 5) is empty
        let range = __kk_op_rangeUntil(5, 5)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: range)!))
        #expect(kk_range_count(range) == 0)
    }

    @Test func untilEndLessThanStart_isEmpty() {
        // (5 until 3) is empty
        let range = __kk_op_rangeUntil(5, 3)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: range)!))
    }

    @Test func untilToList() {
        let range = __kk_op_rangeUntil(1, 5)
        let list = kk_range_toList(range)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 3) == 4)
    }

    @Test func untilWithStep() {
        // (1 until 10 step 3) -> 1,4,7; last aligned to 7
        let range = __kk_op_step(__kk_op_rangeUntil(1, 10), 3, nil)
        #expect(kk_range_count(range) == 3)
        let list = kk_range_toList(range)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 2) == 7)
    }

    // MARK: - reversed()

    @Test func reversedOfAscendingRange() {
        let range = kk_op_rangeTo(1, 5)
        let rev = kk_range_reversed(range)
        #expect(kk_range_first(rev) == 5)
        #expect(kk_range_last(rev) == 1)
        #expect(kk_range_count(rev) == 5)
        let list = kk_range_toList(rev)
        #expect(kk_list_get(list, 0) == 5)
        #expect(kk_list_get(list, 4) == 1)
    }

    @Test func reversedOfDescendingRange() {
        let range = __kk_op_downTo(5, 1)
        let rev = kk_range_reversed(range)
        #expect(kk_range_first(rev) == 1)
        #expect(kk_range_last(rev) == 5)
        let list = kk_range_toList(rev)
        #expect(kk_list_get(list, 0) == 1)
        #expect(kk_list_get(list, 4) == 5)
    }

    @Test func reversedOfEmptyRange_staysEmpty() {
        let empty = kk_op_rangeTo(10, 1)
        let rev = kk_range_reversed(empty)
        #expect(kk_range_count(rev) == 0)
    }

    // MARK: - step 0 / invalid step handling

    @Test func stepZeroThrowsIllegalArgumentException() {
        // STDLIB-022: __kk_op_step with step=0 must throw IllegalArgumentException.
        // Previous behavior silently returned the range unchanged; this is now corrected.
        var thrown = 0
        let range = kk_op_rangeTo(1, 10)
        _ = __kk_op_step(range, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw IllegalArgumentException (STDLIB-022)")
    }

    // MARK: - IntProgression fromClosedRange

    @Test func intProgressionFromClosedRange_positiveStep() {
        // (1..10 step 3) -> first=1, last=10, count=4
        let p = __kk_int_progression_fromClosedRange(0, 1, 10, 3, nil)
        #expect(kk_range_first(p) == 1)
        #expect(kk_range_last(p) == 10)
        #expect(kk_range_count(p) == 4)
    }

    @Test func intProgressionFromClosedRange_negativeStep_downTo() {
        // (10..1 step -3) -> first=10, last=1, count=4
        let p = __kk_int_progression_fromClosedRange(0, 10, 1, -3, nil)
        #expect(kk_range_first(p) == 10)
        #expect(kk_range_last(p) == 1)
        #expect(kk_range_count(p) == 4)
    }

    @Test func intProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = __kk_int_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw IllegalArgumentException")
    }

    @Test func intProgressionFromClosedRange_stepIntMinThrows() {
        var thrown = 0
        _ = __kk_int_progression_fromClosedRange(0, 1, 10, Int.min, &thrown)
        #expect(thrown != 0, "step=Int.min must throw")
    }

    // MARK: - LongRange edge cases

    @Test func longRange_emptyWhenFromGtTo() {
        let empty = kk_long_rangeTo(100, 1)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: empty)!))
    }

    @Test func longRange_singleElement() {
        let r = kk_long_rangeTo(42, 42)
        #expect(!(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: r)!)))
        #expect(kk_range_contains(r, 42) == 1)
        #expect(kk_range_contains(r, 41) == 0)
    }

    @Test func longRange_containsBothEnds() {
        let r = kk_long_rangeTo(1, 10)
        #expect(kk_range_contains(r, 1) == 1)
        #expect(kk_range_contains(r, 10) == 1)
        #expect(kk_range_contains(r, 0) == 0)
        #expect(kk_range_contains(r, 11) == 0)
    }

    @Test func longRange_step2ContainsOnlyEvenFromFirst() {
        // (1..10 step 2) -> 1,3,5,7,9; step-reachable from 1
        let p = __kk_long_progression_fromClosedRange(0, 1, 10, 2, nil)
        #expect(kk_range_contains(p, 1) == 1)
        #expect(kk_range_contains(p, 3) == 1)
        #expect(kk_range_contains(p, 9) == 1)
        #expect(kk_range_contains(p, 2) == 0)
        #expect(kk_range_contains(p, 10) == 0, "10 is not reachable from 1 with step 2")
    }

    @Test func longRange_reversed() {
        let r = kk_long_rangeTo(1, 5)
        let rev = kk_range_reversed(r)
        #expect(kk_range_first(rev) == 5)
        #expect(kk_range_last(rev) == 1)
    }

    @Test func longProgressionFromClosedRange_negativeStep() {
        // Exercise the signed descending helper path.
        let progression = __kk_long_progression_fromClosedRange(0, 10, 1, -3, nil)
        #expect(kk_range_first(progression) == 10)
        #expect(kk_range_last(progression) == 1)
        #expect(kk_range_count(progression) == 4)
        let list = kk_long_range_toList(progression)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 10)
        #expect(kk_list_get(list, 3) == 1)
    }

    @Test func longProgression_stepZeroThrows() {
        var thrown = 0
        _ = __kk_long_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw for LongProgression")
    }

    // MARK: - CharProgression fromClosedRange

    @Test func charProgressionFromClosedRange_positiveStep() {
        let a = kk_box_char(Int(Unicode.Scalar("a").value))
        let g = kk_box_char(Int(Unicode.Scalar("g").value))
        let progression = __kk_char_progression_fromClosedRange(0, a, g, 2, nil)
        let list = kk_char_range_toList(progression)

        #expect(kk_list_size(list) == 4)
        #expect(kk_unbox_char(kk_range_first(progression)) == Int(Unicode.Scalar("a").value))
        #expect(kk_unbox_char(kk_range_last(progression)) == Int(Unicode.Scalar("g").value))
        #expect(kk_range_step(progression) == 2)
    }

    @Test func charProgressionFromClosedRange_negativeStep() {
        let g = kk_box_char(Int(Unicode.Scalar("g").value))
        let a = kk_box_char(Int(Unicode.Scalar("a").value))
        let progression = __kk_char_progression_fromClosedRange(0, g, a, -2, nil)
        let list = kk_char_range_toList(progression)

        #expect(kk_list_size(list) == 4)
        #expect(kk_unbox_char(kk_range_first(progression)) == Int(Unicode.Scalar("g").value))
        #expect(kk_unbox_char(kk_range_last(progression)) == Int(Unicode.Scalar("a").value))
        #expect(kk_range_step(progression) == -2)
    }

    @Test func charProgressionFromClosedRange_stepZeroThrows() {
        let a = kk_box_char(Int(Unicode.Scalar("a").value))
        let g = kk_box_char(Int(Unicode.Scalar("g").value))
        var thrown = 0
        _ = __kk_char_progression_fromClosedRange(0, a, g, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw for CharProgression")
    }

    @Test func charProgressionStepRealignsLast() {
        let a = kk_box_char(Int(Unicode.Scalar("a").value))
        let h = kk_box_char(Int(Unicode.Scalar("h").value))
        let progression = __kk_char_progression_fromClosedRange(0, a, h, 1, nil)
        let stepped = __kk_char_range_step(progression, 3, nil)

        #expect(kk_unbox_char(kk_range_last(stepped)) == Int(Unicode.Scalar("g").value))
        #expect(kk_list_size(kk_char_range_toList(stepped)) == 3)
        #expect(!(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: stepped)!)))
    }

    // MARK: - CharRange edge cases

    @Test func charRange_toListAscending() {
        // ('a'..'e') -> ['a','b','c','d','e']
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let range = kk_op_rangeTo(aBoxed, eBoxed)
        let list = kk_char_range_toList(range)
        #expect(kk_list_size(list) == 5)
    }

    @Test func charRange_emptyWhenFromGtTo() {
        // ('z'..'a') -> empty
        let zBoxed = kk_box_char(Int(Unicode.Scalar("z").value))
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let range = kk_op_rangeTo(zBoxed, aBoxed)
        let list = kk_char_range_toList(range)
        #expect(kk_list_size(list) == 0, "CharRange from > to must produce empty list")
    }

    @Test func charRange_singleElement() {
        let cBoxed = kk_box_char(Int(Unicode.Scalar("c").value))
        let range = kk_op_rangeTo(cBoxed, cBoxed)
        let list = kk_char_range_toList(range)
        #expect(kk_list_size(list) == 1)
    }

    @Test func charRange_take() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let zBoxed = kk_box_char(Int(Unicode.Scalar("z").value))
        let range = kk_op_rangeTo(aBoxed, zBoxed)
        let taken = kk_char_range_take(range, 3, nil)
        #expect(kk_list_size(taken) == 3)
    }

    @Test func charRange_drop() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let range = kk_op_rangeTo(aBoxed, eBoxed)
        // ('a'..'e') drop 2 -> ['c','d','e']
        let dropped = kk_char_range_drop(range, 2, nil)
        #expect(kk_list_size(dropped) == 3)
    }

    @Test func charRange_takeNegativeCountThrows() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let zBoxed = kk_box_char(Int(Unicode.Scalar("z").value))
        let range = kk_op_rangeTo(aBoxed, zBoxed)
        var thrown: Int = 0
        let taken = kk_char_range_take(range, -1, &thrown)
        #expect(kk_list_size(taken) == 0)
        #expect(thrown != 0)
    }

    @Test func charRange_dropNegativeCountThrows() {
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let range = kk_op_rangeTo(aBoxed, eBoxed)
        var thrown: Int = 0
        let dropped = kk_char_range_drop(range, -1, &thrown)
        #expect(kk_list_size(dropped) == 0)
        #expect(thrown != 0)
    }

    @Test func charRange_sorted_descendingInput() {
        // Sorted should still return ascending order
        let eBoxed = kk_box_char(Int(Unicode.Scalar("e").value))
        let aBoxed = kk_box_char(Int(Unicode.Scalar("a").value))
        // Descending range with step -1
        let range = __kk_op_downTo(eBoxed, aBoxed)
        let sorted = kk_char_range_sorted(range)
        #expect(kk_list_size(sorted) == 5)
        // first element should be 'a' (smallest)
        let firstChar = kk_unbox_char(kk_list_get(sorted, 0))
        let lastChar = kk_unbox_char(kk_list_get(sorted, 4))
        #expect(firstChar == Int(Unicode.Scalar("a").value))
        #expect(lastChar == Int(Unicode.Scalar("e").value))
    }

    // MARK: - UIntRange edge cases

    @Test func uIntRange_emptyWhenFromGtTo() {
        let empty = __kk_uint_rangeTo(10, 1) // unsigned: 10u > 1u, empty
        #expect(kk_uint_range_isEmpty(empty) == 1)
    }

    @Test func uIntRange_singleElement() {
        let r = __kk_uint_rangeTo(5, 5)
        #expect(kk_uint_range_isEmpty(r) == 0)
        #expect(kk_uint_range_contains(r, 5) == 1)
        #expect(kk_uint_range_contains(r, 4) == 0)
    }

    @Test func uIntRange_step2_lastAligned() {
        // (1u..10u step 2) -> 1,3,5,7,9; last aligned to 9
        let p = __kk_uint_step(__kk_uint_rangeTo(1, 10), 2)
        #expect(kk_range_first(p) == 1)
        #expect(kk_range_last(p) == 9)
        #expect(kk_range_count(p) == 5)
    }

    @Test func uIntRange_downTo() {
        // (5u downTo 1u) -> 5,4,3,2,1
        let range = __kk_uint_downTo(5, 1)
        #expect(kk_range_count(range) == 5)
        let list = kk_uint_range_toList(range)
        #expect(kk_list_get(list, 0) == 5)
        #expect(kk_list_get(list, 4) == 1)
    }

    @Test func uIntRange_downToStepAlignment() {
        // (10u downTo 1u) step 3 -> 10,7,4,1
        let range = __kk_uint_step(__kk_uint_downTo(10, 1), 3)
        #expect(kk_range_first(range) == 10)
        #expect(kk_range_last(range) == 1)
        #expect(kk_range_count(range) == 4)
        let list = kk_uint_range_toList(range)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == 10)
        #expect(kk_list_get(list, 3) == 1)
    }

    @Test func uIntRange_downTo_isEmpty_whenFromLtTo() {
        let empty = __kk_uint_downTo(1, 5)
        #expect(kk_uint_range_isEmpty(empty) == 1)
    }

    @Test func uIntRange_reversed() {
        let r = __kk_uint_rangeTo(1, 5)
        let rev = kk_uint_range_reversed(r)
        #expect(kk_range_first(rev) == 5)
        #expect(kk_range_last(rev) == 1)
        #expect(kk_range_count(rev) == 5)
    }

    @Test func uIntProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = __kk_uint_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw for UIntProgression")
    }

    @Test func uIntRange_largeUnsignedValues_beyondIntMax() {
        // Values near UInt.max stored as negative Int bit patterns
        let uintMax = Int(bitPattern: UInt.max)
        let uintMaxMinus1 = Int(bitPattern: UInt.max - 1)
        let r = __kk_uint_rangeTo(uintMaxMinus1, uintMax)
        #expect(kk_uint_range_contains(r, uintMaxMinus1) == 1)
        #expect(kk_uint_range_contains(r, uintMax) == 1)
        #expect(kk_range_count(r) == 2)
    }

    // MARK: - ULongRange edge cases

    @Test func uLongRange_emptyWhenFromGtTo() {
        let empty = kk_ulong_rangeTo(10, 1)
        #expect(RuntimeUnsignedRangeHOFKind.isEmpty(runtimeRangeBox(from: empty)!), "ULongRange from > to must be empty")
    }

    @Test func uLongRange_singleElement() {
        let r = kk_ulong_rangeTo(42, 42)
        #expect(kk_range_count(r) == 1)
    }

    @Test func uLongRange_step2_lastAligned() {
        // (1UL..10UL step 2) -> 1,3,5,7,9; last aligned to 9
        let p = __kk_ulong_step(kk_ulong_rangeTo(1, 10), 2)
        #expect(kk_range_first(p) == 1)
        #expect(kk_range_last(p) == 9)
        #expect(kk_range_count(p) == 5)
    }

    @Test func uLongRange_downTo_iterationOrder() {
        // (5UL downTo 1UL) -> 5,4,3,2,1
        let range = __kk_ulong_downTo(5, 1)
        let list = kk_ulong_range_toList(range)
        #expect(kk_list_size(list) == 5)
        #expect(kk_list_get(list, 0) == 5)
        #expect(kk_list_get(list, 4) == 1)
    }

    @Test func uLongRange_downTo_step3_lastAligned() {
        // (10UL downTo 1UL step 3) -> 10,7,4,1; last aligned to 1
        let range = __kk_ulong_step(__kk_ulong_downTo(10, 1), 3)
        #expect(kk_range_first(range) == 10)
        #expect(kk_range_last(range) == 1)
        #expect(kk_range_count(range) == 4)
    }

    @Test func uLongRange_reversed() {
        let r = kk_ulong_rangeTo(1, 5)
        let rev = kk_ulong_range_reversed(r)
        #expect(kk_range_first(rev) == 5)
        #expect(kk_range_last(rev) == 1)
        #expect(kk_range_count(rev) == 5)
    }

    @Test func uLongProgressionFromClosedRange_stepZeroThrows() {
        var thrown = 0
        _ = __kk_ulong_progression_fromClosedRange(0, 1, 10, 0, &thrown)
        #expect(thrown != 0, "step=0 must throw for ULongProgression")
    }

    @Test func uLongProgressionFromClosedRange_stepIntMinThrows() {
        var thrown = 0
        _ = __kk_ulong_progression_fromClosedRange(0, 1, 10, Int.min, &thrown)
        #expect(thrown != 0, "step=Int.min must throw for ULongProgression")
    }

    @Test func uLongRange_largeValues_beyondIntMax() {
        // Values beyond Int.max (represented as negative Int with UInt semantics)
        let bigStart = Int(bitPattern: UInt(4_294_967_295))   // UInt32.max
        let bigEnd = Int(bitPattern: UInt(4_294_967_298))
        let r = kk_ulong_rangeTo(bigStart, bigEnd)
        let list = kk_ulong_range_toList(r)
        #expect(kk_list_size(list) == 4)
        #expect(kk_list_get(list, 0) == bigStart)
        #expect(kk_list_get(list, 3) == bigEnd)
    }

    @Test func uLongRange_untilHighValues() {
        // Exercise the unsigned rangeUntil helper on values above Int.max.
        let start = Int(bitPattern: UInt.max - 3)
        let end = Int(bitPattern: UInt.max - 1)
        let range = __kk_op_ulong_rangeUntil(start, end)
        #expect(kk_range_count(range) == 2)
        let list = kk_ulong_range_toList(range)
        #expect(kk_list_size(list) == 2)
        #expect(kk_list_get(list, 0) == start)
        #expect(kk_list_get(list, 1) == Int(bitPattern: UInt.max - 2))
    }

    // MARK: - ClosedRange contract (IntRange)

    @Test func closedRangeContract_firstIncluded() {
        let r = kk_op_rangeTo(3, 7)
        #expect(kk_range_contains(r, kk_range_first(r)) == 1, "first must be contained in ClosedRange")
    }

    @Test func closedRangeContract_lastIncluded() {
        let r = kk_op_rangeTo(3, 7)
        #expect(kk_range_contains(r, kk_range_last(r)) == 1, "last must be contained in ClosedRange")
    }

    @Test func closedRangeContract_adjacentToFirstExcluded() {
        let r = kk_op_rangeTo(3, 7)
        #expect(kk_range_contains(r, kk_range_first(r) - 1) == 0, "first-1 must not be contained")
    }

    @Test func closedRangeContract_adjacentToLastExcluded() {
        let r = kk_op_rangeTo(3, 7)
        #expect(kk_range_contains(r, kk_range_last(r) + 1) == 0, "last+1 must not be contained")
    }

    // MARK: - OpenEndRange contract (rangeUntil / ..<)

    @Test func openEndRangeContract_endExcluded() {
        let r = __kk_op_rangeUntil(3, 7)
        #expect(kk_range_contains(r, 7) == 0, "end must NOT be contained in OpenEndRange (..<)")
    }

    @Test func openEndRangeContract_startIncluded() {
        let r = __kk_op_rangeUntil(3, 7)
        #expect(kk_range_contains(r, 3) == 1, "start must be contained in OpenEndRange")
    }

    @Test func openEndRangeContract_endMinus1Included() {
        let r = __kk_op_rangeUntil(3, 7)
        #expect(kk_range_contains(r, 6) == 1, "end-1 must be contained in OpenEndRange")
    }

    @Test func openEndRangeContract_endExclusiveMatchesUpperBound() {
        let closed = kk_op_rangeTo(3, 7)
        #expect(kk_range_endExclusive(closed) == 8, "ClosedRange endExclusive should be last + 1")

        let open = __kk_op_rangeUntil(3, 7)
        #expect(kk_range_endExclusive(open) == 7, "OpenEndRange endExclusive should match the exclusive upper bound")
    }

    // MARK: - Iterator protocol correctness

    @Test func iterator_withoutThrownChannel_preservesRangeIteration() {
        let range = kk_op_rangeTo(1, 2)
        let iterator = kk_range_iterator(range)

        #expect(kk_range_hasNext(iterator) == 1)
        #expect(kk_range_next(iterator) == 1)
        #expect(kk_range_hasNext(iterator) == 1)
        #expect(kk_range_next(iterator) == 2)
        #expect(kk_range_hasNext(iterator) == 0)
    }

    @Test func iterator_stepsCorrectly_ascending() {
        let range = kk_op_rangeTo(1, 4)
        let iter = kk_range_iterator(range, nil)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        #expect(values == [1, 2, 3, 4])
    }

    @Test func iterator_stepsCorrectly_descending() {
        let range = __kk_op_downTo(4, 1)
        let iter = kk_range_iterator(range, nil)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        #expect(values == [4, 3, 2, 1])
    }

    @Test func iterator_emptyRange_hasNextFalseImmediately() {
        let empty = kk_op_rangeTo(5, 1)
        let iter = kk_range_iterator(empty, nil)
        #expect(kk_range_hasNext(iter) == 0, "hasNext on empty range must be false immediately")
    }

    @Test func iterator_withStep_yieldsAlignedValues() {
        // (1..10 step 3) -> 1,4,7,10
        let range = __kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        let iter = kk_range_iterator(range, nil)
        var values: [Int] = []
        while kk_range_hasNext(iter) != 0 {
            values.append(kk_range_next(iter))
        }
        #expect(values == [1, 4, 7, 10])
    }

    // BUG-198: the compiler-lowered fast path must match RangeIterators.kt,
    // including stopping after an arithmetic overflow instead of wrapping into
    // another valid-looking element.
    @Test func forInFastPath_stepsAndStopsAtOverflow() {
        let range = kk_op_rangeTo(Int.max - 1, Int.max)
        let iter = kk_range_for_in_iterator(range)
        var values: [Int] = []
        while kk_range_for_in_hasNext(iter) != 0 {
            values.append(kk_range_for_in_next(iter))
        }
        #expect(values == [Int.max - 1, Int.max])
        #expect(kk_range_for_in_hasNext(iter) == 0)
    }

    @Test func forInFastPath_descendingStopsAtUnderflow() {
        let range = __kk_op_downTo(Int.min + 1, Int.min)
        let iter = kk_range_for_in_iterator(range)
        var values: [Int] = []
        while kk_range_for_in_hasNext(iter) != 0 {
            values.append(kk_range_for_in_next(iter))
        }
        #expect(values == [Int.min + 1, Int.min])
        #expect(kk_range_for_in_hasNext(iter) == 0)
    }

    @Test func forInFastPath_emptyAndSteppedRanges() {
        let empty = kk_range_for_in_iterator(kk_op_rangeTo(5, 1))
        #expect(kk_range_for_in_hasNext(empty) == 0)

        let stepped = __kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        let iter = kk_range_for_in_iterator(stepped)
        var values: [Int] = []
        while kk_range_for_in_hasNext(iter) != 0 {
            values.append(kk_range_for_in_next(iter))
        }
        #expect(values == [1, 4, 7, 10])
    }

    // MARK: - sum / isEmpty on progressions

    @Test func progressionSum_empty() {
        let empty = kk_op_rangeTo(5, 1)
        #expect(kk_range_sum(empty) == 0)
    }

    @Test func progressionSum_singleElement() {
        let single = kk_op_rangeTo(7, 7)
        #expect(kk_range_sum(single) == 7)
    }

    @Test func progressionSum_ascending() {
        // 1+2+3+4+5 = 15
        let r = kk_op_rangeTo(1, 5)
        #expect(kk_range_sum(r) == 15)
    }

    @Test func progressionSum_descendingWithStep() {
        // (10 downTo 1 step 3) -> 10,7,4,1 -> sum=22
        let r = __kk_op_step(__kk_op_downTo(10, 1), 3, nil)
        #expect(kk_range_sum(r) == 22)
    }
}
