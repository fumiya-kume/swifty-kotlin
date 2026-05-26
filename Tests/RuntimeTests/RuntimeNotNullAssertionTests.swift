@testable import Runtime
import XCTest

// STDLIB-ASSERT-ABI-001: Runtime entry points for checkNotNull / requireNotNull.
//
// Covers:
//  - kk_check_not_null: non-null passthrough, null throws IllegalStateException
//  - kk_require_not_null: non-null passthrough, null throws IllegalArgumentException
//  - kk_check_not_null_lazy: lazy message evaluated only on null
//  - kk_require_not_null_lazy: lazy message evaluated only on null
//  - Default message "Required value was null." for both variants
//  - Exception type discrimination (IllegalState vs IllegalArgument)

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func makeRuntimeString(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
        }
    }
}

private func makeNonNullValue() -> Int {
    // Allocate a simple string to use as a non-null opaque pointer value
    makeRuntimeString("hello")
}

// Lazy thunk counter for "not evaluated" tests
private let notNullLazyLock = NSLock()
nonisolated(unsafe) private var _notNullLazyCounter = 0
private var notNullLazyCounter: Int {
    get { notNullLazyLock.lock(); defer { notNullLazyLock.unlock() }; return _notNullLazyCounter }
    set { notNullLazyLock.lock(); defer { notNullLazyLock.unlock() }; _notNullLazyCounter = newValue }
}

private let notNullCountingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    notNullLazyCounter += 1
    return runtimeNullSentinelInt
}

private let notNullStringThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let msg = "custom-null-msg"
    return msg.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: msg.utf8.count) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(msg.utf8.count)))
        }
    }
}

final class RuntimeNotNullAssertionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        notNullLazyCounter = 0
    }

    // MARK: - kk_check_not_null: non-null passthrough

    func testCheckNotNullPassthroughNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_check_not_null(value, &thrown)
        XCTAssertEqual(thrown, 0, "checkNotNull(nonNull) must not throw")
        XCTAssertEqual(result, value, "checkNotNull(nonNull) must return the value unchanged")
    }

    // MARK: - kk_check_not_null: null throws IllegalStateException

    func testCheckNotNullThrowsIllegalStateOnNull() throws {
        var thrown = 0
        _ = kk_check_not_null(runtimeNullSentinelInt, &thrown)
        XCTAssertNotEqual(thrown, 0, "checkNotNull(null) must throw")
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalStateException",
                       "checkNotNull must throw IllegalStateException on null")
        XCTAssertFalse(box is RuntimeIllegalArgumentExceptionBox,
                       "checkNotNull must NOT throw IllegalArgumentException")
    }

    func testCheckNotNullDefaultMessage() throws {
        var thrown = 0
        _ = kk_check_not_null(runtimeNullSentinelInt, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "Required value was null.",
                       "checkNotNull default message must be \"Required value was null.\"")
    }

    // MARK: - kk_require_not_null: non-null passthrough

    func testRequireNotNullPassthroughNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_require_not_null(value, &thrown)
        XCTAssertEqual(thrown, 0, "requireNotNull(nonNull) must not throw")
        XCTAssertEqual(result, value, "requireNotNull(nonNull) must return the value unchanged")
    }

    // MARK: - kk_require_not_null: null throws IllegalArgumentException

    func testRequireNotNullThrowsIllegalArgumentOnNull() throws {
        var thrown = 0
        _ = kk_require_not_null(runtimeNullSentinelInt, &thrown)
        XCTAssertNotEqual(thrown, 0, "requireNotNull(null) must throw")
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException",
                       "requireNotNull must throw IllegalArgumentException on null")
        XCTAssertFalse(box is RuntimeIllegalStateExceptionBox,
                       "requireNotNull must NOT throw IllegalStateException")
    }

    func testRequireNotNullDefaultMessage() throws {
        var thrown = 0
        _ = kk_require_not_null(runtimeNullSentinelInt, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "Required value was null.",
                       "requireNotNull default message must be \"Required value was null.\"")
    }

    // MARK: - Lazy variants: message NOT evaluated when non-null

    func testCheckNotNullLazyNotEvaluatedWhenNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_check_not_null_lazy(value, fnPtrInt(notNullCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "checkNotNull(nonNull) { ... } must not throw")
        XCTAssertEqual(result, value, "checkNotNull(nonNull) must return the value unchanged")
        XCTAssertEqual(notNullLazyCounter, 0,
                       "Lazy message lambda must NOT be evaluated when value is non-null")
    }

    func testRequireNotNullLazyNotEvaluatedWhenNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_require_not_null_lazy(value, fnPtrInt(notNullCountingThunk), 0, &thrown)
        XCTAssertEqual(thrown, 0, "requireNotNull(nonNull) { ... } must not throw")
        XCTAssertEqual(result, value, "requireNotNull(nonNull) must return the value unchanged")
        XCTAssertEqual(notNullLazyCounter, 0,
                       "Lazy message lambda must NOT be evaluated when value is non-null")
    }

    // MARK: - Lazy variants: message evaluated on null

    func testCheckNotNullLazyEvaluatedOnNull() {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "checkNotNull(null) { ... } must throw")
        XCTAssertEqual(notNullLazyCounter, 1,
                       "Lazy message lambda must be evaluated exactly once when value is null")
    }

    func testRequireNotNullLazyEvaluatedOnNull() {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "requireNotNull(null) { ... } must throw")
        XCTAssertEqual(notNullLazyCounter, 1,
                       "Lazy message lambda must be evaluated exactly once when value is null")
    }

    // MARK: - Lazy variants: custom string message included in exception

    func testCheckNotNullLazyStringMessageIncluded() throws {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullStringThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "custom-null-msg",
                       "checkNotNull lazy message must be included in IllegalStateException")
    }

    func testRequireNotNullLazyStringMessageIncluded() throws {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullStringThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.message, "custom-null-msg",
                       "requireNotNull lazy message must be included in IllegalArgumentException")
    }

    // MARK: - Exception type discrimination for lazy variants

    func testCheckNotNullLazyThrowsIllegalStateException() throws {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalStateException")
        XCTAssertFalse(box is RuntimeIllegalArgumentExceptionBox)
    }

    func testRequireNotNullLazyThrowsIllegalArgumentException() throws {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException")
        XCTAssertFalse(box is RuntimeIllegalStateExceptionBox)
    }
}
