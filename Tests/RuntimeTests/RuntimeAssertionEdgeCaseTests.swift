@testable import Runtime
import XCTest

// STDLIB-ASSERT-001: Edge case coverage for Kotlin assertion APIs.
//
// Covers:
//  - assert(value) / assert(value, lazyMessage)        -> AssertionError
//  - check(value) / check(value, lazyMessage)          -> IllegalStateException
//  - require(value) / require(value, lazyMessage)      -> IllegalArgumentException
//  - error(message)                                    -> IllegalStateException (always)
//  - lazy message not evaluated when condition is true
//  - message toString behavior (null sentinel, Int box, Bool box)
//  - exception type discrimination
//
// NOTE: checkNotNull / requireNotNull runtime entry points (kk_check_not_null /
// kk_require_not_null) are not yet implemented in Sources/Runtime/RuntimePreconditions.swift.
// Those APIs are tracked as a known gap — see PR body for STDLIB-ASSERT-001.

// Helpers for constructing runtime string boxes to pass as message arguments.
private func makeRuntimeString(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
        }
    }
}

private func makeRuntimeIntBox(_ value: Int) -> Int {
    let box = RuntimeIntBox(value)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func makeRuntimeBoolBox(_ value: Bool) -> Int {
    let box = RuntimeBoolBox(value)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

// Lazy thunks

private let lazyNotInvoked_Lock = NSLock()
nonisolated(unsafe) private var _lazyNotInvoked_Counter = 0
nonisolated(unsafe) private var lazyNotInvoked_Counter: Int {
    get { lazyNotInvoked_Lock.lock(); defer { lazyNotInvoked_Lock.unlock() }; return _lazyNotInvoked_Counter }
    set { lazyNotInvoked_Lock.lock(); defer { lazyNotInvoked_Lock.unlock() }; _lazyNotInvoked_Counter = newValue }
}

private let lazyCountingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    lazyNotInvoked_Counter += 1
    // Return null sentinel — treated as "null" string by runtimePreconditionMessage
    return runtimeNullSentinelInt
}

private let lazyStringThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let msg = "lazy-msg"
    return msg.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: msg.utf8.count) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(msg.utf8.count)))
        }
    }
}

