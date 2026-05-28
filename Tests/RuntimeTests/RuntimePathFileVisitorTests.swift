import Foundation
@testable import Runtime
import XCTest

/// Tests for `kk_path_fileVisitor` (STDLIB-IO-PATH-FN-018).
///
/// `fileVisitor(builderAction: FileVisitorBuilder.() -> Unit): FileVisitor<Path>`
/// creates an opaque `FileVisitor<Path>` handle by running the DSL builder lambda.
final class RuntimePathFileVisitorTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Helpers

    private func runtimeFileVisitorBox(from raw: Int) -> RuntimeFileVisitorBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return tryCast(ptr, to: RuntimeFileVisitorBox.self)
    }

    // MARK: - Tests

    func testFileVisitorWithNullBuilderActionReturnsNonZero() {
        // A zero builderAction means "no DSL body" — should still return a valid handle.
        let resultRaw = kk_path_fileVisitor(0)
        XCTAssertNotEqual(resultRaw, 0)
    }

    func testFileVisitorWithNullBuilderActionProducesVisitorBox() {
        let resultRaw = kk_path_fileVisitor(0)
        let box = runtimeFileVisitorBox(from: resultRaw)
        XCTAssertNotNil(box, "kk_path_fileVisitor should return a RuntimeFileVisitorBox handle")
    }

    func testFileVisitorWithNullBuilderActionHasZeroCallbacks() {
        let resultRaw = kk_path_fileVisitor(0)
        let box = runtimeFileVisitorBox(from: resultRaw)
        XCTAssertNotNil(box)
        XCTAssertEqual(box?.preVisitDirectoryRaw, 0)
        XCTAssertEqual(box?.visitFileRaw, 0)
        XCTAssertEqual(box?.visitFileFailedRaw, 0)
        XCTAssertEqual(box?.postVisitDirectoryRaw, 0)
    }

    func testFileVisitorReturnsDifferentHandlesForDistinctCalls() {
        let first = kk_path_fileVisitor(0)
        let second = kk_path_fileVisitor(0)
        // Each call should allocate a distinct object.
        XCTAssertNotEqual(first, second)
    }
}
