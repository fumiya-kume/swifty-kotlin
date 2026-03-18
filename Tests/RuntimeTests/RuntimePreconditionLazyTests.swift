@testable import Runtime
import XCTest

// STDLIB-257: Regression tests for precondition lazy message failure path distinction.
//
// When require(false) { ... } or check(false) { ... } is called and the lazy message
// lambda itself throws, the runtime must still report the precondition failure
// (IllegalArgumentException / IllegalStateException) as the primary exception, with
// the lambda's exception attached as the cause.

// A closure thunk that returns a string message successfully.
private let lazyMessageReturnsString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    // Allocate a runtime string "custom message"
    let message = "custom message"
    return message.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(message.utf8.count)))
        }
    }
}

// A closure thunk that throws an exception during evaluation.
private let lazyMessageThrows: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "LazyEvalError: lambda threw")
    return 0
}

/// Convert a @convention(c) function to an Int-sized raw pointer value,
/// using UnsafeRawPointer + Int(bitPattern:) for portability across ABIs.
private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

final class RuntimePreconditionLazyTests: IsolatedRuntimeXCTestCase {

    // MARK: - kk_require (non-lazy)

    func testRequirePassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_require(1, &outThrown)
        XCTAssertEqual(outThrown, 0, "require(true) should not throw")
    }

    func testRequireFailingConditionThrowsIllegalArgument() throws {
        var outThrown = 0
        _ = kk_require(0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "require(false) should throw")
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(box.message.contains("IllegalArgumentException"))
    }

    // MARK: - kk_check (non-lazy)

    func testCheckPassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_check(1, &outThrown)
        XCTAssertEqual(outThrown, 0, "check(true) should not throw")
    }

    func testCheckFailingConditionThrowsIllegalState() throws {
        var outThrown = 0
        _ = kk_check(0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "check(false) should throw")
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(box.message.contains("IllegalStateException"))
    }

    // MARK: - kk_require_lazy: condition passes

    func testRequireLazyPassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_require_lazy(1, fnPtrInt(lazyMessageReturnsString), 0, &outThrown)
        XCTAssertEqual(outThrown, 0, "require(true) { ... } should not throw")
    }

    // MARK: - kk_require_lazy: condition fails, lazy message succeeds

    func testRequireLazyFailsWithCustomMessage() throws {
        var outThrown = 0
        _ = kk_require_lazy(0, fnPtrInt(lazyMessageReturnsString), 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "require(false) { ... } should throw")
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(
            box.message.contains("custom message"),
            "Should contain the lazy message, got: \(box.message)"
        )
    }

    // MARK: - kk_require_lazy: condition fails, lazy message throws (STDLIB-257 core case)

    func testRequireLazyMessageThrowsReportsPreconditionFailureWithCause() throws {
        var outThrown = 0
        _ = kk_require_lazy(0, fnPtrInt(lazyMessageThrows), 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0, "Should throw when condition is false")

        // The primary exception must be the precondition failure, not the lambda's exception.
        let box = try XCTUnwrap(throwableBox(from: outThrown), "outThrown should be a RuntimeThrowableBox")
        XCTAssertTrue(
            box.message.contains("IllegalArgumentException"),
            "Primary exception must be IllegalArgumentException, got: \(box.message)"
        )

        // The lambda's exception must be attached as the cause.
        XCTAssertNotEqual(box.cause, 0, "cause must be set when lazy message threw")
        let causeBox = try XCTUnwrap(throwableBox(from: box.cause), "cause should be a RuntimeThrowableBox")
        XCTAssertTrue(
            causeBox.message.contains("LazyEvalError"),
            "cause should contain the lambda's exception message, got: \(causeBox.message)"
        )
    }

    // MARK: - kk_check_lazy: condition fails, lazy message throws (STDLIB-257 core case)

    func testCheckLazyMessageThrowsReportsPreconditionFailureWithCause() throws {
        var outThrown = 0
        _ = kk_check_lazy(0, fnPtrInt(lazyMessageThrows), 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0, "Should throw when condition is false")

        // The primary exception must be the precondition failure, not the lambda's exception.
        let box = try XCTUnwrap(throwableBox(from: outThrown), "outThrown should be a RuntimeThrowableBox")
        XCTAssertTrue(
            box.message.contains("IllegalStateException"),
            "Primary exception must be IllegalStateException, got: \(box.message)"
        )

        // The lambda's exception must be attached as the cause.
        XCTAssertNotEqual(box.cause, 0, "cause must be set when lazy message threw")
        let causeBox = try XCTUnwrap(throwableBox(from: box.cause), "cause should be a RuntimeThrowableBox")
        XCTAssertTrue(
            causeBox.message.contains("LazyEvalError"),
            "cause should contain the lambda's exception message, got: \(causeBox.message)"
        )
    }

    // MARK: - kk_require_lazy: no lambda provided (fnPtr == 0) falls back to default

    func testRequireLazyNoLambdaUsesDefaultMessage() throws {
        var outThrown = 0
        _ = kk_require_lazy(0, 0, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0)
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(
            box.message.contains("IllegalArgumentException"),
            "Should use default IllegalArgumentException message"
        )
        XCTAssertEqual(box.cause, 0, "No cause when lambda is absent")
    }

    // MARK: - kk_check_lazy: no lambda provided (fnPtr == 0) falls back to default

    func testCheckLazyNoLambdaUsesDefaultMessage() throws {
        var outThrown = 0
        _ = kk_check_lazy(0, 0, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0)
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(
            box.message.contains("IllegalStateException"),
            "Should use default IllegalStateException message"
        )
        XCTAssertEqual(box.cause, 0, "No cause when lambda is absent")
    }

    // MARK: - kk_check_lazy: condition passes with lazy message

    func testCheckLazyPassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_check_lazy(1, fnPtrInt(lazyMessageReturnsString), 0, &outThrown)
        XCTAssertEqual(outThrown, 0, "check(true) { ... } should not throw")
    }

    // MARK: - kk_check_lazy: condition fails, lazy message succeeds

    func testCheckLazyFailsWithCustomMessage() throws {
        var outThrown = 0
        _ = kk_check_lazy(0, fnPtrInt(lazyMessageReturnsString), 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "check(false) { ... } should throw")
        let box = try XCTUnwrap(throwableBox(from: outThrown))
        XCTAssertTrue(
            box.message.contains("custom message"),
            "Should contain the lazy message, got: \(box.message)"
        )
    }

    // MARK: - Helpers

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }
}
