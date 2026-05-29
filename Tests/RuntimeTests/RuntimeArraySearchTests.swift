@testable import Runtime
import XCTest

final class RuntimeArraySearchTests: XCTestCase {
    func testArrayContainsUsesRuntimeEquality() {
        let array = makeArray([kk_box_int(1), kk_box_int(2), kk_box_int(2)])

        XCTAssertEqual(kk_unbox_bool(kk_array_contains(array, 2)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_array_contains(array, 9)), 0)
    }

    func testArrayIndexOfAndLastIndexOfUseRuntimeEquality() {
        let array = makeArray([kk_box_int(1), kk_box_int(2), kk_box_int(3), kk_box_int(2)])

        XCTAssertEqual(kk_array_indexOf(array, 2), 1)
        XCTAssertEqual(kk_array_lastIndexOf(array, 2), 3)
        XCTAssertEqual(kk_array_indexOf(array, 9), -1)
        XCTAssertEqual(kk_array_lastIndexOf(array, 9), -1)
    }

    func testArraySearchInvalidHandleFallsBackToNotFound() {
        XCTAssertEqual(kk_unbox_bool(kk_array_contains(0, 1)), 0)
        XCTAssertEqual(kk_array_indexOf(0, 1), -1)
        XCTAssertEqual(kk_array_lastIndexOf(0, 1), -1)
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let box = RuntimeArrayBox(length: elements.count)
        for (index, element) in elements.enumerated() {
            box.elements[index] = element
        }
        return registerRuntimeObject(box)
    }
}
