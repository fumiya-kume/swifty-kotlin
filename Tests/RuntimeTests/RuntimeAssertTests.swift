@testable import Runtime
import XCTest

final class RuntimeAssertTests: IsolatedRuntimeXCTestCase {

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
}
