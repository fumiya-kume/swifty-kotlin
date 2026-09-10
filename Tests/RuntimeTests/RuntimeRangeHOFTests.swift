#if canImport(Testing)
import Testing
@testable import Runtime

private let rangeMapDouble: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 2
}

private let rangeFilterNotEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

private let rangeFoldIndexedSum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index + value
}

private let rangeMapIndexedSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index + value
}

private let rangeForEachAccumulate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closurePtr, value, _ in
    UnsafeMutablePointer<Int>(bitPattern: closurePtr)!.pointee += value
    return 0
}

// Returns the runtime null sentinel for even values so mapNotNull filters them out
private let rangeMapNotNullOddOnly: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? runtimeNullSentinelInt : value
}

private let rangeFilterIndexedEvenIndex: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, _, _ in
    index % 2 == 0 ? 1 : 0
}

private let rangeReduceIndexedAccPlusIndexPlusValue: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index + value
}

private let rangePredicateEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

@Suite
struct RuntimeRangeHOFTests {
    @Test
    func testRangeMapProducesMappedList() {
        let range = kk_op_rangeTo(1, 4)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [2, 4, 6, 8])
    }

    @Test
    func testRangeFilterNotDropsMatchingElements() {
        let range = kk_op_rangeTo(1, 5)
        let filtered = kk_range_filterNot(range, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        #expect(listElements(filtered) == [1, 3, 5])
    }

    @Test
    func testRangeFoldIndexedAccumulatesWithIndex() {
        let range = kk_op_rangeTo(1, 3)
        let result = kk_range_foldIndexed(range, 10, unsafeBitCast(rangeFoldIndexedSum, to: Int.self), 0, nil)
        #expect(result == 19)
    }

    @Test
    func testRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_op_rangeTo(1, 4)
        #expect(kk_range_firstOrNull(range) == 1)
        #expect(kk_range_lastOrNull(range) == 4)
    }

    @Test
    func testULongRangeNoArgOrIndexedHOFs() {
        let range = kk_ulong_rangeTo(1, 4)
        #expect(kk_ulong_range_firstOrNull(range) == 1)
        #expect(kk_ulong_range_lastOrNull(range) == 4)

        let mapped = kk_ulong_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [1, 3, 5, 7])
    }

    @Test
    func testUIntRangeTakeAndDropNegativeCountThrows() {
        let range = __kk_uint_rangeTo(1, 5)
        var takeThrown: Int = 0
        let taken = __kk_uint_range_take(range, -1, &takeThrown)
        #expect(kk_list_size(taken) == 0)
        #expect(takeThrown != 0)

        var dropThrown: Int = 0
        let dropped = __kk_uint_range_drop(range, -1, &dropThrown)
        #expect(kk_list_size(dropped) == 0)
        #expect(dropThrown != 0)
    }

    @Test
    func testUIntRangeChunkedAndWindowedNonPositiveArgumentsThrow() {
        let range = __kk_uint_rangeTo(1, 5)
        var chunkedThrown: Int = 0
        _ = __kk_uint_range_chunked(range, 0, &chunkedThrown)
        #expect(chunkedThrown != 0)

        var windowedSizeThrown: Int = 0
        _ = __kk_uint_range_windowed(range, 0, 1, 0, &windowedSizeThrown)
        #expect(windowedSizeThrown != 0)

        var windowedStepThrown: Int = 0
        _ = __kk_uint_range_windowed(range, 2, 0, 0, &windowedStepThrown)
        #expect(windowedStepThrown != 0)
    }

    @Test
    func testULongRangeTakeAndDropNegativeCountThrows() {
        let range = kk_ulong_rangeTo(1, 5)
        var takeThrown: Int = 0
        let taken = kk_ulong_range_take(range, -1, &takeThrown)
        #expect(kk_list_size(taken) == 0)
        #expect(takeThrown != 0)

        var dropThrown: Int = 0
        let dropped = kk_ulong_range_drop(range, -1, &dropThrown)
        #expect(kk_list_size(dropped) == 0)
        #expect(dropThrown != 0)
    }

    @Test
    func testULongRangeChunkedAndWindowedNonPositiveArgumentsThrow() {
        let range = kk_ulong_rangeTo(1, 5)
        var chunkedThrown: Int = 0
        _ = kk_ulong_range_chunked(range, 0, &chunkedThrown)
        #expect(chunkedThrown != 0)

        var windowedSizeThrown: Int = 0
        _ = kk_ulong_range_windowed(range, 0, 1, 0, &windowedSizeThrown)
        #expect(windowedSizeThrown != 0)

        var windowedStepThrown: Int = 0
        _ = kk_ulong_range_windowed(range, 2, 0, 0, &windowedStepThrown)
        #expect(windowedStepThrown != 0)
    }

    @Test
    func testLongRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_long_rangeTo(1, 4)
        #expect(kk_long_range_firstOrNull(range) == 1)
        #expect(kk_long_range_lastOrNull(range) == 4)

        let empty = kk_long_rangeTo(5, 1)
        #expect(kk_long_range_firstOrNull(empty) == runtimeNullSentinelInt)
        #expect(kk_long_range_lastOrNull(empty) == runtimeNullSentinelInt)
    }

    @Test
    func testRangeWindowedBuildsNestedLists() {
        let range = kk_op_rangeTo(1, 5)
        let windows = kk_range_windowed(range, 3, 2, 0, nil)
        #expect(kk_list_size(windows) == 2)
        #expect(listElements(kk_list_get(windows, 0)) == [1, 2, 3])
        #expect(listElements(kk_list_get(windows, 1)) == [3, 4, 5])
    }

    @Test
    func testRangeReduceOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown: Int = 0
        let result = kk_range_reduce(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, &thrown)
        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
    func testRangeReduceOnSingleElement() {
        let singleRange = kk_op_rangeTo(3, 3)
        let result = kk_range_reduce(singleRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        #expect(result == 3)
    }

    @Test
    func testRangeMapOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let mapped = kk_range_map(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        #expect(kk_list_size(mapped) == 0)
    }

    @Test
    func testRangeFilterOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let filtered = kk_range_filter(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        #expect(kk_list_size(filtered) == 0)
    }

    @Test
    func testRangeFoldOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let result = kk_range_fold(emptyRange, 10, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        #expect(result == 10)
    }

    @Test
    func testRangeWithNegativeStep() {
        let range = __kk_op_downTo(5, 1)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [10, 8, 6, 4, 2])
    }

    @Test
    func testRangeFindOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let found = kk_range_find(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        #expect(found == runtimeNullSentinelInt)
    }

    @Test
    func testRangeAnyAllNoneOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        #expect(kk_range_any(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil) == 0)
        #expect(kk_range_all(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil) == 1)
        #expect(kk_range_none(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil) == 1)
    }

    @Test
    func testRangeChunkedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let chunks = kk_range_chunked(emptyRange, 2, nil)
        #expect(kk_list_size(chunks) == 0)
    }

    @Test
    func testRangeWindowedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let windows = kk_range_windowed(emptyRange, 3, 1, 0, nil)
        #expect(kk_list_size(windows) == 0)
    }

    @Test
    func testRangeForEachIteratesAllElements() {
        let range = kk_op_rangeTo(1, 4)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        #expect(sum == 10)
    }

    @Test
    func testRangeForEachOnDescendingProgression() {
        let range = __kk_op_downTo(5, 3)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        #expect(sum == 12)
    }

    @Test
    func testRangeForEachOnEmptyRangeIsNoOp() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(emptyRange, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        #expect(sum == 0)
    }

    @Test
    func testRangeDropReducesFromFront() {
        let range = kk_op_rangeTo(1, 5)
        let dropped = kk_range_drop(range, 2, nil)
        #expect(listElements(dropped) == [3, 4, 5])
    }

    @Test
    func testRangeDropOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let dropped = kk_range_drop(emptyRange, 2, nil)
        #expect(kk_list_size(dropped) == 0)
    }

    @Test
    func testRangeTakeLimitsFromFront() {
        let range = kk_op_rangeTo(1, 5)
        let taken = kk_range_take(range, 3, nil)
        #expect(listElements(taken) == [1, 2, 3])
    }

    @Test
    func testRangeTakeOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let taken = kk_range_take(emptyRange, 3, nil)
        #expect(kk_list_size(taken) == 0)
    }

    @Test
    func testRangeTakeNegativeCountThrows() {
        let range = kk_op_rangeTo(1, 5)
        var thrown: Int = 0
        let taken = kk_range_take(range, -1, &thrown)
        #expect(kk_list_size(taken) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testRangeDropNegativeCountThrows() {
        let range = kk_op_rangeTo(1, 5)
        var thrown: Int = 0
        let dropped = kk_range_drop(range, -1, &thrown)
        #expect(kk_list_size(dropped) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testRangeChunkedNonPositiveSizeThrows() {
        let range = kk_op_rangeTo(1, 5)
        var thrownForZero: Int = 0
        _ = kk_range_chunked(range, 0, &thrownForZero)
        #expect(thrownForZero != 0)

        var thrownForNegative: Int = 0
        _ = kk_range_chunked(range, -1, &thrownForNegative)
        #expect(thrownForNegative != 0)
    }

    @Test
    func testRangeWindowedNonPositiveSizeThrows() {
        let range = kk_op_rangeTo(1, 5)
        var thrown: Int = 0
        _ = kk_range_windowed(range, 0, 1, 0, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testRangeWindowedNonPositiveStepThrows() {
        let range = kk_op_rangeTo(1, 5)
        var thrown: Int = 0
        _ = kk_range_windowed(range, 2, 0, 0, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testRangeSortedOnDescendingProgressionProducesAscendingList() {
        let range = __kk_op_downTo(5, 1)
        let sorted = kk_range_sorted(range)
        #expect(listElements(sorted) == [1, 2, 3, 4, 5])
    }

    @Test
    func testRangeAverageReturnsDoubleAsBitPattern() {
        let range = kk_op_rangeTo(1, 4)
        let avg = Double(bitPattern: UInt64(bitPattern: Int64(kk_range_average(range))))
        #expect(avg == 2.5)
    }

    @Test
    func testRangeAverageOnSingleElement() {
        let range = kk_op_rangeTo(7, 7)
        let avg = Double(bitPattern: UInt64(bitPattern: Int64(kk_range_average(range))))
        #expect(avg == 7.0)
    }

    @Test
    func testRangeAverageOnEmptyRangeProducesNaN() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let avg = Double(bitPattern: UInt64(bitPattern: Int64(kk_range_average(emptyRange))))
        #expect(avg.isNaN)
    }

    @Test
    func testRangeMapIndexedCombinesIndexAndValue() {
        let range = kk_op_rangeTo(1, 4)
        let mapped = kk_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [1, 3, 5, 7])
    }

    @Test
    func testRangeMapIndexedOnDescendingProgression() {
        let range = __kk_op_downTo(5, 3)
        let mapped = kk_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [5, 5, 5])
    }

    @Test
    func testRangeMapNotNullFiltersNullResults() {
        let range = kk_op_rangeTo(1, 5)
        let mapped = kk_range_mapNotNull(range, unsafeBitCast(rangeMapNotNullOddOnly, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [1, 3, 5])
    }

    @Test
    func testRangeMapNotNullOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let mapped = kk_range_mapNotNull(emptyRange, unsafeBitCast(rangeMapNotNullOddOnly, to: Int.self), 0, nil)
        #expect(kk_list_size(mapped) == 0)
    }

    @Test
    func testRangeFilterIndexedKeepsEvenIndexedElements() {
        let range = kk_op_rangeTo(1, 4)
        let filtered = kk_range_filterIndexed(range, unsafeBitCast(rangeFilterIndexedEvenIndex, to: Int.self), 0, nil)
        #expect(listElements(filtered) == [1, 3])
    }

    @Test
    func testRangeFilterIndexedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let filtered = kk_range_filterIndexed(emptyRange, unsafeBitCast(rangeFilterIndexedEvenIndex, to: Int.self), 0, nil)
        #expect(kk_list_size(filtered) == 0)
    }

    @Test
    func testRangeFindLastReturnsLastMatchingElement() {
        let range = kk_op_rangeTo(1, 6)
        let found = kk_range_findLast(range, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        #expect(found == 6)
    }

    @Test
    func testRangeFindLastOnEmptyRangeReturnsNullSentinel() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let found = kk_range_findLast(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        #expect(found == runtimeNullSentinelInt)
    }

    @Test
    func testRangeReduceIndexedAccumulatesWithIndex() {
        // acc=1(first), then index=1,acc=1,val=2→4; index=2,acc=4,val=3→9; index=3,acc=9,val=4→16
        let range = kk_op_rangeTo(1, 4)
        let result = kk_range_reduceIndexed(range, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, nil)
        #expect(result == 16)
    }

    @Test
    func testRangeReduceIndexedOnSingleElement() {
        let range = kk_op_rangeTo(5, 5)
        let result = kk_range_reduceIndexed(range, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, nil)
        #expect(result == 5)
    }

    @Test
    func testRangeReduceIndexedOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown = 0
        _ = kk_range_reduceIndexed(emptyRange, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testRangeFirstPredicateOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown = 0
        let result = kk_range_first_predicate(emptyRange, unsafeBitCast(rangePredicateEven, to: Int.self), 0, &thrown)
        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
    func testRangeFirstAndLastPredicatesOnSingleElementRange() {
        let singleRange = kk_op_rangeTo(2, 2)
        let predicate = unsafeBitCast(rangePredicateEven, to: Int.self)

        #expect(kk_range_first_predicate(singleRange, predicate, 0, nil) == 2)
        #expect(kk_range_last_predicate(singleRange, predicate, 0, nil) == 2)
    }

    @Test
    func testRangeLastPredicateFindsLastMatchInDescendingProgression() {
        let range = __kk_op_downTo(5, 1)
        let result = kk_range_last_predicate(range, unsafeBitCast(rangePredicateEven, to: Int.self), 0, nil)
        #expect(result == 2)
    }

    @Test
    func testLongRangeForEachIteratesAllElements() {
        let range = kk_long_rangeTo(1, 4)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_long_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        #expect(sum == 10)
    }

    @Test
    func testLongRangeDropReducesFromFront() {
        let range = kk_long_rangeTo(1, 5)
        let dropped = kk_long_range_drop(range, 2, nil)
        #expect(listElements(dropped) == [3, 4, 5])
    }

    @Test
    func testLongRangeTakeLimitsFromFront() {
        let range = kk_long_rangeTo(1, 5)
        let taken = kk_long_range_take(range, 3, nil)
        #expect(listElements(taken) == [1, 2, 3])
    }

    @Test
    func testLongRangeTakeNegativeCountThrows() {
        let range = kk_long_rangeTo(1, 5)
        var thrown: Int = 0
        let taken = kk_long_range_take(range, -1, &thrown)
        #expect(kk_list_size(taken) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testLongRangeDropNegativeCountThrows() {
        let range = kk_long_rangeTo(1, 5)
        var thrown: Int = 0
        let dropped = kk_long_range_drop(range, -1, &thrown)
        #expect(kk_list_size(dropped) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testLongRangeSortedProducesAscendingList() {
        let range = __kk_op_downTo(4, 1)
        let sorted = kk_long_range_sorted(range)
        #expect(listElements(sorted) == [1, 2, 3, 4])
    }

    @Test
    func testLongRangeAverageReturnsDoubleAsBitPattern() {
        let range = kk_long_rangeTo(1, 4)
        let avg = Double(bitPattern: UInt64(bitPattern: Int64(kk_long_range_average(range))))
        #expect(avg == 2.5)
    }

    @Test
    func testLongRangeForEachOnEmptyRangeIsNoOp() {
        let emptyRange = kk_long_rangeTo(5, 1)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_long_range_forEach(emptyRange, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        #expect(sum == 0)
    }

    @Test
    func testLongRangeDropOnEmptyRange() {
        let emptyRange = kk_long_rangeTo(5, 1)
        let dropped = kk_long_range_drop(emptyRange, 2, nil)
        #expect(kk_list_size(dropped) == 0)
    }

    @Test
    func testLongRangeTakeOnSingleElementRange() {
        let singleRange = kk_long_rangeTo(7, 7)
        let taken = kk_long_range_take(singleRange, 3, nil)
        #expect(listElements(taken) == [7])
    }

    @Test
    func testLongRangeAverageOnEmptyRangeProducesNaN() {
        let emptyRange = kk_long_rangeTo(5, 1)
        let avg = Double(bitPattern: UInt64(bitPattern: Int64(kk_long_range_average(emptyRange))))
        #expect(avg.isNaN)
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { kk_list_get(listRaw, $0) }
    }
}
#endif
