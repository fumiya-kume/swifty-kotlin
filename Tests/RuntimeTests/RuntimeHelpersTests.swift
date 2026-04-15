import Dispatch
@testable import Runtime
import XCTest

final class RuntimeHelpersTests: IsolatedRuntimeXCTestCase {
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

    func testNormalizeNullSentinelPointerReturnsNil() throws {
        try XCTSkipIf(runtimeNullSentinelInt == 0, "Null sentinel is 0 on this platform")
        let sentinelPtr = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: runtimeNullSentinelInt))
        let result = normalizeNullableRuntimePointer(sentinelPtr)
        XCTAssertNil(result, "Null sentinel should be normalized to nil")
    }

    func testNormalizeValidPointerReturnsItself() {
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
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
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
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
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: nil) { result in
            receivedResult = result
        }
        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 7, as: Int.self)
        continuation.resumeWith(resultPtr)
        XCTAssertEqual(receivedResult, resultPtr)
    }

    func testContinuationInterceptedReturnsSelfWhenContextHasNoDispatcher() {
        let continuation = KKDispatchContinuation(context: nil) { _ in }
        let intercepted = continuation.intercepted()

        XCTAssertTrue(
            (intercepted as AnyObject) === (continuation as AnyObject),
            "Continuation without a dispatcher should not be wrapped"
        )
    }

    func testContinuationInterceptedDispatchesThroughDispatcherContext() async {
        let expectation = expectation(description: "intercepted continuation dispatched")
        let dispatcherContext = UnsafeMutableRawPointer(bitPattern: kk_dispatcher_default())
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: dispatcherContext) { result in
            receivedResult = result
            expectation.fulfill()
        }

        let intercepted = continuation.intercepted()

        XCTAssertFalse(
            (intercepted as AnyObject) === (continuation as AnyObject),
            "Continuation with a dispatcher should be wrapped"
        )

        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 123, as: Int.self)

        intercepted.resumeWith(resultPtr)
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedResult, resultPtr)
    }

    func testExplicitContinuationInterceptorBridgeDispatchesContinuation() async {
        let expectation = expectation(description: "explicit interceptor dispatched")
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }
        let continuationRaw = Int(bitPattern: Unmanaged.passUnretained(continuation as AnyObject).toOpaque())
        let interceptedRaw = kk_continuation_interceptor_intercept_continuation(kk_dispatcher_default(), continuationRaw)

        XCTAssertNotEqual(
            interceptedRaw,
            continuationRaw,
            "Explicit interceptor bridge should wrap the continuation when a dispatcher is available"
        )

        guard let interceptedPtr = UnsafeMutableRawPointer(bitPattern: interceptedRaw) else {
            XCTFail("Expected wrapped continuation pointer")
            return
        }
        let interceptedObject = Unmanaged<AnyObject>.fromOpaque(interceptedPtr).takeUnretainedValue()
        guard let intercepted = interceptedObject as? KKContinuation else {
            XCTFail("Expected wrapped object to be a KKContinuation")
            return
        }

        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 456, as: Int.self)

        intercepted.resumeWith(resultPtr)
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedResult, resultPtr)
    }

    // MARK: - KxMiniRuntime.runBlocking

    func testRunBlockingBlocksUntilCallbackInvoked() {
        let callbackInvoked = expectation(description: "runBlocking callback invoked")
        let runBlockingReturned = expectation(description: "runBlocking returned")

        DispatchQueue.global().async {
            KxMiniRuntime.runBlocking { done in
                callbackInvoked.fulfill()
                done(nil)
            }
            runBlockingReturned.fulfill()
        }

        wait(for: [callbackInvoked, runBlockingReturned], timeout: 2.0)
    }

    func testRunBlockingCompletesWhenCallbackCalledAsync() {
        let callbackInvoked = expectation(description: "async callback invoked")
        let runBlockingReturned = expectation(description: "runBlocking returned after async callback")
        final class CountBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func set(_ newValue: Int) {
                lock.lock()
                value = newValue
                lock.unlock()
            }

            func get() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }
        let count = CountBox()

        DispatchQueue.global().async {
            KxMiniRuntime.runBlocking { done in
                DispatchQueue.global().async(execute: DispatchWorkItem {
                    count.set(42)
                    callbackInvoked.fulfill()
                    done(nil)
                })
            }
            runBlockingReturned.fulfill()
        }

        wait(for: [callbackInvoked, runBlockingReturned], timeout: 2.0)
        XCTAssertEqual(count.get(), 42)
    }

    // MARK: - KxMiniRuntime.launch

    func testLaunchExecutesBlock() async {
        let expectation = expectation(description: "launch block executed")
        KxMiniRuntime.launch {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - KxMiniRuntime.async

    func testAsyncReturnsKKContinuation() {
        let continuation = KxMiniRuntime.async { nil }
        XCTAssertNotNil(continuation)
    }

    // MARK: - KxMiniRuntime.delay

    func testDelayInvokesContinuationAfterDelay() async {
        let expectation = expectation(description: "delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: 10, continuation: continuation)
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func testDelayWithZeroMilliseconds() async {
        let expectation = expectation(description: "zero delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: 0, continuation: continuation)
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func testDelayWithNegativeMilliseconds() async {
        let expectation = expectation(description: "negative delay continuation invoked")
        let continuation = KKDispatchContinuation(context: nil) { _ in
            expectation.fulfill()
        }
        KxMiniRuntime.delay(milliseconds: -5, continuation: continuation)
        await fulfillment(of: [expectation], timeout: 3.0)
    }
}
