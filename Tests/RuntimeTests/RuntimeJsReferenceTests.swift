@testable import Runtime
import XCTest

final class RuntimeJsReferenceTests: XCTestCase {
    func testJsReferenceGetUnwrapsStoredValue() {
        let valueRaw = kk_box_int(42)
        let referenceRaw = registerRuntimeObject(RuntimeJsReferenceBox(valueRaw: valueRaw))
        XCTAssertEqual(kk_js_reference_get(referenceRaw), valueRaw)
        XCTAssertEqual(kk_unbox_int(kk_js_reference_get(referenceRaw)), 42)
    }
}
