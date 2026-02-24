import Dispatch
import XCTest
@testable import Runtime

private typealias RuntimeTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let runtimeKxMiniDelayFunctionID = 9101
private let runtimeKxMiniLaunchFunctionID = 9102
private let runtimeKxMiniAsyncFunctionID = 9103
private let runtimeKxMiniLaunchSignal = DispatchSemaphore(value: 0)

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

@_cdecl("runtime_test_suspend_with_arg")
func runtime_test_suspend_with_arg(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let arg = kk_coroutine_launcher_arg_get(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, Int(arg) + 10)
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
        // launch now returns a job handle (non-zero) for structured concurrency
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0)
        XCTAssertEqual(runtimeKxMiniLaunchSignal.wait(timeout: .now() + .seconds(1)), .success)
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

    func testLauncherArgSetAndGetRoundTrips() {
        let continuation = kk_coroutine_continuation_new(5000)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        XCTAssertEqual(kk_coroutine_launcher_arg_set(continuation, 0, 42), 42)
        XCTAssertEqual(kk_coroutine_launcher_arg_set(continuation, 1, 99), 99)
        XCTAssertEqual(kk_coroutine_launcher_arg_get(continuation, 0), 42)
        XCTAssertEqual(kk_coroutine_launcher_arg_get(continuation, 1), 99)
        XCTAssertEqual(kk_coroutine_launcher_arg_get(continuation, 2), 0)
    }

    func testLauncherArgsSurviveStateEnterReset() {
        let continuation = kk_coroutine_continuation_new(5001)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_launcher_arg_set(continuation, 0, 77)
        XCTAssertEqual(kk_coroutine_state_enter(continuation, 5001), 0)
        _ = kk_coroutine_state_enter(continuation, 9999)
        XCTAssertEqual(kk_coroutine_launcher_arg_get(continuation, 0), 77)
    }

    func testRunBlockingWithContPassesArgsThroughLauncherArgs() {
        let functionID = 5002
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 32)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_arg as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking_with_cont(entryRaw, continuation)
        XCTAssertEqual(result, 42)
    }

    func testLaunchWithContRunsAsynchronously() {
        let functionID = 5003
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 0)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // launch_with_cont now returns a job handle (non-zero) for structured concurrency
        let jobHandle = kk_kxmini_launch_with_cont(entryRaw, continuation)
        XCTAssertNotEqual(jobHandle, 0)
        XCTAssertEqual(runtimeKxMiniLaunchSignal.wait(timeout: .now() + .seconds(1)), .success)
    }

    func testAsyncWithContReturnsAwaitableResult() {
        let functionID = 5004
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 63)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_arg as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let handle = kk_kxmini_async_with_cont(entryRaw, continuation)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_kxmini_async_await(handle), 73)
    }

    func testRunBlockingWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5005)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 123)
        _ = kk_kxmini_run_blocking_with_cont(0, continuation)
    }

    func testLaunchWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5006)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 0)
        _ = kk_kxmini_launch_with_cont(0, continuation)
    }

    func testAsyncWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5007)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 1)
        _ = kk_kxmini_async_with_cont(0, continuation)
    }

    // MARK: - Structured Concurrency (P5-89)

    func testCoroutineScopeNewAndWaitLifecycle() {
        let scopeHandle = kk_coroutine_scope_new()
        XCTAssertNotEqual(scopeHandle, 0)
        // Scope with no children should complete immediately
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    func testCoroutineScopeWaitsForLaunchedChild() {
        let scopeHandle = kk_coroutine_scope_new()

        // Launch a child that delays and completes with value 7
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0)

        // Wait for the launched signal to confirm the child ran
        XCTAssertEqual(runtimeKxMiniLaunchSignal.wait(timeout: .now() + .seconds(2)), .success)

        // scope_wait should return after all children complete
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    func testCoroutineScopeRunExecutesBlockAndWaitsForChildren() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // kk_coroutine_scope_run creates scope, runs block, waits for children
        let result = kk_coroutine_scope_run(entryRaw, runtimeKxMiniDelayFunctionID)
        XCTAssertEqual(result, 42)
    }

    func testJobJoinWaitsForCompletion() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Launch outside a scope to get a job handle directly
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniAsyncFunctionID)
        XCTAssertNotEqual(jobHandle, 0)
        let result = kk_job_join(jobHandle)
        XCTAssertEqual(result, 73)
    }

    func testCoroutineScopeCancelPropagatesToChildren() {
        let scopeHandle = kk_coroutine_scope_new()

        // Launch a child that delays (will be cancelled before completing normally)
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        _ = kk_kxmini_launch(entryRaw, runtimeKxMiniDelayFunctionID)

        // Cancel the scope — should propagate to children
        XCTAssertEqual(kk_coroutine_scope_cancel(scopeHandle), 0)

        // Wait should complete (children are cancelled so they exit early)
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    func testCoroutineScopeRegisterChildManualRegistration() {
        let scopeHandle = kk_coroutine_scope_new()

        // Create an async task and manually register it
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Temporarily pop the scope to prevent auto-registration
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = nil

        let asyncHandle = kk_kxmini_async(entryRaw, runtimeKxMiniAsyncFunctionID)

        // Restore scope and manually register
        RuntimeCoroutineScope.current = savedScope
        _ = kk_coroutine_scope_register_child(scopeHandle, asyncHandle)

        // Wait for children — should wait for the manually-registered async task
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)

        // The async task should have completed
        XCTAssertEqual(kk_kxmini_async_await(asyncHandle), 73)
    }

    func testNestedCoroutineScopesRestoreParent() {
        let outerScope = kk_coroutine_scope_new()
        XCTAssertNotEqual(outerScope, 0)

        let innerScope = kk_coroutine_scope_new()
        XCTAssertNotEqual(innerScope, 0)

        // Inner scope wait should pop inner and restore outer as current
        XCTAssertEqual(kk_coroutine_scope_wait(innerScope), 0)

        // Outer scope wait should pop outer
        XCTAssertEqual(kk_coroutine_scope_wait(outerScope), 0)
    }
}
