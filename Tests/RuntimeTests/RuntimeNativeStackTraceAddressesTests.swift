@testable import Runtime
import XCTest

final class RuntimeNativeStackTraceAddressesTests: IsolatedRuntimeXCTestCase {
    func testGetStackTraceAddressesReturnsRuntimeList() throws {
        let raw = kk_native_getStackTraceAddresses()
        let ptr = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: raw))
        let list = try XCTUnwrap(tryCast(ptr, to: RuntimeListBox.self))

        XCTAssertFalse(list.elements.isEmpty)
    }
}
