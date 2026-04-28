@testable import Runtime
import XCTest

private func makeRuntimeString(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
        }
    }
}

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

    // MARK: - RuntimeNoWhenBranchMatchedExceptionBox

    func testNoWhenBranchMatchedExceptionBoxExceptionFQName() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "missing branch")
        XCTAssertEqual(box.exceptionFQName, "kotlin.NoWhenBranchMatchedException")
    }

    func testNoWhenBranchMatchedExceptionBoxRenderedMessage() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "missing branch")
        XCTAssertEqual(box.renderedMessage, "NoWhenBranchMatchedException: missing branch")
    }

    func testNoWhenBranchMatchedExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.NoWhenBranchMatchedException"))
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"))
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testNoWhenBranchMatchedExceptionBoxHierarchyOrder() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.NoWhenBranchMatchedException",
                       "NoWhenBranchMatchedException should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
    }

    // MARK: - RuntimeConcurrentModificationExceptionBox

    func testConcurrentModificationExceptionBoxExceptionFQName() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "modified")
        XCTAssertEqual(box.exceptionFQName, "kotlin.ConcurrentModificationException")
    }

    func testConcurrentModificationExceptionBoxRenderedMessage() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "modified")
        XCTAssertEqual(box.renderedMessage, "ConcurrentModificationException: modified")
    }

    func testConcurrentModificationExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.ConcurrentModificationException"))
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"))
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testConcurrentModificationExceptionBoxHierarchyOrder() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.ConcurrentModificationException",
                       "ConcurrentModificationException should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
    }

    // MARK: - RuntimeArrayIndexOutOfBoundsExceptionBox

    func testArrayIndexOutOfBoundsExceptionBoxExceptionFQName() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "bad index")
        XCTAssertEqual(box.exceptionFQName, "kotlin.ArrayIndexOutOfBoundsException")
    }

    func testArrayIndexOutOfBoundsExceptionBoxRenderedMessage() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "bad index")
        XCTAssertEqual(box.renderedMessage, "ArrayIndexOutOfBoundsException: bad index")
    }

    func testArrayIndexOutOfBoundsExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.ArrayIndexOutOfBoundsException"))
        XCTAssertTrue(hierarchy.contains("kotlin.IndexOutOfBoundsException"))
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"))
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"))
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"))
    }

    func testArrayIndexOutOfBoundsExceptionBoxHierarchyOrder() throws {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertEqual(hierarchy.first, "kotlin.ArrayIndexOutOfBoundsException",
                       "ArrayIndexOutOfBoundsException should be first in hierarchy")
        XCTAssertEqual(hierarchy.last, "kotlin.Throwable",
                       "Throwable should be last in hierarchy")
        XCTAssertLessThan(
            try XCTUnwrap(hierarchy.firstIndex(of: "kotlin.ArrayIndexOutOfBoundsException")),
            try XCTUnwrap(hierarchy.firstIndex(of: "kotlin.IndexOutOfBoundsException"))
        )
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

    func testNoWhenBranchMatchedBoxIsDistinctFromIllegalStateBox() {
        let noWhenBox = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        XCTAssertFalse(noWhenBox is RuntimeIllegalStateExceptionBox)
    }

    func testConcurrentModificationBoxIsDistinctFromNoWhenBox() {
        let concurrentModificationBox = RuntimeConcurrentModificationExceptionBox(message: "test")
        XCTAssertFalse(concurrentModificationBox is RuntimeNoWhenBranchMatchedExceptionBox)
    }

    func testArrayIndexOutOfBoundsBoxIsDistinctFromConcurrentModificationBox() {
        let arrayIndexBox = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        XCTAssertFalse(arrayIndexBox is RuntimeConcurrentModificationExceptionBox)
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

    func testNoWhenBranchMatchedExceptionBoxWithCause() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "caused no when", cause: 11)
        XCTAssertEqual(box.cause, 11)
    }

    func testConcurrentModificationExceptionBoxWithCause() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "caused concurrent modification", cause: 13)
        XCTAssertEqual(box.cause, 13)
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

    func testNoWhenBranchMatchedExceptionRuntimeConstructors() {
        let messageRaw = makeRuntimeString("missing")
        let messageOnly = kk_no_when_branch_matched_exception_new_message(messageRaw)
        let noArg = kk_no_when_branch_matched_exception_new()
        let withCause = kk_no_when_branch_matched_exception_new_message_cause(messageRaw, noArg)
        let causeOnly = kk_no_when_branch_matched_exception_new_cause(noArg)

        guard let messageOnlyPtr = UnsafeMutableRawPointer(bitPattern: messageOnly),
              let messageOnlyBox = tryCast(messageOnlyPtr, to: RuntimeNoWhenBranchMatchedExceptionBox.self),
              let withCausePtr = UnsafeMutableRawPointer(bitPattern: withCause),
              let withCauseBox = tryCast(withCausePtr, to: RuntimeNoWhenBranchMatchedExceptionBox.self),
              let causeOnlyPtr = UnsafeMutableRawPointer(bitPattern: causeOnly),
              let causeOnlyBox = tryCast(causeOnlyPtr, to: RuntimeNoWhenBranchMatchedExceptionBox.self)
        else {
            return XCTFail("Expected typed NoWhenBranchMatchedException runtime boxes")
        }

        XCTAssertEqual(messageOnlyBox.message, "missing")
        XCTAssertEqual(withCauseBox.message, "missing")
        XCTAssertEqual(withCauseBox.cause, noArg)
        XCTAssertEqual(causeOnlyBox.cause, noArg)
    }

    func testConcurrentModificationExceptionRuntimeConstructors() {
        let messageRaw = makeRuntimeString("modified")
        let messageOnly = kk_concurrent_modification_exception_new_message(messageRaw)
        let noArg = kk_concurrent_modification_exception_new()
        let withCause = kk_concurrent_modification_exception_new_message_cause(messageRaw, noArg)
        let causeOnly = kk_concurrent_modification_exception_new_cause(noArg)

        guard let messageOnlyPtr = UnsafeMutableRawPointer(bitPattern: messageOnly),
              let messageOnlyBox = tryCast(messageOnlyPtr, to: RuntimeConcurrentModificationExceptionBox.self),
              let noArgPtr = UnsafeMutableRawPointer(bitPattern: noArg),
              let noArgBox = tryCast(noArgPtr, to: RuntimeConcurrentModificationExceptionBox.self),
              let withCausePtr = UnsafeMutableRawPointer(bitPattern: withCause),
              let withCauseBox = tryCast(withCausePtr, to: RuntimeConcurrentModificationExceptionBox.self),
              let causeOnlyPtr = UnsafeMutableRawPointer(bitPattern: causeOnly),
              let causeOnlyBox = tryCast(causeOnlyPtr, to: RuntimeConcurrentModificationExceptionBox.self)
        else {
            return XCTFail("Expected typed ConcurrentModificationException runtime boxes")
        }

        XCTAssertEqual(messageOnlyBox.message, "modified")
        XCTAssertEqual(noArgBox.message, "")
        XCTAssertEqual(withCauseBox.message, "modified")
        XCTAssertEqual(withCauseBox.cause, noArg)
        XCTAssertEqual(causeOnlyBox.cause, noArg)
    }

    func testArrayIndexOutOfBoundsExceptionRuntimeConstructors() {
        let messageRaw = makeRuntimeString("bad index")
        let messageOnly = kk_array_index_out_of_bounds_exception_new_message(messageRaw)
        let noArg = kk_array_index_out_of_bounds_exception_new()

        guard let messageOnlyPtr = UnsafeMutableRawPointer(bitPattern: messageOnly),
              let messageOnlyBox = tryCast(messageOnlyPtr, to: RuntimeArrayIndexOutOfBoundsExceptionBox.self),
              let noArgPtr = UnsafeMutableRawPointer(bitPattern: noArg),
              let noArgBox = tryCast(noArgPtr, to: RuntimeArrayIndexOutOfBoundsExceptionBox.self)
        else {
            return XCTFail("Expected typed ArrayIndexOutOfBoundsException runtime boxes")
        }

        XCTAssertEqual(messageOnlyBox.message, "bad index")
        XCTAssertEqual(noArgBox.message, "")
    }
}
