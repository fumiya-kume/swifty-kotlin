@testable import Runtime
import XCTest

final class RuntimeAssertionsTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        // No global state to reset for these typed exception box tests
    }

    // MARK: - RuntimeAssertionErrorBox

    func testAssertionErrorBoxExceptionFQName() {
        let box = RuntimeAssertionErrorBox(message: "assertion failed")
        XCTAssertEqual(box.exceptionFQName, "kotlin.AssertionError")
    }

    func testAssertionErrorBoxRenderedMessage() {
        let box = RuntimeAssertionErrorBox(message: "something went wrong")
        XCTAssertEqual(box.renderedMessage, "AssertionError: something went wrong")
    }

    func testAssertionErrorBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeAssertionErrorBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.AssertionError"))
        XCTAssertTrue(hierarchy.contains("kotlin.Error"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testAssertionErrorBoxHierarchyOrder() {
        let box = RuntimeAssertionErrorBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.AssertionError",
                       "AssertionError should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
    }

    func testAssertionErrorBoxMessageIsStored() {
        let msg = "custom assertion message"
        let box = RuntimeAssertionErrorBox(message: msg)
        XCTAssertEqual(box.message, msg)
    }

    func testAssertionErrorBoxDefaultCauseIsZero() {
        let box = RuntimeAssertionErrorBox(message: "test")
        XCTAssertEqual(box.cause, 0)
    }

    func testAssertionErrorBoxIsRuntimeThrowableBox() {
        let box = RuntimeAssertionErrorBox(message: "test")
        XCTAssertTrue(box is RuntimeThrowableBox)
    }

    // MARK: - RuntimeIllegalStateExceptionBox

    func testIllegalStateExceptionBoxExceptionFQName() {
        let box = RuntimeIllegalStateExceptionBox(message: "illegal state")
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalStateException")
    }

    func testIllegalStateExceptionBoxRenderedMessage() {
        let box = RuntimeIllegalStateExceptionBox(message: "bad state")
        XCTAssertEqual(box.renderedMessage, "IllegalStateException: bad state")
    }

    func testIllegalStateExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.IllegalStateException"))
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"))
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testIllegalStateExceptionBoxHierarchyOrder() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.IllegalStateException",
                       "IllegalStateException should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
    }

    func testIllegalStateExceptionBoxMessageIsStored() {
        let msg = "state is invalid"
        let box = RuntimeIllegalStateExceptionBox(message: msg)
        XCTAssertEqual(box.message, msg)
    }

    func testIllegalStateExceptionBoxDefaultCauseIsZero() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        XCTAssertEqual(box.cause, 0)
    }

    func testIllegalStateExceptionBoxIsRuntimeThrowableBox() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        XCTAssertTrue(box is RuntimeThrowableBox)
    }

    // MARK: - RuntimeIllegalArgumentExceptionBox

    func testIllegalArgumentExceptionBoxExceptionFQName() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "bad argument")
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException")
    }

    func testIllegalArgumentExceptionBoxRenderedMessage() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "invalid arg")
        XCTAssertEqual(box.renderedMessage, "IllegalArgumentException: invalid arg")
    }

    func testIllegalArgumentExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.IllegalArgumentException"))
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"))
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testIllegalArgumentExceptionBoxHierarchyOrder() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.IllegalArgumentException",
                       "IllegalArgumentException should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
    }

    func testIllegalArgumentExceptionBoxMessageIsStored() {
        let msg = "argument must be positive"
        let box = RuntimeIllegalArgumentExceptionBox(message: msg)
        XCTAssertEqual(box.message, msg)
    }

    func testIllegalArgumentExceptionBoxDefaultCauseIsZero() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        XCTAssertEqual(box.cause, 0)
    }

    func testIllegalArgumentExceptionBoxIsRuntimeThrowableBox() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        XCTAssertTrue(box is RuntimeThrowableBox)
    }

    // MARK: - Type Discrimination

    func testAssertionErrorBoxIsDistinctFromIllegalStateBox() {
        let assertionBox = RuntimeAssertionErrorBox(message: "test")
        XCTAssertFalse(assertionBox is RuntimeIllegalStateExceptionBox)
    }

    func testAssertionErrorBoxIsDistinctFromIllegalArgumentBox() {
        let assertionBox = RuntimeAssertionErrorBox(message: "test")
        XCTAssertFalse(assertionBox is RuntimeIllegalArgumentExceptionBox)
    }

    func testIllegalStateBoxIsDistinctFromIllegalArgumentBox() {
        let stateBox = RuntimeIllegalStateExceptionBox(message: "test")
        XCTAssertFalse(stateBox is RuntimeIllegalArgumentExceptionBox)
    }

    // MARK: - Cause Parameter

    func testAssertionErrorBoxWithCause() {
        let box = RuntimeAssertionErrorBox(message: "caused error", cause: 42)
        XCTAssertEqual(box.cause, 42)
    }

    func testIllegalStateExceptionBoxWithCause() {
        let box = RuntimeIllegalStateExceptionBox(message: "caused state", cause: 99)
        XCTAssertEqual(box.cause, 99)
    }

    func testIllegalArgumentExceptionBoxWithCause() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "caused arg", cause: 7)
        XCTAssertEqual(box.cause, 7)
    }

    // MARK: - Empty Message

    func testAssertionErrorBoxWithEmptyMessage() {
        let box = RuntimeAssertionErrorBox(message: "")
        XCTAssertEqual(box.renderedMessage, "AssertionError: ")
    }

    func testIllegalStateExceptionBoxWithEmptyMessage() {
        let box = RuntimeIllegalStateExceptionBox(message: "")
        XCTAssertEqual(box.renderedMessage, "IllegalStateException: ")
    }

    func testIllegalArgumentExceptionBoxWithEmptyMessage() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "")
        XCTAssertEqual(box.renderedMessage, "IllegalArgumentException: ")
    }
}
