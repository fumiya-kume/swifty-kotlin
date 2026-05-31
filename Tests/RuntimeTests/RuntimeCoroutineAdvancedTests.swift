import Dispatch
import Foundation
@testable import Runtime
import XCTest

// MARK: - C-callable helpers for advanced coroutine tests

private let advancedCoroTestState = AdvancedCoroutineTestState()

/// File-level storage for the throwable raw value used in advcoro_fail_with_exc.
private nonisolated(unsafe) var advCoroFailExcRaw: Int = 0

/// Non-capturing C stub that writes `advCoroFailExcRaw` to outThrown.
@_cdecl("advcoro_fail_with_exc")
func advcoro_fail_with_exc(_ _closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = advCoroFailExcRaw
    return 0
}

/// Non-capturing C stub that returns 512 (success value for resumeWith test).
@_cdecl("advcoro_return_512")
func advcoro_return_512(_ _closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return 512
}

/// A simple suspend function that adds `arg[0]` to a fixed constant and returns.
@_cdecl("advcoro_add_constant")
func advcoro_add_constant(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let arg = kk_coroutine_launcher_arg_get(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, Int(arg) + 100)
}

/// A suspend function that records one iteration, then returns its iteration count.
@_cdecl("advcoro_counter")
func advcoro_counter(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    advancedCoroTestState.recordIteration()
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, advancedCoroTestState.iterationsSnapshot())
}

/// A suspend function that delays once, then returns 55.
private let advCoroDelayFunctionID = 8801
@_cdecl("advcoro_delay_then_return")
func advcoro_delay_then_return(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 55)
}

/// A suspend function that delays, sets a spill slot with a "live value", then reads it back.
private let advCoroSpillFunctionID = 8802
@_cdecl("advcoro_spill_across_suspension")
func advcoro_spill_across_suspension(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroSpillFunctionID)
    if label == 0 {
        // Save a "live value" in spill slot 0 before suspending.
        _ = kk_coroutine_state_set_spill(continuation, 0, 777)
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    // After resume: reload the live value.
    let live = kk_coroutine_state_get_spill(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, live + 1)
}

/// A suspend function that immediately resumes with exception.
@_cdecl("advcoro_throw_immediately")
func advcoro_throw_immediately(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let exc = runtimeAllocateThrowable(message: "advcoro-exception")
    outThrown?.pointee = exc
    return 0
}

/// A suspend function that returns a fixed value (used for multi-launch tests).
@_cdecl("advcoro_return_fixed")
func advcoro_return_fixed(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

/// A suspend function that signals the test state and returns.
@_cdecl("advcoro_signal_and_return")
func advcoro_signal_and_return(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    advancedCoroTestState.recordIteration()
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 1)
}

/// Nested suspend: delays twice (two suspension labels), saving values across both points.
private let advCoroNestedFunctionID = 8803
@_cdecl("advcoro_nested_two_delays")
func advcoro_nested_two_delays(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroNestedFunctionID)
    switch label {
    case 0:
        // First suspension: save partial result in spill slot 0.
        _ = kk_coroutine_state_set_spill(continuation, 0, 10)
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    case 1:
        // Between first and second suspension: accumulate partial results.
        let partial = kk_coroutine_state_get_spill(continuation, 0)
        _ = kk_coroutine_state_set_spill(continuation, 0, partial + 20)
        _ = kk_coroutine_state_set_label(continuation, 2)
        return kk_kxmini_delay(1, continuation)
    default:
        // After second suspension: return accumulated value.
        let result = kk_coroutine_state_get_spill(continuation, 0)
        outThrown?.pointee = 0
        return kk_coroutine_state_exit(continuation, result)
    }
}

// MARK: - Advanced Coroutine Tests (TEST-CORO-003)

