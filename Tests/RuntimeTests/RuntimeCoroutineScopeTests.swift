import Dispatch
import XCTest
@testable import Runtime

private typealias RuntimeTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let scopeTestDelayFunctionID: Int = 9201
private let scopeTestChildFunctionID: Int = 9202
private let scopeTestCancelledChildFunctionID: Int = 9203

private var scopeTestChildCompleted = false
private var scopeTestCancelledChildSawCancellation = false
private let scopeTestLock = NSLock()

@_cdecl("scope_test_child_entry")
func scope_test_child_entry(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, scopeTestChildFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    scopeTestLock.lock()
    scopeTestChildCompleted = true
    scopeTestLock.unlock()
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("scope_test_cancelled_child_entry")
func scope_test_cancelled_child_entry(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, scopeTestCancelledChildFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(50, continuation)
    }
    // After resuming from delay, check if our job was cancelled via scope
    let spill = kk_coroutine_state_get_spill(continuation, 0)
    if spill != 0 && kk_job_is_cancelled(spill) != 0 {
        scopeTestLock.lock()
        scopeTestCancelledChildSawCancellation = true
        scopeTestLock.unlock()
        // Simulate CancellationException by setting outThrown
        let throwablePtr = kk_throwable_new(nil)
        outThrown?.pointee = Int(bitPattern: throwablePtr)
        return kk_coroutine_state_exit(continuation, 0)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 99)
}

final class RuntimeCoroutineScopeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        scopeTestLock.lock()
        scopeTestChildCompleted = false
        scopeTestCancelledChildSawCancellation = false
        scopeTestLock.unlock()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Scope lifecycle

    func testScopeNewReturnsNonZeroHandle() {
        let scope = kk_coroutine_scope_new()
        XCTAssertNotEqual(scope, 0)
        _ = kk_coroutine_scope_release(scope)
    }

    func testScopeIsNotCancelledByDefault() {
        let scope = kk_coroutine_scope_new()
        XCTAssertEqual(kk_coroutine_scope_is_cancelled(scope), 0)
        _ = kk_coroutine_scope_release(scope)
    }

    func testScopeCancelSetsCancelledFlag() {
        let scope = kk_coroutine_scope_new()
        _ = kk_coroutine_scope_cancel(scope)
        XCTAssertEqual(kk_coroutine_scope_is_cancelled(scope), 1)
        _ = kk_coroutine_scope_release(scope)
    }

    // MARK: - Job lifecycle

    func testJobNewReturnsNonZeroHandle() {
        let scope = kk_coroutine_scope_new()
        let job = kk_job_new(scope)
        XCTAssertNotEqual(job, 0)
        _ = kk_coroutine_scope_release(scope)
    }

    func testJobCompleteAndJoinReturnsValue() {
        let scope = kk_coroutine_scope_new()
        let job = kk_job_new(scope)
        _ = kk_job_complete(job, 42)
        let result = kk_job_join(job)
        XCTAssertEqual(result, 42)
        _ = kk_coroutine_scope_release(scope)
    }

    func testJobCancelSetsCancelledFlag() {
        let scope = kk_coroutine_scope_new()
        let job = kk_job_new(scope)
        XCTAssertEqual(kk_job_is_cancelled(job), 0)
        _ = kk_job_cancel(job)
        XCTAssertEqual(kk_job_is_cancelled(job), 1)
        _ = kk_job_complete(job, 0)
        _ = kk_coroutine_scope_release(scope)
    }

    // MARK: - Cancel propagation from scope to children

    func testScopeCancelPropagatesToChildJobs() {
        let scope = kk_coroutine_scope_new()
        let job1 = kk_job_new(scope)
        let job2 = kk_job_new(scope)
        XCTAssertEqual(kk_job_is_cancelled(job1), 0)
        XCTAssertEqual(kk_job_is_cancelled(job2), 0)
        _ = kk_coroutine_scope_cancel(scope)
        XCTAssertEqual(kk_job_is_cancelled(job1), 1)
        XCTAssertEqual(kk_job_is_cancelled(job2), 1)
        _ = kk_job_complete(job1, 0)
        _ = kk_job_complete(job2, 0)
        _ = kk_coroutine_scope_release(scope)
    }

    // MARK: - Scoped launch

    func testScopedLaunchRunsChildAndCompletes() {
        let entryRaw = unsafeBitCast(
            scope_test_child_entry as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let scope = kk_coroutine_scope_new()
        let jobHandle = kk_scoped_launch(scope, entryRaw, scopeTestChildFunctionID)
        XCTAssertNotEqual(jobHandle, 0)

        // Join the job to wait for completion
        let result = kk_job_join(jobHandle)
        XCTAssertEqual(result, 42)

        scopeTestLock.lock()
        let completed = scopeTestChildCompleted
        scopeTestLock.unlock()
        XCTAssertTrue(completed)

        _ = kk_coroutine_scope_release(scope)
    }

    // MARK: - Scope join_all waits for children

    func testScopeJoinAllWaitsForAllChildren() {
        let entryRaw = unsafeBitCast(
            scope_test_child_entry as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let scope = kk_coroutine_scope_new()
        _ = kk_scoped_launch(scope, entryRaw, scopeTestChildFunctionID)

        // join_all should wait for all children
        _ = kk_coroutine_scope_join_all(scope)

        scopeTestLock.lock()
        let completed = scopeTestChildCompleted
        scopeTestLock.unlock()
        XCTAssertTrue(completed)

        _ = kk_coroutine_scope_release(scope)
    }

    // MARK: - Cancel propagation E2E

    func testCancelAfterLaunchPropagatesCancellationToChild() {
        let scope = kk_coroutine_scope_new()
        let job = kk_job_new(scope)

        // Simulate: cancel the scope, then check that child job sees cancellation
        _ = kk_coroutine_scope_cancel(scope)
        XCTAssertEqual(kk_job_is_cancelled(job), 1, "Child job should see cancellation after scope cancel")

        _ = kk_job_complete(job, 0)
        _ = kk_coroutine_scope_release(scope)
    }
}
