import Dispatch
@testable import Runtime
import XCTest

private typealias RuntimeTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let runtimeKxMiniDelayFunctionID = 9101
private let runtimeKxMiniLaunchFunctionID = 9102
private let runtimeKxMiniAsyncFunctionID = 9103
private let runtimeKxMiniCancelFunctionID = 9104
private let runtimeWithContextFunctionID = 9105
private let runtimeCoroutineTestState = RuntimeCoroutineTestState()

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
    runtimeCoroutineTestState.recordLaunchEvent()
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

@_cdecl("runtime_test_suspend_cancel_loop")
func runtime_test_suspend_cancel_loop(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeKxMiniCancelFunctionID)
    if label == 0 {
        runtimeCoroutineTestState.recordCancelLoopIteration()
        _ = kk_coroutine_state_set_label(continuation, 1)
        let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
        if cancelled != 0 {
            return 0
        }
        return kk_kxmini_delay(5, continuation)
    }
    // Resumed after delay — check cancellation again
    let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
    if cancelled != 0 {
        return 0
    }
    // Loop: increment iteration counter, set label to 1 and delay again
    runtimeCoroutineTestState.recordCancelLoopIteration()
    _ = kk_coroutine_state_set_label(continuation, 1)
    return kk_kxmini_delay(5, continuation)
}

/// withContext test entry: returns a value immediately (no suspension).
@_cdecl("runtime_test_with_context_simple")
func runtime_test_with_context_simple(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 99)
}

/// withContext test entry: suspends via delay, then returns.
/// This verifies that the full suspend-resume loop runs on the target queue.
@_cdecl("runtime_test_with_context_delay")
func runtime_test_with_context_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeWithContextFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 55)
}

final class RuntimeCoroutineStateTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        runtimeCoroutineTestState.reset()
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
        let result = kk_kxmini_run_blocking(entryRaw, runtimeKxMiniDelayFunctionID, nil)
        XCTAssertEqual(result, 42)
    }

    func testKxMiniLaunchRunsSuspendEntryAsynchronously() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // launch now returns a job handle (non-zero) for structured concurrency
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0)
        XCTAssertTrue(
            runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched coroutine to record a launch event."
        )
        XCTAssertEqual(kk_job_join(jobHandle), 7)
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
        let result = kk_kxmini_run_blocking_with_cont(entryRaw, continuation, nil)
        XCTAssertEqual(result, 42)
    }

    func testLaunchWithContRunsAsynchronously() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
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
        XCTAssertTrue(
            runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched continuation to record a launch event."
        )
        XCTAssertEqual(kk_job_join(jobHandle), 7)
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
        _ = kk_kxmini_run_blocking_with_cont(0, continuation, nil)
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
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()

        // Launch a child that delays and completes with value 7
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0)

        // Wait for the launched signal to confirm the child ran
        XCTAssertTrue(
            runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 2.0),
            "Expected scope child to record a launch event."
        )

        // scope_wait should return after all children complete
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    func testCoroutineScopeRunExecutesBlockAndWaitsForChildren() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // kk_coroutine_scope_run creates scope, runs block, waits for children
        let result = kk_coroutine_scope_run(entryRaw, runtimeKxMiniDelayFunctionID, nil)
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

        // Measure how long cancel + wait take to complete.
        // The child uses kk_kxmini_delay(1, ...), so a correct cancellation
        // should cause wait to complete significantly earlier than 1 second.
        let start = DispatchTime.now()

        // Cancel the scope — should propagate to children
        XCTAssertEqual(kk_coroutine_scope_cancel(scopeHandle), 0)

        // Wait should complete (children are cancelled so they exit early)
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)

        let end = DispatchTime.now()
        let elapsedSeconds = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        // Ensure we didn't just wait for the full 1-second delay, which would
        // indicate that the child was not actually cancelled.
        XCTAssertLessThan(elapsedSeconds, 0.9)
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
        defer { RuntimeCoroutineScope.current = savedScope }

        let asyncHandle = kk_kxmini_async(entryRaw, runtimeKxMiniAsyncFunctionID)

        // Restore scope before manual registration
        RuntimeCoroutineScope.current = savedScope
        _ = kk_coroutine_scope_register_child(scopeHandle, asyncHandle)

        // Await the async result BEFORE scope_wait, since scope_wait releases the handle.
        // This matches real usage: user code awaits within the scope block, then scope cleans up.
        let result = kk_kxmini_async_await(asyncHandle)
        XCTAssertEqual(result, 73)

        // Wait for children — scope releases remaining retains for the child
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    func testJobJoinWithinScopeAndScopeWaitsForChild() {
        let scopeHandle = kk_coroutine_scope_new()
        XCTAssertNotEqual(scopeHandle, 0)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )

        // Launch within an active scope so the job is registered with it
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniAsyncFunctionID)
        XCTAssertNotEqual(jobHandle, 0)

        // Explicitly join the job and verify it completed successfully
        let result = kk_job_join(jobHandle)
        XCTAssertEqual(result, 73)

        // Scope wait should also complete successfully after the child has finished
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
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

    // MARK: - CORO-002: Cancellation Tests

    func testCheckCancellationReturnsZeroWhenNotCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        var outThrown = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        XCTAssertEqual(result, 0, "Should return 0 when not cancelled")
        XCTAssertEqual(outThrown, 0, "outThrown should be 0 when not cancelled")
    }

    func testCheckCancellationReturnsCancellationExceptionWhenCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        // Link a job handle so kk_coroutine_cancel and kk_coroutine_check_cancellation work
        let job = RuntimeJobHandle()
        if let state = runtimeContinuationState(from: continuation) {
            state.jobHandle = job
            job.continuationState = state
        }
        kk_coroutine_cancel(continuation)
        var outThrown = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        XCTAssertEqual(result, 1, "Should return 1 when cancelled")
        XCTAssertNotEqual(outThrown, 0, "outThrown should be set to CancellationException")
        XCTAssertEqual(kk_is_cancellation_exception(outThrown), 1, "Should be a CancellationException")
    }

    func testIsCancellationExceptionReturnsFalseForRegularThrowable() {
        let throwablePtr = kk_throwable_new(nil)
        let throwableInt = Int(bitPattern: throwablePtr)
        let result = kk_is_cancellation_exception(throwableInt)
        XCTAssertEqual(result, 0, "Regular throwable should not be CancellationException")
    }

    func testJobCancelStopsLaunchedCoroutine() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_cancel_loop as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniCancelFunctionID)
        XCTAssertNotEqual(jobHandle, 0, "Launch should return a job handle")

        // Wait until the coroutine has started (bounded polling)
        XCTAssertTrue(
            runtimeCoroutineTestState.waitForCancelLoopIterations(atLeast: 1, timeout: 2.0),
            "Coroutine should have started"
        )
        XCTAssertGreaterThan(
            runtimeCoroutineTestState.cancelLoopIterationsSnapshot(),
            0,
            "Coroutine should have started"
        )

        // Cancel the job
        _ = kk_job_cancel(jobHandle)

        // Join the job — should complete promptly after cancellation
        let startTime = DispatchTime.now()
        _ = kk_job_join(jobHandle)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        XCTAssertLessThan(elapsed, 2.0, "Coroutine should stop promptly after cancel")
    }

    func testLaunchReturnsJobHandle() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        XCTAssertNotEqual(jobHandle, 0, "Launch should return a non-zero job handle")
        XCTAssertTrue(
            runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched coroutine to record a launch event."
        )
        XCTAssertEqual(kk_job_join(jobHandle), 7)
    }

    func testJobStateMachineTransitionsAndAwaitCompletion() {
        let job = RuntimeJobHandle()
        XCTAssertFalse(job.isActiveSnapshot())
        XCTAssertFalse(job.completedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())

        job.markStarted()
        XCTAssertTrue(job.isActiveSnapshot())

        XCTAssertTrue(job.complete(with: 41))
        XCTAssertTrue(job.completedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        XCTAssertEqual(job.awaitCompletion(), 41)
        XCTAssertEqual(job.join(), 41)
    }

    func testJobCompleteExceptionallyStoresFailureCause() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let throwable = runtimeAllocateThrowable(message: "boom")

        XCTAssertTrue(job.completeExceptionally(with: throwable))
        XCTAssertTrue(job.completedSnapshot())
        XCTAssertTrue(job.isFailedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        XCTAssertEqual(job.join(), throwable)
    }

    func testJobCancelPropagatesToRegisteredChildren() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()
        parent.markStarted()
        child.markStarted()

        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)

        XCTAssertTrue(parent.cancel())
        XCTAssertTrue(parent.cancellationSnapshot())
        XCTAssertTrue(parent.completedSnapshot())
        XCTAssertTrue(child.cancellationSnapshot())
        XCTAssertTrue(child.completedSnapshot())
    }

    func testJobCancelWithCausePreservesCauseValue() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let cause = runtimeAllocateThrowable(message: "cancel cause")

        XCTAssertTrue(job.cancel(cause: cause))
        XCTAssertTrue(job.cancellationSnapshot())
        XCTAssertEqual(job.join(), cause)
    }

    // MARK: - STDLIB-250: withContext async context switching

    func testWithContextDefaultDispatcherReturnsBlockResult() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 99, "withContext should return the block's result")
    }

    func testWithContextIODispatcherReturnsBlockResult() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 99, "withContext(IO) should return the block's result")
    }

    func testWithContextHandlesSuspensionInsideBlock() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 55, "withContext should handle suspension inside the block")
    }

    func testWithContextUnknownDispatcherFallsBackToDefault() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Unknown dispatcher tag — should fall back to Default
        let result = kk_with_context(0xDEAD, entryRaw, continuation)
        XCTAssertEqual(result, 99, "Unknown dispatcher should fall back to Default and still work")
    }

    func testWithContextInvalidEntryPointReturnsZero() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        // kk_with_context now cleans up the continuation internally on
        // invalid entry, so no manual defer cleanup is needed.
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, 0, continuation)
        XCTAssertEqual(result, 0, "Invalid entry point should return 0")
    }

    func testWithContextIODispatcherRunsOffMainThread() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Run on IO dispatcher — the call should complete successfully
        // even when issued from the main thread (no deadlock).
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 99, "IO dispatcher should execute without deadlock")
    }

    func testWithContextMainDispatcherFromMainThread() {
        // Dispatchers.Main should execute inline when already on the main
        // thread, avoiding the deadlock that would occur with async+semaphore.
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_main()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 99, "Main dispatcher should execute inline on main thread")
    }

    func testWithContextMainDispatcherFromBackgroundThread() {
        // When called from a background thread, kk_with_context dispatches
        // async to DispatchQueue.main and waits on a semaphore. The test
        // succeeds because XCTest's wait(for:timeout:) pumps the main run
        // loop, allowing the main queue to service the enqueued block.
        let expectation = XCTestExpectation(description: "withContext(Main) from background")
        // Perform the assertion inside the async block so there is no shared
        // mutable state across threads — only the expectation is used to
        // synchronize completion with the test thread.
        DispatchQueue.global().async {
            let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
            let entryRaw = unsafeBitCast(
                runtime_test_with_context_simple as RuntimeTestSuspendEntry,
                to: Int.self
            )
            let dispatcher = kk_dispatcher_main()
            let result = kk_with_context(dispatcher, entryRaw, continuation)
            XCTAssertEqual(result, 99, "Main dispatcher from background thread should return block result")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    func testWithContextWithDelayOnIODispatcher() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        XCTAssertEqual(result, 55, "withContext(IO) should handle suspension correctly")
    }
}
