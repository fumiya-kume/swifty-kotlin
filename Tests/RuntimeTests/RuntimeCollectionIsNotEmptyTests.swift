@testable import Runtime
import XCTest

final class RuntimeCollectionIsNotEmptyTests: XCTestCase {
    func testListIsNotEmptyReturnsBoxedBoolean() {
        let nonEmpty = registerRuntimeObject(RuntimeListBox(elements: [1]))
        let empty = registerRuntimeObject(RuntimeListBox(elements: []))

        XCTAssertEqual(kk_unbox_bool(kk_list_is_not_empty(nonEmpty)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_list_is_not_empty(empty)), 0)
    }
}
