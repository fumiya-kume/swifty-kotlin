import Dispatch
@testable import Runtime
import XCTest

// MARK: - STDLIB-CORO-BUG-01: Resume-once (one-shot) guard tests
//
// Kotlin spec requires that a Continuation may be resumed at most once.
// A second `resume` must throw `IllegalStateException("Already resumed, ...")`.
// These tests verify the guard fires correctly for both the success path
// (resume(with:)) and the exception path (resume(withException:)), and that
// concurrent callers on separate threads are correctly serialised.

final class RuntimeContinuationOneShotTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    /// Creates a fresh `RuntimeContinuationState` for testing without kicking
    /// off the full coroutine machinery.
    private func makeFreshState(functionID: Int64 = 9999) -> RuntimeContinuationState {
        RuntimeContinuationState(functionID: functionID)
    }

    /// Returns `true` if the raw `Int` pointer refers to a
    /// `RuntimeIllegalStateExceptionBox`.
    private func isIllegalStateException(_ raw: Int) -> Bool {
        guard raw != 0,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw)
        else { return false }
        return tryCast(ptr, to: RuntimeIllegalStateExceptionBox.self) != nil
    }

    // MARK: - Basic one-shot guard: success value

    /// First `resume(with:)` returns nil (no error).
    func testFirstResumeWithValueReturnsNil() {
        let state = makeFreshState()
        let result = state.resume(with: 42)
        XCTAssertNil(result, "First resume(with:) must succeed (return nil)")
    }

    /// Second `resume(with:)` returns an IllegalStateException.
    func testSecondResumeWithValueReturnsIllegalStateException() {
        let state = makeFreshState()
        _ = state.resume(with: 42)
        let doubleResumeEx = state.resume(with: 99)
        XCTAssertNotNil(doubleResumeEx, "Second resume(with:) must return IllegalStateException")
        XCTAssertTrue(
            isIllegalStateException(doubleResumeEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    /// The IllegalStateException message must contain "Already resumed".
    func testDoubleResumeWithValueExceptionMessage() {
        let state = makeFreshState()
        _ = state.resume(with: 7)
        let ex = state.resume(with: 13)!
        guard let ptr = UnsafeMutableRawPointer(bitPattern: ex),
              let box = tryCast(ptr, to: RuntimeIllegalStateExceptionBox.self)
        else {
            XCTFail("Exception is not an IllegalStateException box")
            return
        }
        XCTAssertTrue(
            box.message.contains("Already resumed"),
            "Exception message must contain 'Already resumed', got: \(box.message)"
        )
    }

    // MARK: - Basic one-shot guard: exception value

    /// First `resume(withException:)` returns nil (no error).
    func testFirstResumeWithExceptionReturnsNil() {
        let state = makeFreshState()
        let ex = runtimeAllocateThrowable(message: "boom")
        let result = state.resume(withException: ex)
        XCTAssertNil(result, "First resume(withException:) must succeed (return nil)")
    }

    /// Second `resume(withException:)` (after first success resume) returns ISE.
    func testSecondResumeWithExceptionAfterSuccessReturnsISE() {
        let state = makeFreshState()
        _ = state.resume(with: 1)
        let ex = runtimeAllocateThrowable(message: "boom2")
        let doubleEx = state.resume(withException: ex)
        XCTAssertNotNil(doubleEx, "Second resume(withException:) must return IllegalStateException")
        XCTAssertTrue(
            isIllegalStateException(doubleEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    /// Second `resume(withException:)` after first exception resume also returns ISE.
    func testSecondResumeWithExceptionAfterExceptionReturnsISE() {
        let state = makeFreshState()
        let ex1 = runtimeAllocateThrowable(message: "first exception")
        _ = state.resume(withException: ex1)
        let ex2 = runtimeAllocateThrowable(message: "second exception")
        let doubleEx = state.resume(withException: ex2)
        XCTAssertNotNil(doubleEx, "Second resume(withException:) must return IllegalStateException")
        XCTAssertTrue(
            isIllegalStateException(doubleEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    // MARK: - resetResumeState resets the guard

    /// After `resetResumeState()`, a fresh resume must succeed (no ISE).
    func testResetResumeStateAllowsSecondResumeToSucceed() {
        let state = makeFreshState()
        _ = state.resume(with: 1)
        // Simulate the coroutine loop advancing to the next suspend point
        state.resetResumeState()
        let result = state.resume(with: 2)
        XCTAssertNil(result, "resume(with:) after resetResumeState() must succeed")
    }

    // MARK: - deliverDoubleResumeException sets thrownException

    /// `deliverDoubleResumeException` must overwrite `thrownException` so that
    /// the coroutine body observes the violation when it next reads state.
    func testDeliverDoubleResumeExceptionSetsThrownException() {
        let state = makeFreshState()
        _ = state.resume(with: 42)
        // Simulate what the C-level entry points do on double-resume.
        let ise = runtimeAllocateIllegalStateException(
            message: "Already resumed, but proposed with update 99"
        )
        state.deliverDoubleResumeException(ise)
        XCTAssertEqual(
            state.thrownException, ise,
            "deliverDoubleResumeException must store the ISE in thrownException"
        )
        XCTAssertEqual(state.completion, 0, "completion must be reset to 0 on double-resume")
    }

    // MARK: - C-level entry-point guard (kk_coroutine_continuation_resume)

    /// Calling `kk_coroutine_continuation_resume` twice must not crash and must
    /// surface the IllegalStateException via `thrownException` on the second call.
    func testCLevelResumeGuardSurfacesIllegalStateExceptionViaThrownException() {
        let continuation = kk_coroutine_continuation_new(8001)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        guard let state = runtimeContinuationState(from: continuation) else {
            XCTFail("Could not retrieve RuntimeContinuationState for continuation")
            return
        }

        // First resume: should succeed silently.
        kk_coroutine_continuation_resume(continuation, 42)
        XCTAssertEqual(state.thrownException, 0, "thrownException must be 0 after first resume")

        // Second resume: must deliver ISE via thrownException.
        kk_coroutine_continuation_resume(continuation, 99)
        XCTAssertTrue(
            isIllegalStateException(state.thrownException),
            "thrownException must be IllegalStateException after double-resume via C-level API"
        )
    }

    /// Calling `kk_coroutine_continuation_resume_with_exception` twice must
    /// surface ISE via `thrownException`.
    func testCLevelResumeWithExceptionGuardSurfacesISE() {
        let continuation = kk_coroutine_continuation_new(8002)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        guard let state = runtimeContinuationState(from: continuation) else {
            XCTFail("Could not retrieve RuntimeContinuationState")
            return
        }

        let ex1 = runtimeAllocateThrowable(message: "first exception")
        kk_coroutine_continuation_resume_with_exception(continuation, ex1)
        XCTAssertEqual(state.thrownException, ex1, "First resume must store the original exception")

        let ex2 = runtimeAllocateThrowable(message: "second exception — double resume")
        kk_coroutine_continuation_resume_with_exception(continuation, ex2)
        XCTAssertTrue(
            isIllegalStateException(state.thrownException),
            "thrownException must be replaced with IllegalStateException after double resume-with-exception"
        )
    }

    // MARK: - Thread safety: concurrent double-resume

    /// Only one of two concurrent `resume(with:)` calls must succeed; the other
    /// must return an IllegalStateException.  This exercises the lock path.
    func testConcurrentDoubleResumeOnlyOneSucceeds() {
        let iterations = 200
        var successCount = 0
        var failureCount = 0
        let countLock = NSLock()

        for _ in 0..<iterations {
            let state = makeFreshState()
            // Use a class wrapper to allow mutation from concurrent closures
            // while keeping Sendable conformance. The NSLock below guards access.
            final class ResultsBox: @unchecked Sendable {
                var values: [Int?] = [nil, nil]
            }
            let resultsBox = ResultsBox()
            let group = DispatchGroup()

            for i in 0..<2 {
                group.enter()
                DispatchQueue.global().async {
                    let ex = state.resume(with: 1)
                    countLock.lock()
                    resultsBox.values[i] = ex
                    countLock.unlock()
                    group.leave()
                }
            }
            group.wait()

            let results = resultsBox.values
            let wins = results.filter { $0 == nil }.count
            let losses = results.filter { $0 != nil }.count
            countLock.lock()
            successCount += wins
            failureCount += losses
            countLock.unlock()
        }

        XCTAssertEqual(
            successCount, iterations,
            "Exactly one resume per pair must succeed across \(iterations) iterations"
        )
        XCTAssertEqual(
            failureCount, iterations,
            "Exactly one resume per pair must fail across \(iterations) iterations"
        )
    }
}
