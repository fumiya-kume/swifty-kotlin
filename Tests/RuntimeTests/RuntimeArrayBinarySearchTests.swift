@testable import Runtime
import XCTest

final class RuntimeArrayBinarySearchTests: XCTestCase {
    private func makeArray(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = -1
        for (index, element) in elements.enumerated() {
            let setResult = kk_array_set(array, index, element, &thrown)
            XCTAssertEqual(setResult, element)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    func testArrayBinarySearchUsesExplicitRangeBounds() {
        let array = makeArray([1, 3, 4, 7, 9])

        XCTAssertEqual(kk_array_binarySearch(array, 4, 1, 4), 2)
        XCTAssertEqual(kk_array_binarySearch(array, 1, 1, 4), -2)
    }

    func testULongArrayBinarySearchUsesUnsignedOrdering() {
        let high = Int(bitPattern: UInt(0x8000_0000_0000_0000))
        let array = makeArray([0, 1, high])

        XCTAssertEqual(kk_uLongArray_binarySearch(array, high, 0, 3), 2)
        XCTAssertEqual(kk_uLongArray_binarySearch(array, 1, 0, 3), 1)
    }
}
