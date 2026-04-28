@testable import Runtime
import XCTest

final class RuntimeKotlinVersionTests: IsolatedRuntimeXCTestCase {
    func testTwoArgumentConstructorDefaultsPatchToZero() {
        let version = kk_kotlin_version_new(2, 1)

        XCTAssertEqual(kk_kotlin_version_major(version), 2)
        XCTAssertEqual(kk_kotlin_version_minor(version), 1)
        XCTAssertEqual(kk_kotlin_version_patch(version), 0)
    }

    func testThreeArgumentConstructorStoresPatch() {
        let version = kk_kotlin_version_new_patch(2, 1, 20)

        XCTAssertEqual(kk_kotlin_version_major(version), 2)
        XCTAssertEqual(kk_kotlin_version_minor(version), 1)
        XCTAssertEqual(kk_kotlin_version_patch(version), 20)
    }
}
