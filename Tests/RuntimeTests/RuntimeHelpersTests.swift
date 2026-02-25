import XCTest
@testable import Runtime

final class RuntimeHelpersTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Null sentinel constants

    func testNullSentinelInt64EqualsInt64Min() {
        XCTAssertEqual(runtimeNullSentinelInt64, Int64.min)
    }

    func testNullSentinelIntTruncatesFromInt64Min() {
        XCTAssertEqual(runtimeNullSentinelInt, Int(truncatingIfNeeded: Int64.min))
    }

    // MARK: - normalizeNullableRuntimePointer

    func testNormalizeNilPointerReturnsNil() {
        let result = normalizeNullableRuntimePointer(nil)
        XCTAssertNil(result)
    }

    func testNormalizeNullSentinelPointerReturnsNil() {
        guard let sentinelPtr = UnsafeMutableRawPointer(bitPattern: runtimeNullSentinelInt) else {
            // If null sentinel is 0 on this platform, skip.
            return
        }
        let result = normalizeNullableRuntimePointer(sentinelPtr)
        XCTAssertNil(result, "Null sentinel should be normalized to nil")
    }

    func testNormalizeValidPointerReturnsItself() {
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size, alignment: MemoryLayout<Int>.alignment)
        defer { ptr.deallocate() }
        ptr.storeBytes(of: 42, as: Int.self)
        let result = normalizeNullableRuntimePointer(ptr)
        XCTAssertEqual(result, ptr)
    }

    // MARK: - runtimeAllocateThrowable

    func testAllocateThrowableReturnsNonZeroHandle() {
        let handle = runtimeAllocateThrowable(message: "test error")
        XCTAssertNotEqual(handle, 0)
    }

    func testAllocateThrowableWithDifferentMessagesReturnsDifferentHandles() {
        let handle1 = runtimeAllocateThrowable(message: "error 1")
        let handle2 = runtimeAllocateThrowable(message: "error 2")
        XCTAssertNotEqual(handle1, handle2)
    }

    func testAllocateThrowableRegistersInObjectPointers() {
        let handle = runtimeAllocateThrowable(message: "registered")
        XCTAssertNotEqual(handle, 0)
        // Confirm the handle is a valid object pointer by attempting to cast it.
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            XCTFail("Expected non-nil raw pointer from handle")
            return
        }
        let box = tryCast(ptr, to: RuntimeThrowableBox.self)
        XCTAssertNotNil(box, "Handle should point to a RuntimeThrowableBox")
        XCTAssertEqual(box?.message, "registered")
    }

    // MARK: - tryCast

    func testTryCastSucceedsForMatchingType() {
        let box = RuntimeStringBox("test")
        let unmanaged = Unmanaged.passRetained(box)
        let ptr = UnsafeMutableRawPointer(unmanaged.toOpaque())
        defer { unmanaged.release() }

        let result = tryCast(ptr, to: RuntimeStringBox.self)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value, "test")
    }

    func testTryCastReturnsNilForWrongType() {
        let box = RuntimeIntBox(42)
        let unmanaged = Unmanaged.passRetained(box)
        let ptr = UnsafeMutableRawPointer(unmanaged.toOpaque())
        defer { unmanaged.release() }

        let result = tryCast(ptr, to: RuntimeStringBox.self)
        XCTAssertNil(result)
    }

    // MARK: - KKDispatchContinuation

    func testDispatchContinuationStoresContext() {
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size, alignment: MemoryLayout<Int>.alignment)
        defer { ptr.deallocate() }
        ptr.storeBytes(of: 99, as: Int.self)
        let continuation = KKDispatchContinuation(context: ptr) { _ in }
        XCTAssertEqual(continuation.context, ptr)
    }

    func testDispatchContinuationNilContext() {
        let continuation = KKDispatchContinuation(context: nil) { _ in }
        XCTAssertNil(continuation.context)
    }

    func testDispatchContinuationResumeInvokesCallback() {
        var called = false
        let continuation = KKDispatchContinuation(context: nil) { _ in
            called = true
        }
        continuation.resumeWith(nil)
        XCTAssertTrue(called)
    }

    func testDispatchContinuationResumePassesResultToCallback() {
        var receivedResult: UnsafeMutableRawPointer? = nil
        let continuation = KKDispatchContinuation(context: nil) { result in
            receivedResult = result
        }
        let resultPtr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size, alignment: MemoryLayout<Int>.alignment)
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 7, as: Int.self)
        continuation.resumeWith(resultPtr)
        XCTAssertEqual(receivedResult, resultPtr)
    }

    // MARK: - KxMiniRuntime.runBlocking

    func testRunBlockingBlocksUntilCallbackInvoked() {
        var executed = false
        KxMiniRuntime.runBlocking { done in
            executed = true
            done(nil)
        }
        XCTAssertTrue(executed)
    }

    func testRunBlockingCompletesWhenCallbackCalledAsync() {
        var count = 0
        KxMiniRuntime.runBlocking { done in
            DispatchQueue.global().async {
                count = 42
                done(nil)
            }
        }
        XCTAssertEqual(count, 42)
    }

    // MARK: - KxMiniRuntime.launch

    func testLaunchExecutesBlock() {
        let expectation = self.expectation(description: "launch block executed")
        KxMiniRuntime.launch {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    // MARK: - KxMiniRuntime.async

    func testAsyncReturnsKKContinuation() {
        let continuation = KxMiniRuntime.async { nil }
        XCTAssertNotNil(continuation)
    }

    // MARK: - KxMiniRuntime.delay

    func testDelayInvokesContinuationAfterDelay() {
        let expectation = self.expectation(description: "delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: 10, continuation: continuation)
        waitForExpectations(timeout: 3.0)
    }

    func testDelayWithZeroMilliseconds() {
        let expectation = self.expectation(description: "zero delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: 0, continuation: continuation)
        waitForExpectations(timeout: 3.0)
    }

    func testDelayWithNegativeMilliseconds() {
        let expectation = self.expectation(description: "negative delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: -5, continuation: continuation)
        waitForExpectations(timeout: 3.0)
    }
}
