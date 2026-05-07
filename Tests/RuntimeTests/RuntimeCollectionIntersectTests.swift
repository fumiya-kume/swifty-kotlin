@testable import Runtime
import XCTest

final class RuntimeCollectionIntersectTests: XCTestCase {
    func testListIntersectReturnsDeduplicatedSetInReceiverOrder() {
        let left = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 2, 3, 4]))
        let right = registerRuntimeObject(RuntimeListBox(elements: [2, 4, 5]))

        let result = kk_list_intersect(left, right)

        XCTAssertEqual(runtimeSetBox(from: result)?.elements, [2, 4])
    }
}
