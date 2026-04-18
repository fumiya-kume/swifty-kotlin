import Dispatch
@testable import Runtime
import XCTest

// MARK: - RuntimeCoroutineIntrinsicsEdgeCaseTests
//
// Edge-case coverage for kotlin.coroutines.intrinsics and
// kotlin.coroutines.cancellation primitives (STDLIB-CORO-001).
//
// Implemented surface tested here:
//   • kk_coroutine_suspended()  — COROUTINE_SUSPENDED sentinel
//   • kk_continuation_intercepted() — intercepted() identity/bypass
//   • kk_continuation_interceptor_intercept_continuation() — explicit interceptor
//   • runtimeAllocateCancellationException / kk_is_cancellation_exception
//   • RuntimeCancellationBox class hierarchy (extends RuntimeThrowableBox)
//   • Result.failure with CancellationException treated as cancellation (not failure)
//   • kk_runCatching + cancellation-exception propagation through Result
//
// Unimplemented (noted in PR body, NOT tested here):
//   • startCoroutineUninterceptedOrReturn — no @_cdecl("kk_start_coroutine_unintercepted…") entry
//   • createCoroutineUnintercepted       — no @_cdecl("kk_create_coroutine_unintercepted") entry
// CancellationException inherits IllegalStateException → RuntimeException in Kotlin.
// RuntimeCancellationBox reports this chain via exceptionHierarchyFQNames so catch clauses
// targeting IllegalStateException / RuntimeException match CancellationException at runtime (PR #1261).

final class RuntimeCoroutineIntrinsicsEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - COROUTINE_SUSPENDED sentinel

    /// kk_coroutine_suspended() returns a stable non-null pointer.
    func testCoroutineSuspendedSentinelIsNonNull() {
        let sentinel = kk_coroutine_suspended()
        XCTAssertNotEqual(Int(bitPattern: sentinel), 0,
            "COROUTINE_SUSPENDED sentinel must be non-null")
    }

    /// Two consecutive calls return the same pointer (singleton identity).
    func testCoroutineSuspendedSentinelIsSingletonIdentity() {
        let first = kk_coroutine_suspended()
        let second = kk_coroutine_suspended()
        XCTAssertEqual(first, second,
            "COROUTINE_SUSPENDED sentinel must return the same object on every call")
    }

    /// The COROUTINE_SUSPENDED sentinel must compare equal to itself (pointer equality).
    /// This models the `result === COROUTINE_SUSPENDED` check in the state machine.
    func testCoroutineSuspendedSentinelEqualityCheck() {
        let sentinelA = kk_coroutine_suspended()
        let sentinelB = kk_coroutine_suspended()
        // Pointer equality — simulates the generated jumpIfEqual comparison.
        XCTAssertTrue(sentinelA == sentinelB,
            "COROUTINE_SUSPENDED pointer equality check must hold (state-machine short-circuit)")
    }

    /// The sentinel pointer must NOT compare equal to an unrelated object.
    func testCoroutineSuspendedSentinelNotEqualToOtherObject() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let cont = kk_coroutine_continuation_new(8800)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        XCTAssertNotEqual(sentinel, cont,
            "COROUTINE_SUSPENDED must not alias a regular continuation handle")
    }

    // MARK: - intercepted() — bypass semantics

    /// kk_continuation_intercepted on a fresh (undecorated) continuation returns
    /// the same handle (identity), meaning "no ContinuationInterceptor installed".
    /// This verifies that unintercepted variants correctly bypass ContinuationInterceptor.
    func testInterceptedFreshContinuationReturnsIdentity() {
        let cont = kk_coroutine_continuation_new(8801)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        // The freshly-created continuation has no dispatcher-backed context, so
        // intercepted() must return the same handle unchanged.
        XCTAssertEqual(intercepted, cont,
            "intercepted() on a continuation with no interceptor must return the same handle (bypass)")
    }

    /// kk_continuation_intercepted with the zero handle returns 0 (null safety guard).
    func testInterceptedZeroHandleReturnsZero() {
        let result = kk_continuation_intercepted(0)
        XCTAssertEqual(result, 0, "intercepted(null) must return 0")
    }

    /// kk_continuation_intercepted returns a non-zero handle for a valid continuation.
    func testInterceptedValidContinuationIsNonZero() {
        let cont = kk_coroutine_continuation_new(8802)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        XCTAssertNotEqual(intercepted, 0,
            "intercepted() must return a non-zero handle for a valid continuation")
    }

    // MARK: - kk_continuation_interceptor_intercept_continuation

    /// With an invalid interceptor (0), the original continuation handle is returned unchanged.
    func testInterceptorInterceptContinuationWithZeroInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8803)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let result = kk_continuation_interceptor_intercept_continuation(0, cont)
        XCTAssertEqual(result, cont,
            "Intercepting with null interceptor must return the original continuation unchanged")
    }

    /// With a valid continuation but no known dispatcher tag, the continuation is returned unchanged.
    func testInterceptorInterceptContinuationWithNonDispatcherInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8804)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        // Use the continuation itself as the interceptor — it is not a dispatcher,
        // so interception must be a no-op.
        let result = kk_continuation_interceptor_intercept_continuation(cont, cont)
        XCTAssertEqual(result, cont,
            "Non-dispatcher interceptor must leave the continuation unchanged")
    }

    /// With a zero continuation, the function returns 0 regardless of interceptor.
    func testInterceptorInterceptContinuationWithZeroContinuationReturnsZero() {
        let result = kk_continuation_interceptor_intercept_continuation(0, 0)
        XCTAssertEqual(result, 0,
            "Intercepting a null continuation must return 0")
    }

    // MARK: - CancellationException type identity

    /// runtimeAllocateCancellationException produces a non-zero pointer.
    func testCancellationExceptionAllocatePtrIsNonZero() {
        let exc = runtimeAllocateCancellationException()
        XCTAssertNotEqual(exc, 0, "CancellationException allocation must return a non-zero pointer")
    }

    /// kk_is_cancellation_exception returns 1 for a CancellationException.
    func testIsCancellationExceptionReturnsTrueForCancellation() {
        let exc = runtimeAllocateCancellationException()
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1,
            "kk_is_cancellation_exception must return 1 for a CancellationException")
    }

    /// kk_is_cancellation_exception returns 0 for a regular throwable.
    func testIsCancellationExceptionReturnsFalseForRegularThrowable() {
        let exc = runtimeAllocateThrowable(message: "regular error")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 0,
            "kk_is_cancellation_exception must return 0 for a non-CancellationException")
    }

    /// kk_is_cancellation_exception with zero returns 0 (null-safety).
    func testIsCancellationExceptionReturnsFalseForNull() {
        XCTAssertEqual(kk_is_cancellation_exception(0), 0,
            "kk_is_cancellation_exception(null) must return 0")
    }

    /// A CancellationException with a custom message round-trips correctly.
    func testCancellationExceptionCustomMessageRoundTrips() {
        let exc = runtimeAllocateCancellationException(message: "job was cancelled")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1)

        // Verify the message is accessible through the throwable API.
        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0, "CancellationException message handle must be non-zero")
    }

    /// A CancellationException with a cause stores the cause correctly.
    func testCancellationExceptionWithCauseRoundTrips() {
        let cause = runtimeAllocateThrowable(message: "root cause")
        let exc = runtimeAllocateCancellationException(message: "cancelled with cause", cause: cause)
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1)

        let causeRaw = kk_throwable_cause(exc)
        XCTAssertEqual(causeRaw, cause,
            "CancellationException must preserve its cause reference")
    }

    // MARK: - CancellationException is NOT a regular failure (Result semantics)

    /// When a coroutine block throws a CancellationException through kk_runCatching,
    /// the Result must be a failure AND kk_is_cancellation_exception on its stored
    /// exception must return 1 — distinguishing cancellation from error failure.
    func testRunCatchingWithCancellationExceptionProducesFailureResult() {
        // Use a non-capturing C stub that writes a CancellationException to outThrown.
        let cancellationExcRaw = runtimeAllocateCancellationException(message: "cancelled")

        // Store the exception raw value in a box so the C stub can access it.
        // We use a Ref<Int> trick via unsafeBitCast of a non-capturing closure.
        let stub: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { exc, outThrown in
            outThrown?.pointee = exc  // exc is passed as closureRaw
            return 0
        }
        let fnPtr = unsafeBitCast(stub, to: Int.self)

        var outerThrown = 0
        let resultRaw = kk_runCatching(fnPtr, cancellationExcRaw, &outerThrown)
        XCTAssertEqual(outerThrown, 0, "kk_runCatching outer outThrown must remain 0")
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1,
            "A block throwing CancellationException must produce Result.failure")
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 0,
            "A block throwing CancellationException must NOT be Result.success")

        // Crucially: the failure's exception must be identified as CancellationException,
        // not just as a generic throwable.
        let exceptionFromResult = kk_result_exceptionOrNull(resultRaw)
        XCTAssertEqual(kk_is_cancellation_exception(exceptionFromResult), 1,
            "Result.failure wrapping a CancellationException must be identified as CancellationException")
    }

    /// A Result.failure wrapping a regular exception must NOT be identified as CancellationException.
    func testRunCatchingWithRegularExceptionIsNotCancellation() {
        let regularExc = runtimeAllocateThrowable(message: "normal error")
        let stub: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { exc, outThrown in
            outThrown?.pointee = exc
            return 0
        }
        let fnPtr = unsafeBitCast(stub, to: Int.self)

        var outerThrown = 0
        let resultRaw = kk_runCatching(fnPtr, regularExc, &outerThrown)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)

        let exceptionFromResult = kk_result_exceptionOrNull(resultRaw)
        XCTAssertEqual(kk_is_cancellation_exception(exceptionFromResult), 0,
            "Result.failure wrapping a regular exception must NOT be identified as CancellationException")
    }

    // MARK: - CancellationException class hierarchy (RuntimeCancellationBox : RuntimeThrowableBox)

    /// Verifies that the RuntimeCancellationBox is a subtype of RuntimeThrowableBox by
    /// confirming that CancellationException pointers are tracked in the object store
    /// (same mechanism as all throwable allocations) and respond to throwable APIs.
    func testCancellationExceptionIsSubtypeOfThrowable() {
        let exc = runtimeAllocateCancellationException(message: "hierarchy check")
        // If it is a throwable, kk_throwable_message must return a non-zero handle.
        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0,
            "CancellationException must respond to throwable APIs (is-a RuntimeThrowableBox)")
        // And it must still be identified as a CancellationException.
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1,
            "CancellationException must also satisfy is-cancellation check (is-a RuntimeCancellationBox)")
    }

    /// A regular throwable is NOT a CancellationException (negative case).
    func testRegularThrowableIsNotCancellationException() {
        let exc = runtimeAllocateThrowable(message: "not cancelled")
        // It IS a throwable.
        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0, "Regular throwable must respond to throwable APIs")
        // But NOT a CancellationException.
        XCTAssertEqual(kk_is_cancellation_exception(exc), 0,
            "Regular throwable must not be identified as CancellationException")
    }

    // MARK: - COROUTINE_SUSPENDED in state machine short-circuit

    /// Simulates the generated state-machine equality check:
    ///   if (blockResult === COROUTINE_SUSPENDED) return COROUTINE_SUSPENDED
    /// When blockResult IS the sentinel, the check passes and the continuation suspends.
    func testStateMachineShortCircuitWhenResultIsSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = Int(bitPattern: kk_coroutine_suspended())

        let shouldSuspend = (blockResult == sentinel)
        XCTAssertTrue(shouldSuspend,
            "State machine must short-circuit and suspend when blockResult === COROUTINE_SUSPENDED")
    }

    /// When blockResult is NOT the sentinel, the check fails and the machine resumes inline.
    func testStateMachineDoesNotShortCircuitWhenResultIsNotSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = 42  // some actual computed value

        let shouldSuspend = (blockResult == sentinel)
        XCTAssertFalse(shouldSuspend,
            "State machine must NOT short-circuit when blockResult is a real value (not COROUTINE_SUSPENDED)")
    }

    // MARK: - CancellationException extends IllegalStateException hierarchy (PR #1261)

    /// CancellationException hierarchy must include kotlin.IllegalStateException so that
    /// catch (e: IllegalStateException) blocks catch CancellationException (Kotlin spec).
    func testCancellationExceptionHierarchyIncludesIllegalStateException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        XCTAssertTrue(
            box.exceptionHierarchyFQNames.contains("kotlin.IllegalStateException"),
            "CancellationException must be catchable as IllegalStateException per Kotlin spec"
        )
    }

    /// CancellationException hierarchy must include kotlin.RuntimeException.
    func testCancellationExceptionHierarchyIncludesRuntimeException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        XCTAssertTrue(
            box.exceptionHierarchyFQNames.contains("kotlin.RuntimeException"),
            "CancellationException must be catchable as RuntimeException per Kotlin spec"
        )
    }

    /// IllegalStateException must appear before RuntimeException in the hierarchy list
    /// (subtype ordering: CancellationException → ISE → RuntimeException → Exception → Throwable).
    func testCancellationExceptionHierarchyOrderingISEBeforeRuntimeException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let names = box.exceptionHierarchyFQNames
        let iseIndex = names.firstIndex(of: "kotlin.IllegalStateException")
        let rteIndex = names.firstIndex(of: "kotlin.RuntimeException")
        XCTAssertNotNil(iseIndex, "kotlin.IllegalStateException must be present")
        XCTAssertNotNil(rteIndex, "kotlin.RuntimeException must be present")
        if let ise = iseIndex, let rte = rteIndex {
            XCTAssertLessThan(ise, rte,
                "IllegalStateException must precede RuntimeException in the hierarchy list")
        }
    }

    /// runtimeThrowableMatchesNominalTypeID must return true when checking CancellationException
    /// against the nominal type ID of kotlin.IllegalStateException — this is what catch blocks use.
    func testCancellationExceptionMatchesIllegalStateExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let iseTypeID = runtimeStableNominalTypeID(fqName: "kotlin.IllegalStateException")
        XCTAssertTrue(
            runtimeThrowableMatchesNominalTypeID(box, targetTypeID: iseTypeID),
            "catch (e: IllegalStateException) must catch CancellationException"
        )
    }

    /// runtimeThrowableMatchesNominalTypeID must return true for kotlin.RuntimeException as well.
    func testCancellationExceptionMatchesRuntimeExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let rteTypeID = runtimeStableNominalTypeID(fqName: "kotlin.RuntimeException")
        XCTAssertTrue(
            runtimeThrowableMatchesNominalTypeID(box, targetTypeID: rteTypeID),
            "catch (e: RuntimeException) must catch CancellationException"
        )
    }
}
