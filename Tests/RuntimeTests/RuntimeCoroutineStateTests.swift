import Dispatch
import XCTest
@testable import Runtime

private typealias RuntimeTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let runtimeKxMiniDelayFunctionID = 9101
private let runtimeKxMiniLaunchFunctionID = 9102
private let runtimeKxMiniAsyncFunctionID = 9103
private let runtimeKxMiniCancelFunctionID = 9104
private let runtimeKxMiniLaunchSignal = DispatchSemaphore(value: 0)
private let runtimeCancelLoopIterations = Atomic<Int>(0)
private let runtimeCancelLoopStopped = DispatchSemaphore(value: 0)

private final class Atomic<T> {
    private var _value: T
    private let lock = NSLock()
    init(_ value: T) { self._value = value }
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: T) {
        lock.lock()
        _value = newValue
        lock.unlock()
    }
    func increment() where T == Int {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

@_cdecl("runtime_test_suspend_with_delay")
func runtime_test_suspend_with_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeKxMiniDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("runtime_test_suspend_launch")
func runtime_test_suspend_launch(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    runtimeKxMiniLaunchSignal.signal()
    return kk_coroutine_state_exit(continuation, 7)
}

@_cdecl("runtime_test_suspend_async")
func runtime_test_suspend_async(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 73)
}

@_cdecl("runtime_test_suspend_cancel_loop")
func runtime_test_suspend_cancel_loop(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeKxMiniCancelFunctionID)
    if label == 0 {
        runtimeCancelLoopIterations.increment()
        _ = kk_coroutine_state_set_label(continuation, 1)
        let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
        if cancelled != 0 {
            runtimeCancelLoopStopped.signal()
            return 0
        }
        return kk_kxmini_delay(5, continuation)
    }
    // Resumed after delay — check cancellation again
    let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
    if cancelled != 0 {
        runtimeCancelLoopStopped.signal()
        return 0
    }
    // Loop: reset label to 0 and delay again
    runtimeCancelLoopIterations.increment()
    _ = kk_coroutine_state_set_label(continuation, 1)
    return kk_kxmini_delay(5, continuation)
}

final class RuntimeCoroutineStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testContinuationStoresAndLoadsSpillSlotsAndCompletion() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        XCTAssertEqual(kk_coroutine_state_enter(continuation, 42), 0)

        XCTAssertEqual(kk_coroutine_state_set_spill(continuation, 0, 111), 111)
        XCTAssertEqual(kk_coroutine_state_set_spill(continuation, 2, 333), 333)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 111)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 1), 0)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 2), 333)

        XCTAssertEqual(kk_coroutine_state_set_completion(continuation, 777), 777)
        XCTAssertEqual(kk_coroutine_state_get_completion(continuation), 777)
    }

    func testStateEnterResetsCompletionAndSpillsWhenFunctionChanges() {
        let continuation = kk_coroutine_continuation_new(7)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_state_set_label(continuation, 5)
        _ = kk_coroutine_state_set_spill(continuation, 0, 91)
        _ = kk_coroutine_state_set_completion(continuation, 123)

        XCTAssertEqual(kk_coroutine_state_enter(continuation, 7), 5)
        XCTAssertEqual(kk_coroutine_state_enter(continuation, 8), 0)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 0)
        XCTAssertEqual(kk_coroutine_state_get_completion(continuation), 0)
    }

    func testKxMiniRunBlockingResumesDelayedSuspendEntry() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, runtimeKxMiniDelayFunctionID)
        XCTAssertEqual(result, 42)
    }

    func testKxMiniLaunchRunsSuspendEntryAsynchronously() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        // Job handle is now returned (non-zero means job handle allocated)
        XCTAssertEqual(runtimeKxMiniLaunchSignal.wait(timeout: .now() + .seconds(1)), .success)
        // Clean up: cancel the job handle if it was returned
        if jobHandle != 0 {
            kk_job_cancel(jobHandle)
        }
    }

    func testKxMiniAsyncReturnsAwaitableHandle() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let handle = kk_kxmini_async(entryRaw, runtimeKxMiniAsyncFunctionID)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_kxmini_async_await(handle), 73)
    }

    // CORO-002: Cancellation tests

    func testCheckCancellationReturnsZeroWhenNotCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        var outThrown: Int = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        XCTAssertEqual(result, 0, "Should return 0 when not cancelled")
        XCTAssertEqual(outThrown, 0, "outThrown should be 0 when not cancelled")
    }

    func testCheckCancellationReturnsCancellationExceptionWhenCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        kk_coroutine_cancel(continuation)
        var outThrown: Int = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        XCTAssertEqual(result, 1, "Should return 1 when cancelled")
        XCTAssertNotEqual(outThrown, 0, "outThrown should be set to CancellationException")
        XCTAssertEqual(kk_is_cancellation_exception(outThrown), 1, "Should be a CancellationException")
    }

    func testJobCancelStopsLaunchedCoroutine() {
        runtimeCancelLoopIterations.set(0)
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_cancel_loop as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniCancelFunctionID)
        XCTAssertNotEqual(jobHandle, 0, "Launch should return a job handle")

        // Wait briefly for the coroutine to start
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel the job
        kk_job_cancel(jobHandle)

        // Wait for the coroutine to stop
        let stopResult = runtimeCancelLoopStopped.wait(timeout: .now() + .seconds(2))
        XCTAssertEqual(stopResult, .success, "Coroutine should stop after cancel")
    }

    func testLaunchReturnsJobHandle() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0, "Launch should return a non-zero job handle")
        XCTAssertEqual(runtimeKxMiniLaunchSignal.wait(timeout: .now() + .seconds(1)), .success)
    }
}
