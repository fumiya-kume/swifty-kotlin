@testable import Runtime
import Testing

private func makeRuntimeString(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
        }
    }
}

private func runtimeBox<T: AnyObject>(from raw: Int, as type: T.Type) -> T? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: type)
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeAssertionsTests {

    // MARK: - RuntimeAssertionErrorBox

    @Test
    func testAssertionErrorBoxExceptionFQName() {
        let box = RuntimeAssertionErrorBox(message: "assertion failed")
        #expect(box.exceptionFQName == "kotlin.AssertionError")
    }

    @Test
    func testAssertionErrorBoxRenderedMessage() {
        let box = RuntimeAssertionErrorBox(message: "something went wrong")
        #expect(box.renderedMessage == "AssertionError: something went wrong")
    }

    @Test
    func testAssertionErrorBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeAssertionErrorBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.AssertionError"))
        #expect(hierarchy.contains("kotlin.Error"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testAssertionErrorBoxHierarchyOrder() {
        let box = RuntimeAssertionErrorBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.AssertionError",
                "AssertionError should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    @Test
    func testAssertionErrorBoxMessageIsStored() {
        let msg = "custom assertion message"
        let box = RuntimeAssertionErrorBox(message: msg)
        #expect(box.message == msg)
    }

    @Test
    func testAssertionErrorBoxDefaultCauseIsZero() {
        let box = RuntimeAssertionErrorBox(message: "test")
        #expect(box.cause == 0)
    }

    @Test
    func testAssertionErrorBoxIsRuntimeThrowableBox() {
        let box = RuntimeAssertionErrorBox(message: "test")
        #expect(runtimeValueIsThrowableBox(box))
    }

    // MARK: - RuntimeIllegalStateExceptionBox

    @Test
    func testIllegalStateExceptionBoxExceptionFQName() {
        let box = RuntimeIllegalStateExceptionBox(message: "illegal state")
        #expect(box.exceptionFQName == "kotlin.IllegalStateException")
    }

    @Test
    func testIllegalStateExceptionBoxRenderedMessage() {
        let box = RuntimeIllegalStateExceptionBox(message: "bad state")
        #expect(box.renderedMessage == "IllegalStateException: bad state")
    }

    @Test
    func testIllegalStateExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.IllegalStateException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testIllegalStateExceptionBoxHierarchyOrder() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.IllegalStateException",
                "IllegalStateException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    @Test
    func testIllegalStateExceptionBoxMessageIsStored() {
        let msg = "state is invalid"
        let box = RuntimeIllegalStateExceptionBox(message: msg)
        #expect(box.message == msg)
    }

    @Test
    func testIllegalStateExceptionBoxDefaultCauseIsZero() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        #expect(box.cause == 0)
    }

    @Test
    func testIllegalStateExceptionBoxIsRuntimeThrowableBox() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        #expect(runtimeValueIsThrowableBox(box))
    }

    // MARK: - RuntimeIllegalArgumentExceptionBox

    @Test
    func testIllegalArgumentExceptionBoxExceptionFQName() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "bad argument")
        #expect(box.exceptionFQName == "kotlin.IllegalArgumentException")
    }

    @Test
    func testIllegalArgumentExceptionBoxRenderedMessage() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "invalid arg")
        #expect(box.renderedMessage == "IllegalArgumentException: invalid arg")
    }

    @Test
    func testIllegalArgumentExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.IllegalArgumentException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testIllegalArgumentExceptionBoxHierarchyOrder() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.IllegalArgumentException",
                "IllegalArgumentException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    @Test
    func testIllegalArgumentExceptionBoxMessageIsStored() {
        let msg = "argument must be positive"
        let box = RuntimeIllegalArgumentExceptionBox(message: msg)
        #expect(box.message == msg)
    }

    @Test
    func testIllegalArgumentExceptionBoxDefaultCauseIsZero() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        #expect(box.cause == 0)
    }

    @Test
    func testIllegalArgumentExceptionBoxIsRuntimeThrowableBox() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        #expect(runtimeValueIsThrowableBox(box))
    }

    // MARK: - RuntimeNoWhenBranchMatchedExceptionBox

    @Test
    func testNoWhenBranchMatchedExceptionBoxExceptionFQName() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "missing branch")
        #expect(box.exceptionFQName == "kotlin.NoWhenBranchMatchedException")
    }

    @Test
    func testNoWhenBranchMatchedExceptionBoxRenderedMessage() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "missing branch")
        #expect(box.renderedMessage == "NoWhenBranchMatchedException: missing branch")
    }

    @Test
    func testNoWhenBranchMatchedExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.NoWhenBranchMatchedException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testNoWhenBranchMatchedExceptionBoxHierarchyOrder() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.NoWhenBranchMatchedException",
                "NoWhenBranchMatchedException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    // MARK: - RuntimeConcurrentModificationExceptionBox

    @Test
    func testConcurrentModificationExceptionBoxExceptionFQName() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "modified")
        #expect(box.exceptionFQName == "kotlin.ConcurrentModificationException")
    }

    @Test
    func testConcurrentModificationExceptionBoxRenderedMessage() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "modified")
        #expect(box.renderedMessage == "ConcurrentModificationException: modified")
    }

    @Test
    func testConcurrentModificationExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.ConcurrentModificationException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testConcurrentModificationExceptionBoxHierarchyOrder() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.ConcurrentModificationException",
                "ConcurrentModificationException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    // MARK: - RuntimeInvalidMutabilityExceptionBox

    @Test
    func testInvalidMutabilityExceptionBoxRuntimeIdentity() {
        let box = RuntimeInvalidMutabilityExceptionBox(message: "mutation blocked")
        #expect(box.exceptionFQName == "kotlin.native.concurrent.InvalidMutabilityException")
        #expect(box.message == "mutation blocked")
        #expect(box.cause == 0)
        #expect(box.renderedMessage == "InvalidMutabilityException: mutation blocked")
        #expect(box.exceptionHierarchyFQNames == [
            "kotlin.native.concurrent.InvalidMutabilityException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ])
        #expect(runtimeValueIsThrowableBox(box))
    }

    // MARK: - RuntimeArrayIndexOutOfBoundsExceptionBox

    @Test
    func testArrayIndexOutOfBoundsExceptionBoxExceptionFQName() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "bad index")
        #expect(box.exceptionFQName == "kotlin.ArrayIndexOutOfBoundsException")
    }

    @Test
    func testArrayIndexOutOfBoundsExceptionBoxRenderedMessage() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "bad index")
        #expect(box.renderedMessage == "ArrayIndexOutOfBoundsException: bad index")
    }

    @Test
    func testArrayIndexOutOfBoundsExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.ArrayIndexOutOfBoundsException"))
        #expect(hierarchy.contains("kotlin.IndexOutOfBoundsException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testArrayIndexOutOfBoundsExceptionBoxHierarchyOrder() throws {
        let box = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.ArrayIndexOutOfBoundsException",
                "ArrayIndexOutOfBoundsException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
        let arrayIndex = try #require(hierarchy.firstIndex(of: "kotlin.ArrayIndexOutOfBoundsException"))
        let indexOutOfBounds = try #require(hierarchy.firstIndex(of: "kotlin.IndexOutOfBoundsException"))
        #expect(arrayIndex < indexOutOfBounds)
    }

    // MARK: - RuntimeNegativeArraySizeExceptionBox

    @Test
    func testNegativeArraySizeExceptionBoxExceptionFQName() {
        let box = RuntimeNegativeArraySizeExceptionBox(message: "-1")
        #expect(box.exceptionFQName == "kotlin.NegativeArraySizeException")
    }

    @Test
    func testNegativeArraySizeExceptionBoxRenderedMessage() {
        let box = RuntimeNegativeArraySizeExceptionBox(message: "-1")
        #expect(box.renderedMessage == "NegativeArraySizeException: -1")
    }

    @Test
    func testNegativeArraySizeExceptionBoxHierarchyContainsExpectedTypes() {
        let box = RuntimeNegativeArraySizeExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.contains("kotlin.NegativeArraySizeException"))
        #expect(hierarchy.contains("kotlin.RuntimeException"))
        #expect(hierarchy.contains("kotlin.Exception"))
        #expect(hierarchy.contains("kotlin.Throwable"))
    }

    @Test
    func testNegativeArraySizeExceptionBoxHierarchyOrder() {
        let box = RuntimeNegativeArraySizeExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        #expect(hierarchy.first == "kotlin.NegativeArraySizeException",
                "NegativeArraySizeException should be first in hierarchy")
        #expect(hierarchy.last == "kotlin.Throwable",
                "Throwable should be last in hierarchy")
    }

    // MARK: - Type Discrimination

    @Test
    func testAssertionErrorBoxIsDistinctFromIllegalStateBox() {
        let assertionBox = RuntimeAssertionErrorBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(assertionBox, RuntimeIllegalStateExceptionBox.self)
        )
    }

    @Test
    func testAssertionErrorBoxIsDistinctFromIllegalArgumentBox() {
        let assertionBox = RuntimeAssertionErrorBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(assertionBox, RuntimeIllegalArgumentExceptionBox.self)
        )
    }

    @Test
    func testIllegalStateBoxIsDistinctFromIllegalArgumentBox() {
        let stateBox = RuntimeIllegalStateExceptionBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(stateBox, RuntimeIllegalArgumentExceptionBox.self)
        )
    }

    @Test
    func testNoWhenBranchMatchedBoxIsDistinctFromIllegalStateBox() {
        let noWhenBox = RuntimeNoWhenBranchMatchedExceptionBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(noWhenBox, RuntimeIllegalStateExceptionBox.self)
        )
    }

    @Test
    func testConcurrentModificationBoxIsDistinctFromNoWhenBox() {
        let concurrentModificationBox = RuntimeConcurrentModificationExceptionBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(
                concurrentModificationBox,
                RuntimeNoWhenBranchMatchedExceptionBox.self
            )
        )
    }

    @Test
    func testArrayIndexOutOfBoundsBoxIsDistinctFromConcurrentModificationBox() {
        let arrayIndexBox = RuntimeArrayIndexOutOfBoundsExceptionBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(
                arrayIndexBox,
                RuntimeConcurrentModificationExceptionBox.self
            )
        )
    }

    @Test
    func testNegativeArraySizeBoxIsDistinctFromArrayIndexOutOfBoundsBox() {
        let negativeArraySizeBox = RuntimeNegativeArraySizeExceptionBox(message: "test")
        #expect(
            !runtimeThrowableBoxHasExactType(
                negativeArraySizeBox,
                RuntimeArrayIndexOutOfBoundsExceptionBox.self
            )
        )
    }

    // MARK: - Cause Parameter

    @Test
    func testAssertionErrorBoxWithCause() {
        let box = RuntimeAssertionErrorBox(message: "caused error", cause: 42)
        #expect(box.cause == 42)
    }

    @Test
    func testIllegalStateExceptionBoxWithCause() {
        let box = RuntimeIllegalStateExceptionBox(message: "caused state", cause: 99)
        #expect(box.cause == 99)
    }

    @Test
    func testIllegalArgumentExceptionBoxWithCause() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "caused arg", cause: 7)
        #expect(box.cause == 7)
    }

    @Test
    func testNoWhenBranchMatchedExceptionBoxWithCause() {
        let box = RuntimeNoWhenBranchMatchedExceptionBox(message: "caused no when", cause: 11)
        #expect(box.cause == 11)
    }

    @Test
    func testConcurrentModificationExceptionBoxWithCause() {
        let box = RuntimeConcurrentModificationExceptionBox(message: "caused concurrent modification", cause: 13)
        #expect(box.cause == 13)
    }

    // MARK: - Empty Message

    @Test
    func testAssertionErrorBoxWithEmptyMessage() {
        let box = RuntimeAssertionErrorBox(message: "")
        #expect(box.renderedMessage == "AssertionError: ")
    }

    @Test
    func testIllegalStateExceptionBoxWithEmptyMessage() {
        let box = RuntimeIllegalStateExceptionBox(message: "")
        #expect(box.renderedMessage == "IllegalStateException: ")
    }

    @Test
    func testIllegalArgumentExceptionBoxWithEmptyMessage() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "")
        #expect(box.renderedMessage == "IllegalArgumentException: ")
    }

    @Test
    func testNoWhenBranchMatchedExceptionRuntimeConstructors() throws {
        let messageRaw = makeRuntimeString("missing")
        let messageOnly = kk_no_when_branch_matched_exception_new_message(messageRaw)
        let noArg = kk_no_when_branch_matched_exception_new()
        let withCause = kk_no_when_branch_matched_exception_new_message_cause(messageRaw, noArg)
        let causeOnly = kk_no_when_branch_matched_exception_new_cause(noArg)

        let messageOnlyBox = try #require(
            runtimeBox(from: messageOnly, as: RuntimeNoWhenBranchMatchedExceptionBox.self),
            "Expected typed NoWhenBranchMatchedException runtime boxes"
        )
        let withCauseBox = try #require(
            runtimeBox(from: withCause, as: RuntimeNoWhenBranchMatchedExceptionBox.self),
            "Expected typed NoWhenBranchMatchedException runtime boxes"
        )
        let causeOnlyBox = try #require(
            runtimeBox(from: causeOnly, as: RuntimeNoWhenBranchMatchedExceptionBox.self),
            "Expected typed NoWhenBranchMatchedException runtime boxes"
        )

        #expect(messageOnlyBox.message == "missing")
        #expect(withCauseBox.message == "missing")
        #expect(withCauseBox.cause == noArg)
        #expect(causeOnlyBox.cause == noArg)
    }

    @Test
    func testConcurrentModificationExceptionRuntimeConstructors() throws {
        let messageRaw = makeRuntimeString("modified")
        let messageOnly = kk_concurrent_modification_exception_new_message(messageRaw)
        let noArg = kk_concurrent_modification_exception_new()
        let withCause = kk_concurrent_modification_exception_new_message_cause(messageRaw, noArg)
        let causeOnly = kk_concurrent_modification_exception_new_cause(noArg)

        let messageOnlyBox = try #require(
            runtimeBox(from: messageOnly, as: RuntimeConcurrentModificationExceptionBox.self),
            "Expected typed ConcurrentModificationException runtime boxes"
        )
        let noArgBox = try #require(
            runtimeBox(from: noArg, as: RuntimeConcurrentModificationExceptionBox.self),
            "Expected typed ConcurrentModificationException runtime boxes"
        )
        let withCauseBox = try #require(
            runtimeBox(from: withCause, as: RuntimeConcurrentModificationExceptionBox.self),
            "Expected typed ConcurrentModificationException runtime boxes"
        )
        let causeOnlyBox = try #require(
            runtimeBox(from: causeOnly, as: RuntimeConcurrentModificationExceptionBox.self),
            "Expected typed ConcurrentModificationException runtime boxes"
        )

        #expect(messageOnlyBox.message == "modified")
        #expect(noArgBox.message == nil)
        #expect(withCauseBox.message == "modified")
        #expect(withCauseBox.cause == noArg)
        #expect(causeOnlyBox.message == "java.util.ConcurrentModificationException")
        #expect(causeOnlyBox.cause == noArg)
    }

    @Test
    func testInvalidMutabilityExceptionRuntimeConstructor() throws {
        let messageRaw = makeRuntimeString("mutation blocked")
        let raw = kk_invalid_mutability_exception_new_message(messageRaw)
        let box = try #require(
            runtimeBox(from: raw, as: RuntimeInvalidMutabilityExceptionBox.self),
            "Expected a typed InvalidMutabilityException runtime box"
        )

        #expect(box.message == "mutation blocked")
        #expect(box.cause == 0)
    }

    @Test
    func testSourceBackedExceptionCauseOnlyConstructors() throws {
        let cause = kk_exception_new()

        #expect(runtimeBox(from: kk_error_new_cause(cause), as: RuntimeErrorBox.self) != nil)
        #expect(runtimeBox(from: kk_exception_new_cause(cause), as: RuntimeExceptionBox.self) != nil)
        #expect(runtimeBox(from: kk_illegal_argument_exception_new_cause(cause), as: RuntimeIllegalArgumentExceptionBox.self) != nil)
        #expect(runtimeBox(from: kk_illegal_state_exception_new_cause(cause), as: RuntimeIllegalStateExceptionBox.self) != nil)
        #expect(runtimeBox(from: kk_unsupported_operation_exception_new_cause(cause), as: RuntimeUnsupportedOperationExceptionBox.self) != nil)
        #expect(runtimeBox(from: kk_uninitialized_property_access_exception_new_cause(cause), as: RuntimeUninitializedPropertyAccessExceptionBox.self) != nil)
    }

    @Test
    func testIllegalStateExceptionCauseOnlyUsesJVMExceptionFQName() throws {
        let messageRaw = makeRuntimeString("root")
        let runtimeCause = kk_illegal_argument_exception_new_message(messageRaw)
        let runtimeWrapped = try #require(
            runtimeBox(from: kk_illegal_state_exception_new_cause(runtimeCause), as: RuntimeIllegalStateExceptionBox.self)
        )
        #expect(runtimeWrapped.message == "java.lang.IllegalArgumentException: root")

        let javaUtilCause = kk_no_such_element_exception_new_message(messageRaw)
        let javaUtilWrapped = try #require(
            runtimeBox(from: kk_illegal_state_exception_new_cause(javaUtilCause), as: RuntimeIllegalStateExceptionBox.self)
        )
        #expect(javaUtilWrapped.message == "java.util.NoSuchElementException: root")

        let genericCause = Int(bitPattern: __kk_throwable_new(UnsafeMutableRawPointer(bitPattern: messageRaw)))
        let genericWrapped = try #require(
            runtimeBox(from: kk_illegal_state_exception_new_cause(genericCause), as: RuntimeIllegalStateExceptionBox.self)
        )
        #expect(genericWrapped.message == "java.lang.Throwable: root")
    }

    @Test
    func testArrayIndexOutOfBoundsExceptionRuntimeConstructors() throws {
        let messageRaw = makeRuntimeString("bad index")
        let messageOnly = kk_array_index_out_of_bounds_exception_new_message(messageRaw)
        let noArg = kk_array_index_out_of_bounds_exception_new()

        let messageOnlyBox = try #require(
            runtimeBox(from: messageOnly, as: RuntimeArrayIndexOutOfBoundsExceptionBox.self),
            "Expected typed ArrayIndexOutOfBoundsException runtime boxes"
        )
        let noArgBox = try #require(
            runtimeBox(from: noArg, as: RuntimeArrayIndexOutOfBoundsExceptionBox.self),
            "Expected typed ArrayIndexOutOfBoundsException runtime boxes"
        )

        #expect(messageOnlyBox.message == "bad index")
        #expect(noArgBox.message == nil)
    }

    @Test
    func testNegativeArraySizeExceptionRuntimeConstructors() throws {
        let messageRaw = makeRuntimeString("-1")
        let messageOnly = kk_negative_array_size_exception_new_message(messageRaw)
        let noArg = kk_negative_array_size_exception_new()

        let messageOnlyBox = try #require(
            runtimeBox(from: messageOnly, as: RuntimeNegativeArraySizeExceptionBox.self),
            "Expected typed NegativeArraySizeException runtime boxes"
        )
        let noArgBox = try #require(
            runtimeBox(from: noArg, as: RuntimeNegativeArraySizeExceptionBox.self),
            "Expected typed NegativeArraySizeException runtime boxes"
        )

        #expect(messageOnlyBox.message == "-1")
        #expect(noArgBox.message == nil)
    }

    // MARK: - kk_array_new_checked

    @Test
    func testArrayNewCheckedRejectsNegativeSizeWithoutAllocating() throws {
        var thrown: Int = 0
        let result = withUnsafeMutablePointer(to: &thrown) { kk_array_new_checked(-1, $0) }
        #expect(result == 0)
        #expect(thrown != 0)

        let box = try #require(
            runtimeBox(from: thrown, as: RuntimeNegativeArraySizeExceptionBox.self),
            "Expected kk_array_new_checked to throw a typed NegativeArraySizeException box"
        )
        #expect(box.message == "-1")
    }

    @Test
    func testArrayNewCheckedAllocatesNormallyForNonNegativeSize() {
        var thrown: Int = 0
        let result = withUnsafeMutablePointer(to: &thrown) { kk_array_new_checked(3, $0) }
        #expect(thrown == 0)
        #expect(result != 0)
        #expect(kk_array_size(result) == 3)
    }

    @Test
    func testArrayNewCheckedZeroFillsReferenceSlots() {
        var thrown: Int = 0
        let result = withUnsafeMutablePointer(to: &thrown) { kk_array_new_checked(2, $0) }
        #expect(thrown == 0)
        #expect(result != 0)
        #expect(kk_array_get(result, 0, &thrown) == 0)
        #expect(kk_array_get(result, 1, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func testArrayNewCheckedZeroSizeDoesNotThrow() {
        var thrown: Int = 0
        let result = withUnsafeMutablePointer(to: &thrown) { kk_array_new_checked(0, $0) }
        #expect(thrown == 0)
        #expect(result != 0)
        #expect(kk_array_size(result) == 0)
    }
}
