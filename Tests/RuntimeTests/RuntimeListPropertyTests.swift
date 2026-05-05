@testable import Runtime
import XCTest

final class RuntimeListPropertyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return kk_list_of(arrayRaw, elements.count)
    }

    func testListIndicesReturnsZeroBasedRange() {
        let indices = kk_list_indices(makeList([10, 20, 30]))

        XCTAssertEqual(kk_range_first(indices), 0)
        XCTAssertEqual(kk_range_last(indices), 2)
        XCTAssertEqual(kk_range_isEmpty(indices), 0)
    }

    func testListIndicesReturnsEmptyRangeForEmptyList() {
        let indices = kk_list_indices(makeList([]))

        XCTAssertEqual(kk_range_first(indices), 0)
        XCTAssertEqual(kk_range_last(indices), -1)
        XCTAssertEqual(kk_range_isEmpty(indices), 1)
    }
}
