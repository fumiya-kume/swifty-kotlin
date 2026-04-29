@testable import Runtime
import XCTest

final class RuntimeNativeIdentityHashCodeTests: IsolatedRuntimeXCTestCase {
    func testIdentityHashCodeIsStableForRuntimeObject() {
        let objectRaw = kk_array_new(0)
        let first = kk_native_identityHashCode(objectRaw)
        let second = kk_native_identityHashCode(objectRaw)

        XCTAssertNotEqual(first, 0)
        XCTAssertEqual(first, second)
    }

    func testIdentityHashCodeReturnsZeroForNull() {
        XCTAssertEqual(kk_native_identityHashCode(0), 0)
        XCTAssertEqual(kk_native_identityHashCode(runtimeNullSentinelInt), 0)
    }
}
