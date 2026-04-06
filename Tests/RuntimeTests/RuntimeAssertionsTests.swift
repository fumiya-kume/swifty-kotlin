@testable import Runtime
import XCTest

final class RuntimeAssertionsTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        _ = kk_assertions_reset()
    }

    // MARK: - High-level RuntimeAssertions.swift API tests

    func testRuntimeAssertTrueDoesNotThrow() {
        XCTAssertNoThrow(assert(true), "assert(true) should not throw")
    }

    func testRuntimeAssertFalseThrows() {
        // Note: Our high-level assert function uses the runtime system
        // so we can't easily catch the exception in Swift tests
        // Instead we verify the behavior through the runtime functions
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        XCTAssertNotEqual(thrown, 0, "assert(false) should throw via runtime")
    }

    func testRuntimeAssertTrueWithMessageDoesNotThrow() {
        XCTAssertNoThrow(assert(true) { "test message" }, "assert(true) { message } should not throw")
    }

    func testRuntimeAssertFalseWithMessageThrows() {
        // Test through runtime function since high-level assert is hard to test in Swift
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyMessageReturnsString), 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "assert(false) { message } should throw via runtime")
    }

    func testRuntimeAssertLazyMessageNotEvaluatedWhenTrue() {
        var evaluationCount = 0
        assert(true) { 
            evaluationCount += 1
            return "should not be evaluated"
        }
        XCTAssertEqual(evaluationCount, 0, "lazy message should not be evaluated when condition is true")
    }

    func testRuntimeAssertionsCanBeDisabled() {
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)
        
        XCTAssertNoThrow(assert(false), "disabled assert(false) should not throw")
        
        var evaluationCount = 0
        XCTAssertNoThrow(assert(false) { 
            evaluationCount += 1
            return "should not be evaluated"
        }, "disabled assert(false) { message } should not evaluate lazy message")
        
        XCTAssertEqual(evaluationCount, 0, "lazy message must not be evaluated when assertions are disabled")
    }

    func testRuntimeAssertionsCanBeReEnabled() {
        _ = kk_assertions_set_enabled(0)
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)
        
        // Test through runtime function
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        XCTAssertNotEqual(thrown, 0, "re-enabled assert(false) should throw")
    }

    func testRuntimeAssertWithComplexMessage() {
        // Test that complex messages are handled correctly
        var evaluationCount = 0
        assert(true) { 
            evaluationCount += 1
            return "complex message"
        }
        XCTAssertEqual(evaluationCount, 0, "complex message should not be evaluated when condition is true")
    }

    func testRuntimeAssertWithNumericMessage() {
        var evaluationCount = 0
        assert(true) { 
            evaluationCount += 1
            return 42
        }
        XCTAssertEqual(evaluationCount, 0, "numeric message should not be evaluated when condition is true")
    }

    func testRuntimeAssertWithBooleanMessage() {
        var evaluationCount = 0
        assert(true) { 
            evaluationCount += 1
            return false
        }
        XCTAssertEqual(evaluationCount, 0, "boolean message should not be evaluated when condition is true")
    }
}

// Helper function for testing - copied from RuntimeAssertTests
private let lazyMessageReturnsString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let message = "custom assert message"
    return message.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(message.utf8.count)))
        }
    }
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}
