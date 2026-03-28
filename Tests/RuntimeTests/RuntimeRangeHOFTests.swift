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

    func testRangeWindowedBuildsNestedLists() {
        let range = kk_op_rangeTo(1, 5)
        let windows = kk_range_windowed(range, 3, 2, 0)
        XCTAssertEqual(kk_list_size(windows), 2)
        XCTAssertEqual(listElements(kk_list_get(windows, 0)), [1, 2, 3])
        XCTAssertEqual(listElements(kk_list_get(windows, 1)), [3, 4, 5])
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { kk_list_get(listRaw, $0) }
    }
}