final class RuntimeAssertionEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        lazyNotInvoked_Counter = 0
        _ = kk_assertions_reset()
    }

    // MARK: - Exception type discrimination

    // assert(false) must throw AssertionError, NOT IllegalStateException
    func testAssertFalseThrowsAssertionErrorNotIllegalState() {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        XCTAssertNotEqual(thrown, 0)
        guard let box = throwableBox(from: thrown) else {
            XCTFail("Expected RuntimeThrowableBox"); return
        }
        XCTAssertEqual(box.exceptionFQName, "kotlin.AssertionError",
                       "assert(false) must throw AssertionError")
        XCTAssertFalse(box is RuntimeIllegalStateExceptionBox,
                       "assert must NOT throw IllegalStateException")
        XCTAssertFalse(box is RuntimeIllegalArgumentExceptionBox,
                       "assert must NOT throw IllegalArgumentException")
    }

    // require(false) must throw IllegalArgumentException, NOT AssertionError
    func testRequireFalseThrowsIllegalArgumentNotAssertionError() {
        var thrown = 0
        _ = kk_require(0, &thrown)
        XCTAssertNotEqual(thrown, 0)
        guard let box = throwableBox(from: thrown) else {
            XCTFail("Expected RuntimeThrowableBox"); return
        }
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException",
                       "require(false) must throw IllegalArgumentException")
        XCTAssertFalse(box is RuntimeAssertionErrorBox,
                       "require must NOT throw AssertionError")
        XCTAssertFalse(box is RuntimeIllegalStateExceptionBox,
                       "require must NOT throw IllegalStateException")
    }

    // check(false) must throw IllegalStateException, NOT AssertionError
    func testCheckFalseThrowsIllegalStateNotAssertionError() {
        var thrown = 0
        _ = kk_check(0, &thrown)
        XCTAssertNotEqual(thrown, 0)
        guard let box = throwableBox(from: thrown) else {
            XCTFail("Expected RuntimeThrowableBox"); return
        }
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalStateException",
                       "check(false) must throw IllegalStateException")
        XCTAssertFalse(box is RuntimeAssertionErrorBox,
                       "check must NOT throw AssertionError")
        XCTAssertFalse(box is RuntimeIllegalArgumentExceptionBox,
                       "check must NOT throw IllegalArgumentException")
    }

    // error() must throw IllegalStateException, NOT AssertionError or IllegalArgumentException
    func testErrorAlwaysThrowsIllegalStateException() {
        var thrown = 0
        let msgRaw = makeRuntimeString("boom")
        _ = kk_error(msgRaw, &thrown)
        XCTAssertNotEqual(thrown, 0)
        guard let box = throwableBox(from: thrown) else {
            XCTFail("Expected RuntimeThrowableBox"); return
        }
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalStateException",
                       "error() must always throw IllegalStateException")
        XCTAssertFalse(box is RuntimeAssertionErrorBox,
                       "error() must NOT throw AssertionError")
        XCTAssertFalse(box is RuntimeIllegalArgumentExceptionBox,
                       "error() must NOT throw IllegalArgumentException")
    }

    // MARK: - error() message propagation

    func testErrorMessageIsPreserved() throws {
        var thrown = 0
        let msgRaw = makeRuntimeString("fatal problem")
        _ = kk_error(msgRaw, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "fatal problem")
    }

    func testErrorWithNullSentinelMessageYieldsNullString() throws {
        var thrown = 0
        _ = kk_error(runtimeNullSentinelInt, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "null",
                       "error() with null sentinel message should produce \"null\"")
    }

    // MARK: - assert(true) does not throw

    func testAssertTrueNeverThrows() {
        var thrown = 0
        _ = kk_precondition_assert(1, &thrown)
        XCTAssertEqual(thrown, 0, "assert(true) must not throw")
    }

    // MARK: - require(true) / check(true) do not throw

    func testRequireTrueNeverThrows() {
        var thrown = 0
        _ = kk_require(1, &thrown)
        XCTAssertEqual(thrown, 0, "require(true) must not throw")
    }

    func testCheckTrueNeverThrows() {
        var thrown = 0
        _ = kk_check(1, &thrown)
        XCTAssertEqual(thrown, 0, "check(true) must not throw")
    }

    // MARK: - Lazy message NOT evaluated when condition is true

    func testRequireLazyMessageNotEvaluatedWhenTrue() {
        var thrown = 0
        _ = kk_require_lazy(1, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "require(true) { ... } must not throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 0,
                       "Lazy message lambda must NOT be evaluated when condition is true")
    }

    func testCheckLazyMessageNotEvaluatedWhenTrue() {
        var thrown = 0
        _ = kk_check_lazy(1, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "check(true) { ... } must not throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 0,
                       "Lazy message lambda must NOT be evaluated when condition is true")
    }

    func testAssertLazyMessageNotEvaluatedWhenTrue() {
        var thrown = 0
        _ = kk_precondition_assert_lazy(1, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "assert(true) { ... } must not throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 0,
                       "Lazy message lambda must NOT be evaluated when condition is true")
    }

    // MARK: - Lazy message evaluated exactly once when condition is false

    func testRequireLazyMessageEvaluatedOnceWhenFalse() {
        var thrown = 0
        _ = kk_require_lazy(0, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "require(false) { ... } must throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 1,
                       "Lazy message lambda must be evaluated exactly once when condition is false")
    }

    func testCheckLazyMessageEvaluatedOnceWhenFalse() {
        var thrown = 0
        _ = kk_check_lazy(0, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "check(false) { ... } must throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 1,
                       "Lazy message lambda must be evaluated exactly once when condition is false")
    }

    // MARK: - Lazy message toString behavior (null sentinel -> "null")

    func testRequireLazyNullSentinelMessageYieldsNull() throws {
        var thrown = 0
        _ = kk_require_lazy(0, fnPtrInt(lazyCountingThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "null",
                       "null sentinel from lazy lambda should produce message \"null\"")
    }

    func testCheckLazyNullSentinelMessageYieldsNull() throws {
        var thrown = 0
        _ = kk_check_lazy(0, fnPtrInt(lazyCountingThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "null",
                       "null sentinel from lazy lambda should produce message \"null\"")
    }

    // MARK: - Lazy message with string value is included in exception

    func testRequireLazyStringMessageIncludedInException() throws {
        var thrown = 0
        _ = kk_require_lazy(0, fnPtrInt(lazyStringThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "lazy-msg",
                       "Lazy string message must be included in IllegalArgumentException")
    }

    func testCheckLazyStringMessageIncludedInException() throws {
        var thrown = 0
        _ = kk_check_lazy(0, fnPtrInt(lazyStringThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "lazy-msg",
                       "Lazy string message must be included in IllegalStateException")
    }

    func testAssertLazyStringMessageIncludedInException() throws {
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyStringThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "lazy-msg",
                       "Lazy string message must be included in AssertionError")
    }

    // MARK: - message toString with Int box (Kotlin Any?.toString())

    func testErrorWithIntBoxMessageConvertsToString() throws {
        var thrown = 0
        let intBoxRaw = makeRuntimeIntBox(42)
        _ = kk_error(intBoxRaw, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "42",
                       "error() with Int box should convert to decimal string")
    }

    func testErrorWithBoolBoxTrueConvertsToString() throws {
        var thrown = 0
        let boolBoxRaw = makeRuntimeBoolBox(true)
        _ = kk_error(boolBoxRaw, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "true",
                       "error() with Bool(true) box should convert to \"true\"")
    }

    func testErrorWithBoolBoxFalseConvertsToString() throws {
        var thrown = 0
        let boolBoxRaw = makeRuntimeBoolBox(false)
        _ = kk_error(boolBoxRaw, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "false",
                       "error() with Bool(false) box should convert to \"false\"")
    }

    // MARK: - Default messages for no-arg variants

    func testRequireDefaultMessage() throws {
        var thrown = 0
        _ = kk_require(0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "Failed requirement.",
                       "require(false) default message must be \"Failed requirement.\"")
    }

    func testCheckDefaultMessage() throws {
        var thrown = 0
        _ = kk_check(0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "Check failed.",
                       "check(false) default message must be \"Check failed.\"")
    }

    func testAssertDefaultMessage() throws {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "Assertion failed.",
                       "assert(false) default message must be \"Assertion failed.\"")
    }

    // MARK: - Exception hierarchy for exception types

    func testAssertionErrorHierarchyContainsErrorAndThrowable() {
        let box = RuntimeAssertionErrorBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        // AssertionError extends Error (not Exception)
        XCTAssertTrue(hierarchy.contains("kotlin.Error"),
                      "AssertionError hierarchy must contain kotlin.Error")
        XCTAssertFalse(hierarchy.contains("kotlin.Exception"),
                       "AssertionError hierarchy must NOT contain kotlin.Exception")
        XCTAssertTrue(hierarchy.contains("kotlin.Throwable"),
                      "AssertionError hierarchy must contain kotlin.Throwable")
    }

    func testIllegalStateExceptionHierarchyContainsRuntimeExceptionAndException() {
        let box = RuntimeIllegalStateExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"),
                      "IllegalStateException hierarchy must contain kotlin.RuntimeException")
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"),
                      "IllegalStateException hierarchy must contain kotlin.Exception")
        XCTAssertFalse(hierarchy.contains("kotlin.Error"),
                       "IllegalStateException hierarchy must NOT contain kotlin.Error")
    }

    func testIllegalArgumentExceptionHierarchyContainsRuntimeExceptionAndException() {
        let box = RuntimeIllegalArgumentExceptionBox(message: "test")
        let hierarchy = box.exceptionHierarchyFQNames
        XCTAssertTrue(hierarchy.contains("kotlin.RuntimeException"),
                      "IllegalArgumentException hierarchy must contain kotlin.RuntimeException")
        XCTAssertTrue(hierarchy.contains("kotlin.Exception"),
                      "IllegalArgumentException hierarchy must contain kotlin.Exception")
        XCTAssertFalse(hierarchy.contains("kotlin.Error"),
                       "IllegalArgumentException hierarchy must NOT contain kotlin.Error")
    }

    // MARK: - Disabled assertions skip assert (already tested in RuntimeAssertTests, but confirm edge)

    func testAssertLazyNotEvaluatedWhenAssertionsDisabled() {
        _ = kk_assertions_set_enabled(0)
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "Disabled assert(false) { ... } must not throw")
        XCTAssertEqual(lazyNotInvoked_Counter, 0,
                       "Lazy message must NOT be evaluated when assertions are disabled")
    }

    // MARK: - error() outThrown is always set (condition-independent)

    func testErrorAlwaysSetsOutThrown() {
        // error() is unconditional — condition is irrelevant; it always throws.
        var thrown = 0
        _ = kk_error(runtimeNullSentinelInt, &thrown)
        XCTAssertNotEqual(thrown, 0,
                          "error() must always populate outThrown regardless of any other state")
    }

    // MARK: - Multiple sequential calls each produce independent exception objects

    func testSequentialRequireCallsProduceIndependentObjects() {
        var thrown1 = 0
        var thrown2 = 0
        _ = kk_require(0, &thrown1)
        _ = kk_require(0, &thrown2)
        XCTAssertNotEqual(thrown1, 0)
        XCTAssertNotEqual(thrown2, 0)
        XCTAssertNotEqual(thrown1, thrown2,
                          "Each require(false) call must produce a distinct exception object")
    }

    func testSequentialErrorCallsProduceIndependentObjects() {
        var thrown1 = 0
        var thrown2 = 0
        _ = kk_error(makeRuntimeString("err1"), &thrown1)
        _ = kk_error(makeRuntimeString("err2"), &thrown2)
        XCTAssertNotEqual(thrown1, thrown2,
                          "Each error() call must produce a distinct exception object")
        if let box1 = throwableBox(from: thrown1), let box2 = throwableBox(from: thrown2) {
            XCTAssertEqual(box1.message, "err1")
            XCTAssertEqual(box2.message, "err2")
        }
    }
}
