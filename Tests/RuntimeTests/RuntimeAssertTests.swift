@testable import Runtime
import XCTest

private let lazyMessageReturnsString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let message = "custom assert message"
    return message.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(message.utf8.count)))
        }
    }
}

private var assertLazyMessageEvaluations = 0

private let lazyMessageCountsEvaluation: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    assertLazyMessageEvaluations += 1
    return runtimeNullSentinelInt
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

final class RuntimeAssertTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        assertLazyMessageEvaluations = 0
        _ = kk_assertions_reset()
    }

    // MARK: - Eager assert

    func testAssertTrueDoesNotThrow() {
        var thrown = 0
        _ = kk_precondition_assert(1, &thrown)
        XCTAssertEqual(thrown, 0, "assert(true) should not throw")
    }

    func testAssertFalseThrows() {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        XCTAssertNotEqual(thrown, 0, "assert(false) should throw")
    }

    func testAssertFalseThrowsAssertionError() {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        XCTAssertNotEqual(thrown, 0)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            XCTFail("Expected a valid RuntimeThrowableBox")
            return
        }
        XCTAssertTrue(
            throwable.message.hasPrefix("AssertionError:"),
            "Expected message to start with 'AssertionError:', got: \(throwable.message)"
        )
        XCTAssertTrue(
            throwable.message.contains("Assertion failed"),
            "Expected message to contain 'Assertion failed', got: \(throwable.message)"
        )
    }

    // MARK: - Lazy assert (no lambda — fallback to default message)

    func testAssertLazyTrueDoesNotThrow() {
        var thrown = 0
        _ = kk_precondition_assert_lazy(1, 0, 0, &thrown)
        XCTAssertEqual(thrown, 0, "assert(true) { ... } should not throw when condition is true")
    }

    func testAssertLazyFalseNoLambdaThrowsDefaultMessage() {
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, 0, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "assert(false) with no lambda should throw")
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            XCTFail("Expected a valid RuntimeThrowableBox")
            return
        }
        XCTAssertTrue(
            throwable.message.hasPrefix("AssertionError:"),
            "Expected default message to start with 'AssertionError:', got: \(throwable.message)"
        )
    }

    func testAssertLazyFalseUsesAssertionErrorPrefixForCustomMessage() {
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyMessageReturnsString), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "assert(false) with lambda should throw")
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            XCTFail("Expected a valid RuntimeThrowableBox")
            return
        }
        XCTAssertEqual(throwable.message, "AssertionError: custom assert message")
    }

    func testAssertionsCanBeDisabledAtRuntime() {
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)

        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)

        XCTAssertEqual(thrown, 0, "disabled assert(false) should not throw")
    }

    func testDisabledAssertionsDoNotEvaluateLazyMessage() {
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)

        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyMessageCountsEvaluation), 0, &thrown)

        XCTAssertEqual(thrown, 0, "disabled assert(false) { ... } should not throw")
        XCTAssertEqual(assertLazyMessageEvaluations, 0, "lazy message must not be evaluated when assertions are disabled")
    }

    func testAssertionsCanBeReEnabledAtRuntime() {
        _ = kk_assertions_set_enabled(0)
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)

        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)

        XCTAssertNotEqual(thrown, 0, "re-enabled assert(false) should throw again")
    }
}
