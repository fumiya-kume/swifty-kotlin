@testable import Runtime
import XCTest

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

final class RuntimeRangeHOFTests: IsolatedRuntimeXCTestCase {
    func testRangeMapProducesMappedList() {
        let range = kk_op_rangeTo(1, 4)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [2, 4, 6, 8])
    }

    func testRangeFilterNotDropsMatchingElements() {
        let range = kk_op_rangeTo(1, 5)
        let filtered = kk_range_filterNot(range, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(filtered), [1, 3, 5])
    }

    func testRangeFoldIndexedAccumulatesWithIndex() {
        let range = kk_op_rangeTo(1, 3)
        let result = kk_range_foldIndexed(range, 10, unsafeBitCast(rangeFoldIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(result, 19)
    }

    func testRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_op_rangeTo(1, 4)
        XCTAssertEqual(kk_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_range_lastOrNull(range), 4)
    }

    func testUIntRangeMapIndexedUsesUnsignedLowering() {
        let range = kk_uint_rangeTo(1, 4)
        let mapped = kk_uint_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5, 7])
    }

    func testULongRangeNoArgOrIndexedHOFs() {
        let range = kk_ulong_rangeTo(1, 4)
        XCTAssertEqual(kk_ulong_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_ulong_range_lastOrNull(range), 4)

        let mapped = kk_ulong_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5, 7])
    }

    func testLongRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_long_rangeTo(1, 4)
        XCTAssertEqual(kk_long_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_long_range_lastOrNull(range), 4)

        let empty = kk_long_rangeTo(5, 1)
        XCTAssertEqual(kk_long_range_firstOrNull(empty), runtimeNullSentinelInt)
        XCTAssertEqual(kk_long_range_lastOrNull(empty), runtimeNullSentinelInt)
    }

    func testRangeWindowedBuildsNestedLists() {
        let range = kk_op_rangeTo(1, 5)
        let windows = kk_range_windowed(range, 3, 2, 0)
        XCTAssertEqual(kk_list_size(windows), 2)
        XCTAssertEqual(listElements(kk_list_get(windows, 0)), [1, 2, 3])
        XCTAssertEqual(listElements(kk_list_get(windows, 1)), [3, 4, 5])
    }

    func testRangeReduceOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown: Int = 0
        let result = kk_range_reduce(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testRangeReduceOnSingleElement() {
        let singleRange = kk_op_rangeTo(3, 3)
        let result = kk_range_reduce(singleRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(result, 3)
    }

    func testRangeMapOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let mapped = kk_range_map(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(mapped), 0)
    }

    func testRangeFilterOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let filtered = kk_range_filter(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(filtered), 0)
    }

    func testRangeFoldOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let result = kk_range_fold(emptyRange, 10, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(result, 10)
    }

    func testRangeWithNegativeStep() {
        let range = kk_op_downTo(5, 1)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [10, 8, 6, 4, 2])
    }

    func testRangeFindOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let found = kk_range_find(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(found, runtimeNullSentinelInt)
    }

    func testRangeAnyAllNoneOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        XCTAssertEqual(kk_range_any(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 0)
        XCTAssertEqual(kk_range_all(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 1)
        XCTAssertEqual(kk_range_none(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 1)
    }

    func testRangeChunkedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let chunks = kk_range_chunked(emptyRange, 2)
        XCTAssertEqual(kk_list_size(chunks), 0)
    }

    func testRangeWindowedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let windows = kk_range_windowed(emptyRange, 3, 1, 0)
        XCTAssertEqual(kk_list_size(windows), 0)
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { kk_list_get(listRaw, $0) }
    }
}