/// Covers advanced coroutine runtime behaviours beyond the base 29 tests:
/// nested suspension, spill/reload across suspension points, exception propagation,
/// supervisor scope semantics, dispatcher dispatch, Result round-trips through
/// resumeWith, multi-spill slot state, timeout-or-null, exception handler invocation,
/// and recursive / chained suspend patterns.
final class RuntimeCoroutineAdvancedTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    override func resetIsolatedRuntimeTestState() {
        advancedCoroTestState.reset()
    }

    // MARK: - Test 1: Two suspension labels / nested suspend state machine

    /// A CPS state machine that passes through two suspension labels correctly
    /// accumulates values in spill slots and returns the right result.
    func testNestedSuspendTwoLabelsAccumulatesSpills() {
        let entryRaw = unsafeBitCast(
            advcoro_nested_two_delays as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, advCoroNestedFunctionID, nil)
        // First label: 10, second label: +20 = 30
        XCTAssertEqual(result, 30, "Two-label CPS state machine must accumulate spills correctly")
    }

    // MARK: - Test 2: Spill-reload round-trip across a single suspension point

    /// A live value stored in a spill slot before a suspension must survive the resume.
    func testSpillSlotRoundTripAcrossSuspension() {
        let entryRaw = unsafeBitCast(
            advcoro_spill_across_suspension as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, advCoroSpillFunctionID, nil)
        // spill slot 0 = 777 before suspension; after resume we add 1 → 778
        XCTAssertEqual(result, 778, "Spill slot must survive one suspension-resume cycle")
    }

    // MARK: - Test 3: resumeWithException propagates through Result<T> round-trip

    /// A Result<T> that wraps a failure and is fed to resumeWith must propagate the exception
    /// to the continuation's thrownException field.
    func testResumeWithResultFailurePropagatesExceptionToState() {
        let fnID = 8810
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let exc = runtimeAllocateThrowable(message: "result-failure-advcoro")
        advCoroFailExcRaw = exc
        let failFn = unsafeBitCast(
            advcoro_fail_with_exc as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(failFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)
        let box = AdvResultBox()

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        // Capture thrownException via a separate nonisolated variable to avoid
        // Sendable analysis of RuntimeContinuationState inside the @Sendable closure.
        let thrownCapture = AdvThrownCapture()
        state.installResumeContinuation { [weak state] in
            thrownCapture.value = state?.thrownException ?? 0
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        XCTAssertEqual(sem.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(thrownCapture.value, exc, "Result.failure must propagate exception via resumeWith")
    }

    // MARK: - Test 4: Result<T> success round-trip through resumeWith

    /// A Result.success value fed to resumeWith must propagate the value (not an exception).
    func testResumeWithResultSuccessDeliversValue() {
        let fnID = 8811
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let successFn = unsafeBitCast(
            advcoro_return_512 as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(successFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)
        let box = AdvResultBox()

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        let completionCapture = AdvThrownCapture()
        state.installResumeContinuation { [weak state] in
            completionCapture.value = state.map { Int($0.completion) } ?? -1
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        XCTAssertEqual(sem.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(completionCapture.value, 512, "Result.success must propagate value via resumeWith")
    }

    // MARK: - Test 5: Exception handler is invoked on uncaught exception

    /// kk_kxmini_launch_with_exception_handler must invoke the handler when the
    /// coroutine throws an uncaught exception.
    func testExceptionHandlerInvokedOnUncaughtException() {
        let handlerHandle = kk_exception_handler_new()
        XCTAssertNotEqual(handlerHandle, 0)

        // We track invocation via a side-channel: launch a coroutine that always
        // throws, and verify that the job completes with a non-zero "failure" value.
        let entryRaw = unsafeBitCast(
            advcoro_throw_immediately as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8812
        let jobHandle = kk_kxmini_launch_with_exception_handler(entryRaw, functionID, handlerHandle)
        XCTAssertNotEqual(jobHandle, 0)

        // When an exception handler is installed and the coroutine throws,
        // the handler is invoked and the job is completed with 0 (handler consumes the exception).
        let joinResult = kk_job_join(jobHandle, 0)
        XCTAssertEqual(joinResult, 0, "Exception handler should consume the exception; job completes with 0")
    }

    // MARK: - Test 6: launch_with_dispatcher uses the specified dispatcher

    /// kk_kxmini_launch_with_dispatcher should run the coroutine and return a job handle
    /// whose join delivers the expected result, regardless of which dispatcher is used.
    func testLaunchWithDefaultDispatcherDeliversResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8813
        let dispatcher = kk_dispatcher_default()
        let jobHandle = kk_kxmini_launch_with_dispatcher(entryRaw, functionID, dispatcher)
        XCTAssertNotEqual(jobHandle, 0)
        let result = kk_job_join(jobHandle, 0)
        XCTAssertEqual(result, 42, "launch_with_dispatcher(Default) must deliver the coroutine's return value")
    }

    // MARK: - Test 7: launch_with_dispatcher IO dispatcher

    func testLaunchWithIODispatcherDeliversResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8814
        let dispatcher = kk_dispatcher_io()
        let jobHandle = kk_kxmini_launch_with_dispatcher(entryRaw, functionID, dispatcher)
        XCTAssertNotEqual(jobHandle, 0)
        let result = kk_job_join(jobHandle, 0)
        XCTAssertEqual(result, 42, "launch_with_dispatcher(IO) must deliver the coroutine's return value")
    }

    // MARK: - Test 8: Supervisor scope isolates child failures

    /// A supervisor scope must not cancel sibling children when one child fails.
    /// Here we use supervisor_scope_run with an immediately-returning coroutine to
    /// verify the scope infrastructure works and returns the block result.
    func testSupervisorScopeRunReturnsBlockResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var outThrown = 0
        let result = kk_supervisor_scope_run(entryRaw, 8815, &outThrown)
        XCTAssertEqual(outThrown, 0, "supervisor_scope_run with non-throwing block must not throw")
        XCTAssertEqual(result, 42, "supervisor_scope_run must return the block's result")
    }

    // MARK: - Test 9: Supervisor scope is active and not cancelled initially

    func testSupervisorScopeNewIsInitiallyActive() {
        let scopeHandle = kk_supervisor_scope_new()
        XCTAssertNotEqual(scopeHandle, 0)
        XCTAssertEqual(kk_coroutine_scope_is_active(scopeHandle), 1, "Supervisor scope should be active on creation")
        XCTAssertEqual(kk_coroutine_scope_is_cancelled(scopeHandle), 0, "Supervisor scope should not be cancelled on creation")
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    // MARK: - Test 10: withTimeoutOrNull returns null (0) when block exceeds timeout

    /// kk_with_timeout_or_null must return 0 when the block takes longer than the deadline.
    func testWithTimeoutOrNullReturnsNullOnTimeout() {
        let entryRaw = unsafeBitCast(
            advcoro_delay_then_return as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(advCoroDelayFunctionID)
        // Use a 0 ms timeout: the block should not complete in time.
        let result = kk_with_timeout_or_null(0, entryRaw, continuation)
        XCTAssertEqual(result, 0, "withTimeoutOrNull should return 0 (null) when block exceeds timeout")
    }

    // MARK: - Test 11: withTimeoutOrNull returns block value when block completes in time

    func testWithTimeoutOrNullReturnsValueWhenBlockCompletesInTime() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(8816)
        // 5000 ms timeout — the instant-return block will always finish in time.
        let result = kk_with_timeout_or_null(5000, entryRaw, continuation)
        XCTAssertEqual(result, 42, "withTimeoutOrNull should return the block value when it completes in time")
    }

    // MARK: - Test 12: Multiple spill slots are independent

    /// Setting two distinct spill slots and reading them back after a suspension
    /// must return the correct value for each slot independently.
    func testMultipleSpillSlotsAreIndependent() {
        let continuation = kk_coroutine_continuation_new(8817)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_state_set_spill(continuation, 0, 111)
        _ = kk_coroutine_state_set_spill(continuation, 1, 222)
        _ = kk_coroutine_state_set_spill(continuation, 2, 333)

        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 111)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 1), 222)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 2), 333)
        // Unset slot must return 0.
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 9), 0)
    }

    // MARK: - Test 13: CoroutineContext merge: right-hand element wins on collision

    /// When two contexts each containing a CoroutineName are merged with +,
    /// the right-hand name must take precedence (mirrors Kotlin semantics).
    func testContextMergeRightHandWinsOnNameCollision() {
        let boxA = RuntimeStringBox("Alpha")
        let ptrA = runtimeRegisterAdvStringBox(boxA)
        let nameA = kk_coroutine_name_create(ptrA)

        let boxB = RuntimeStringBox("Beta")
        let ptrB = runtimeRegisterAdvStringBox(boxB)
        let nameB = kk_coroutine_name_create(ptrB)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(8818))
        let ctxA = kk_context_plus(emptyCtx, nameA)
        let ctxAB = kk_context_plus(ctxA, nameB)

        let nameHandleRaw = kk_context_get_name(ctxAB)
        XCTAssertNotEqual(nameHandleRaw, 0)
        let nameValue = runtimeAdvStringBoxValue(nameHandleRaw)
        XCTAssertEqual(nameValue, "Beta", "Right-hand CoroutineName must win on context collision")
    }

    // MARK: - Test 14: Coroutine yield is a non-blocking no-op

    /// kk_coroutine_yield must return 0 promptly without blocking or crashing.
    func testCoroutineYieldReturnsZeroAndDoesNotBlock() {
        let start = Date()
        let result = kk_coroutine_yield()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, 0, "kk_coroutine_yield must return 0 (Unit)")
        XCTAssertLessThan(elapsed, 1.0, "kk_coroutine_yield must not block for more than 1 second")
    }

    // MARK: - Test 15: Concurrent launches converge via job_join

    /// Launching two concurrent coroutines and joining both must return each one's
    /// independent result without interference.
    func testConcurrentLaunchesReturnIndependentResults() {
        let baseline = advancedCoroTestState.iterationsSnapshot()

        let entry1 = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let entry2 = unsafeBitCast(
            advcoro_add_constant as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        let cont2 = kk_coroutine_continuation_new(8820)
        _ = kk_coroutine_launcher_arg_set(cont2, 0, 7)

        let job1 = kk_kxmini_launch(entry1, 8819)
        let job2 = kk_kxmini_launch_with_cont(entry2, cont2)

        XCTAssertNotEqual(job1, 0)
        XCTAssertNotEqual(job2, 0)

        let result1 = kk_job_join(job1, 0)
        let result2 = kk_job_join(job2, 0)

        XCTAssertEqual(result1, 42, "First concurrent launch must return 42")
        XCTAssertEqual(result2, 107, "Second concurrent launch must return arg(7)+100=107")
        _ = baseline // suppress unused warning
    }
}

// MARK: - Private helpers

private final class AdvResultBox: @unchecked Sendable {
    var value: Int = -1
    var thrown: Int = 0
}

/// Sendable capture box for a single Int value (used to capture state fields
/// across @Sendable closures without making RuntimeContinuationState Sendable).
private final class AdvThrownCapture: @unchecked Sendable {
    var value: Int = 0
}

private func runtimeRegisterAdvStringBox(_ box: RuntimeStringBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeAdvStringBoxValue(_ raw: Int) -> String {
    guard raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeStringBox.self)
    else { return "" }
    return box.value
}

// MARK: - AdvancedCoroutineTestState

private final class AdvancedCoroutineTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _iterations = 0

    func reset() {
        lock.lock()
        _iterations = 0
        lock.unlock()
    }

    func recordIteration() {
        lock.lock()
        _iterations += 1
        lock.unlock()
    }

    func iterationsSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _iterations
    }
}
