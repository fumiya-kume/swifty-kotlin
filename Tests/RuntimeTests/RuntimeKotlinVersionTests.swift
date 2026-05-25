@testable import Runtime
import XCTest

final class RuntimeKotlinVersionTests: XCTestCase {
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

    func testCurrentReturnsStableKotlinVersion() {
        let version = kk_kotlin_version_current()

        XCTAssertEqual(kk_kotlin_version_major(version), 2)
        XCTAssertEqual(kk_kotlin_version_minor(version), 3)
        XCTAssertEqual(kk_kotlin_version_patch(version), 20)
    }

    func testCompareToUsesSemanticVersionOrdering() {
        let lower = kk_kotlin_version_new_patch(2, 1, 20)
        let same = kk_kotlin_version_new_patch(2, 1, 20)
        let higherPatch = kk_kotlin_version_new_patch(2, 1, 21)
        let higherMinor = kk_kotlin_version_new_patch(2, 2, 0)
        let higherMajor = kk_kotlin_version_new_patch(3, 0, 0)

        XCTAssertEqual(kk_kotlin_version_compareTo(lower, same), 0)
        XCTAssertLessThan(kk_kotlin_version_compareTo(lower, higherPatch), 0)
        XCTAssertLessThan(kk_kotlin_version_compareTo(lower, higherMinor), 0)
        XCTAssertLessThan(kk_kotlin_version_compareTo(lower, higherMajor), 0)
        XCTAssertGreaterThan(kk_kotlin_version_compareTo(higherPatch, lower), 0)
    }

    func testIsAtLeastChecksTwoAndThreePartMinimums() {
        let version = kk_kotlin_version_new_patch(2, 1, 20)

        XCTAssertEqual(kk_kotlin_version_isAtLeast(version, 2, 1), 1)
        XCTAssertEqual(kk_kotlin_version_isAtLeast(version, 2, 2), 0)
        XCTAssertEqual(kk_kotlin_version_isAtLeast_patch(version, 2, 1, 20), 1)
        XCTAssertEqual(kk_kotlin_version_isAtLeast_patch(version, 2, 1, 21), 0)
        XCTAssertEqual(kk_kotlin_version_isAtLeast_patch(version, 1, 9, 99), 1)
    }
}
