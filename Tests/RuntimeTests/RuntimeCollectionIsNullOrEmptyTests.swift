@testable import Runtime
import XCTest

final class RuntimeCollectionIsNullOrEmptyTests: XCTestCase {
    func testExistingIsEmptyHelpersTreatNullHandlesAsEmpty() {
        XCTAssertEqual(kk_unbox_bool(kk_list_is_empty(0)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_set_is_empty(0)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_map_is_empty(0)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_array_is_empty(0)), 1)
    }
}
