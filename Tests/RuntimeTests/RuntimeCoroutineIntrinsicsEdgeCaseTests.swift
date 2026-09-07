#if canImport(Testing)
import Dispatch
@testable import Runtime
import Testing

private typealias RuntimeCoroutineIntrinsicEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let coroutineIntrinsicsDelayFunctionID = 8810
private let coroutineIntrinsicsReceiverFunctionID = 8811

@_cdecl("coro_intrinsics_return_123")
private func coro_intrinsics_return_123(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 123)
}

@_cdecl("coro_intrinsics_delay_then_return")
private func coro_intrinsics_delay_then_return(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, coroutineIntrinsicsDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 456)
}

@_cdecl("coro_intrinsics_receiver_plus_one")
private func coro_intrinsics_receiver_plus_one(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = kk_coroutine_state_enter(continuation, coroutineIntrinsicsReceiverFunctionID)
    outThrown?.pointee = 0
    let receiver = kk_coroutine_launcher_arg_get(continuation, 0)
    return kk_coroutine_state_exit(continuation, Int(receiver) + 1)
}

@_cdecl("coro_intrinsics_throw_immediately")
private func coro_intrinsics_throw_immediately(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "intrinsic boom")
    _ = kk_coroutine_state_exit(continuation, 0)
    return 0
}

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
//   • runtimeResultRunCatching + cancellation-exception propagation through Result
//   • kk_create_coroutine_unintercepted / kk_start_coroutine_unintercepted_or_return
// CancellationException inherits IllegalStateException → RuntimeException in Kotlin.
// RuntimeCancellationBox reports this chain via exceptionHierarchyFQNames so catch clauses
// targeting IllegalStateException / RuntimeException match CancellationException at runtime (PR #1261).

@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeCoroutineIntrinsicsEdgeCaseTests {

    // MARK: - COROUTINE_SUSPENDED sentinel

    /// kk_coroutine_suspended() returns a stable non-null pointer.
    @Test func coroutineSuspendedSentinelIsNonNull() {
        let sentinel = kk_coroutine_suspended()
        #expect(Int(bitPattern: sentinel) != 0, "COROUTINE_SUSPENDED sentinel must be non-null")
    }

    /// Two consecutive calls return the same pointer (singleton identity).
    @Test func coroutineSuspendedSentinelIsSingletonIdentity() {
        let first = kk_coroutine_suspended()
        let second = kk_coroutine_suspended()
        #expect(first == second, "COROUTINE_SUSPENDED sentinel must return the same object on every call")
    }

    /// The COROUTINE_SUSPENDED sentinel must compare equal to itself (pointer equality).
    /// This models the `result === COROUTINE_SUSPENDED` check in the state machine.
    @Test func coroutineSuspendedSentinelEqualityCheck() {
        let sentinelA = kk_coroutine_suspended()
        let sentinelB = kk_coroutine_suspended()
        // Pointer equality — simulates the generated jumpIfEqual comparison.
        #expect(sentinelA == sentinelB, "COROUTINE_SUSPENDED pointer equality check must hold (state-machine short-circuit)")
    }

    /// The sentinel pointer must NOT compare equal to an unrelated object.
    @Test func coroutineSuspendedSentinelNotEqualToOtherObject() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let cont = kk_coroutine_continuation_new(8800)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        #expect(sentinel != cont, "COROUTINE_SUSPENDED must not alias a regular continuation handle")
    }

    // MARK: - start/create unintercepted runtime entry points

    @Test func createCoroutineUninterceptedStartsWhenReturnedContinuationIsResumed() throws {
        let completion = kk_coroutine_continuation_new(8812)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try #require(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_return_123 as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )

        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        #expect(continuation != 0)

        kk_coroutine_continuation_resume(continuation, 0)
        #expect(Int(completionState.completion) == 123)
        #expect(completionState.thrownException == 0)
    }

    @Test func createCoroutineUninterceptedPreservesReceiverLauncherArg() throws {
        let completion = kk_coroutine_continuation_new(8813)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try #require(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_receiver_plus_one as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )

        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 41)
        kk_coroutine_continuation_resume(continuation, 0)

        #expect(Int(completionState.completion) == 42)
        #expect(completionState.thrownException == 0)
    }

    @Test func startCoroutineUninterceptedOrReturnReturnsImmediateResult() throws {
        let completion = kk_coroutine_continuation_new(8814)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try #require(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_return_123 as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        #expect(result == 123)
        #expect(thrown == 0)
        #expect(Int(completionState.completion) == 0)
        #expect(completionState.thrownException == 0)
    }

    @Test func startCoroutineUninterceptedOrReturnSuspendsAndResumesCompletion() throws {
        let completion = kk_coroutine_continuation_new(8815)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try #require(runtimeContinuationState(from: completion))
        let completed = DispatchSemaphore(value: 0)
        completionState.installResumeContinuation {
            completed.signal()
        }
        let entryRaw = unsafeBitCast(
            coro_intrinsics_delay_then_return as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        #expect(result == Int(bitPattern: kk_coroutine_suspended()))
        #expect(thrown == 0)
        #expect(completed.wait(timeout: .now() + 3) == .success)
        #expect(Int(completionState.completion) == 456)
        #expect(completionState.thrownException == 0)
    }

    @Test func startCoroutineUninterceptedOrReturnPropagatesImmediateThrow() throws {
        let completion = kk_coroutine_continuation_new(8816)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try #require(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_throw_immediately as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        #expect(result == 0)
        #expect(thrown != 0)
        #expect(Int(completionState.completion) == 0)
        #expect(completionState.thrownException == 0)
    }

    // MARK: - intercepted() — bypass semantics

    /// kk_continuation_intercepted on a fresh (undecorated) continuation returns
    /// the same handle (identity), meaning "no ContinuationInterceptor installed".
    /// This verifies that unintercepted variants correctly bypass ContinuationInterceptor.
    @Test func interceptedFreshContinuationReturnsIdentity() {
        let cont = kk_coroutine_continuation_new(8801)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        // The freshly-created continuation has no dispatcher-backed context, so
        // intercepted() must return the same handle unchanged.
        #expect(intercepted == cont, "intercepted() on a continuation with no interceptor must return the same handle (bypass)")
    }

    /// kk_continuation_intercepted with the zero handle returns 0 (null safety guard).
    @Test func interceptedZeroHandleReturnsZero() {
        let result = kk_continuation_intercepted(0)
        #expect(result == 0, "intercepted(null) must return 0")
    }

    /// kk_continuation_intercepted returns a non-zero handle for a valid continuation.
    @Test func interceptedValidContinuationIsNonZero() {
        let cont = kk_coroutine_continuation_new(8802)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        #expect(intercepted != 0, "intercepted() must return a non-zero handle for a valid continuation")
    }

    // MARK: - kk_continuation_interceptor_intercept_continuation

    /// With an invalid interceptor (0), the original continuation handle is returned unchanged.
    @Test func interceptorInterceptContinuationWithZeroInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8803)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let result = kk_continuation_interceptor_intercept_continuation(0, cont)
        #expect(result == cont, "Intercepting with null interceptor must return the original continuation unchanged")
    }

    /// With a valid continuation but no known dispatcher tag, the continuation is returned unchanged.
    @Test func interceptorInterceptContinuationWithNonDispatcherInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8804)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        // Use the continuation itself as the interceptor — it is not a dispatcher,
        // so interception must be a no-op.
        let result = kk_continuation_interceptor_intercept_continuation(cont, cont)
        #expect(result == cont, "Non-dispatcher interceptor must leave the continuation unchanged")
    }

    /// With a zero continuation, the function returns 0 regardless of interceptor.
    @Test func interceptorInterceptContinuationWithZeroContinuationReturnsZero() {
        let result = kk_continuation_interceptor_intercept_continuation(0, 0)
        #expect(result == 0, "Intercepting a null continuation must return 0")
    }

    // MARK: - CancellationException type identity

    /// runtimeAllocateCancellationException produces a non-zero pointer.
    @Test func cancellationExceptionAllocatePtrIsNonZero() {
        let exc = runtimeAllocateCancellationException()
        #expect(exc != 0, "CancellationException allocation must return a non-zero pointer")
    }

    /// kk_is_cancellation_exception returns 1 for a CancellationException.
    @Test func isCancellationExceptionReturnsTrueForCancellation() {
        let exc = runtimeAllocateCancellationException()
        #expect(kk_is_cancellation_exception(exc) == 1, "kk_is_cancellation_exception must return 1 for a CancellationException")
    }

    /// kk_is_cancellation_exception returns 0 for a regular throwable.
    @Test func isCancellationExceptionReturnsFalseForRegularThrowable() {
        let exc = runtimeAllocateThrowable(message: "regular error")
        #expect(kk_is_cancellation_exception(exc) == 0, "kk_is_cancellation_exception must return 0 for a non-CancellationException")
    }

    /// kk_is_cancellation_exception with zero returns 0 (null-safety).
    @Test func isCancellationExceptionReturnsFalseForNull() {
        #expect(kk_is_cancellation_exception(0) == 0, "kk_is_cancellation_exception(null) must return 0")
    }

    /// A CancellationException with a custom message round-trips correctly.
    @Test func cancellationExceptionCustomMessageRoundTrips() {
        let exc = runtimeAllocateCancellationException(message: "job was cancelled")
        #expect(kk_is_cancellation_exception(exc) == 1)

        // Verify the message is accessible through the throwable API.
        let msgRaw = __kk_throwable_message(exc)
        #expect(msgRaw != 0, "CancellationException message handle must be non-zero")
    }

    /// A CancellationException with a cause stores the cause correctly.
    @Test func cancellationExceptionWithCauseRoundTrips() {
        let cause = runtimeAllocateThrowable(message: "root cause")
        let exc = runtimeAllocateCancellationException(message: "cancelled with cause", cause: cause)
        #expect(kk_is_cancellation_exception(exc) == 1)

        let causeRaw = __kk_throwable_cause(exc)
        #expect(causeRaw == cause, "CancellationException must preserve its cause reference")
    }

    /// Each source-backed CancellationException constructor bridge must retain
    /// the cancellation runtime identity and preserve its cause arguments.
    @Test func cancellationExceptionConstructorBridgesPreserveIdentity() {
        let message = registerRuntimeObject(RuntimeStringBox("bridge message"))
        let cause = runtimeAllocateThrowable(message: "bridge cause")
        let constructors = [
            kk_cancellation_exception_new(),
            kk_cancellation_exception_new_message(message),
            kk_cancellation_exception_new_cause(cause),
            kk_cancellation_exception_new_message_cause(message, cause),
        ]

        for exception in constructors {
            #expect(kk_is_cancellation_exception(exception) == 1)
        }
        #expect(__kk_throwable_cause(constructors[0]) == runtimeNullSentinelInt)
        #expect(__kk_throwable_cause(constructors[1]) == runtimeNullSentinelInt)
        #expect(__kk_throwable_cause(constructors[2]) == cause)
        #expect(__kk_throwable_cause(constructors[3]) == cause)
    }

    // MARK: - CancellationException is NOT a regular failure (Result semantics)

    /// When a coroutine block throws a CancellationException through runtimeResultRunCatching,
    /// the Result must be a failure AND kk_is_cancellation_exception on its stored
    /// exception must return 1 — distinguishing cancellation from error failure.
    @Test func runCatchingWithCancellationExceptionProducesFailureResult() {
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
        let resultRaw = runtimeResultRunCatching(fnPtr, cancellationExcRaw, &outerThrown)
        #expect(outerThrown == 0, "runtimeResultRunCatching outer outThrown must remain 0")
        #expect(runtimeResultFailureFlag(resultRaw) == 1, "A block throwing CancellationException must produce Result.failure")
        #expect(runtimeResultSuccessFlag(resultRaw) == 0, "A block throwing CancellationException must NOT be Result.success")

        // Crucially: the failure's exception must be identified as CancellationException,
        // not just as a generic throwable.
        let exceptionFromResult = runtimeResultExceptionOrNull(resultRaw)
        #expect(kk_is_cancellation_exception(exceptionFromResult) == 1, "Result.failure wrapping a CancellationException must be identified as CancellationException")
    }

    /// A Result.failure wrapping a regular exception must NOT be identified as CancellationException.
    @Test func runCatchingWithRegularExceptionIsNotCancellation() {
        let regularExc = runtimeAllocateThrowable(message: "normal error")
        let stub: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { exc, outThrown in
            outThrown?.pointee = exc
            return 0
        }
        let fnPtr = unsafeBitCast(stub, to: Int.self)

        var outerThrown = 0
        let resultRaw = runtimeResultRunCatching(fnPtr, regularExc, &outerThrown)
        #expect(runtimeResultFailureFlag(resultRaw) == 1)

        let exceptionFromResult = runtimeResultExceptionOrNull(resultRaw)
        #expect(kk_is_cancellation_exception(exceptionFromResult) == 0, "Result.failure wrapping a regular exception must NOT be identified as CancellationException")
    }

    // MARK: - CancellationException class hierarchy (RuntimeCancellationBox : RuntimeThrowableBox)

    /// Verifies that the RuntimeCancellationBox is a subtype of RuntimeThrowableBox by
    /// confirming that CancellationException pointers are tracked in the object store
    /// (same mechanism as all throwable allocations) and respond to throwable APIs.
    @Test func cancellationExceptionIsSubtypeOfThrowable() {
        let exc = runtimeAllocateCancellationException(message: "hierarchy check")
        // If it is a throwable, __kk_throwable_message must return a non-zero handle.
        let msgRaw = __kk_throwable_message(exc)
        #expect(msgRaw != 0, "CancellationException must respond to throwable APIs (is-a RuntimeThrowableBox)")
        // And it must still be identified as a CancellationException.
        #expect(kk_is_cancellation_exception(exc) == 1, "CancellationException must also satisfy is-cancellation check (is-a RuntimeCancellationBox)")
    }

    /// A regular throwable is NOT a CancellationException (negative case).
    @Test func regularThrowableIsNotCancellationException() {
        let exc = runtimeAllocateThrowable(message: "not cancelled")
        // It IS a throwable.
        let msgRaw = __kk_throwable_message(exc)
        #expect(msgRaw != 0, "Regular throwable must respond to throwable APIs")
        // But NOT a CancellationException.
        #expect(kk_is_cancellation_exception(exc) == 0, "Regular throwable must not be identified as CancellationException")
    }

    // MARK: - COROUTINE_SUSPENDED in state machine short-circuit

    /// Simulates the generated state-machine equality check:
    ///   if (blockResult === COROUTINE_SUSPENDED) return COROUTINE_SUSPENDED
    /// When blockResult IS the sentinel, the check passes and the continuation suspends.
    @Test func stateMachineShortCircuitWhenResultIsSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = Int(bitPattern: kk_coroutine_suspended())

        let shouldSuspend = (blockResult == sentinel)
        #expect(shouldSuspend, "State machine must short-circuit and suspend when blockResult === COROUTINE_SUSPENDED")
    }

    /// When blockResult is NOT the sentinel, the check fails and the machine resumes inline.
    @Test func stateMachineDoesNotShortCircuitWhenResultIsNotSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = 42  // some actual computed value

        let shouldSuspend = (blockResult == sentinel)
        #expect(!(shouldSuspend), "State machine must NOT short-circuit when blockResult is a real value (not COROUTINE_SUSPENDED)")
    }

    // MARK: - CancellationException extends IllegalStateException hierarchy (PR #1261)

    /// CancellationException hierarchy must include kotlin.IllegalStateException so that
    /// catch (e: IllegalStateException) blocks catch CancellationException (Kotlin spec).
    @Test func cancellationExceptionHierarchyIncludesIllegalStateException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        #expect(box.exceptionHierarchyFQNames.contains("kotlin.IllegalStateException"), "CancellationException must be catchable as IllegalStateException per Kotlin spec")
    }

    /// CancellationException hierarchy must include kotlin.RuntimeException.
    @Test func cancellationExceptionHierarchyIncludesRuntimeException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        #expect(box.exceptionHierarchyFQNames.contains("kotlin.RuntimeException"), "CancellationException must be catchable as RuntimeException per Kotlin spec")
    }

    /// IllegalStateException must appear before RuntimeException in the hierarchy list
    /// (subtype ordering: CancellationException → ISE → RuntimeException → Exception → Throwable).
    @Test func cancellationExceptionHierarchyOrderingISEBeforeRuntimeException() throws {
        let box = RuntimeCancellationBox(message: "cancelled")
        let names = box.exceptionHierarchyFQNames
        let iseIndex = try #require(names.firstIndex(of: "kotlin.IllegalStateException"),
            "kotlin.IllegalStateException must be present")
        let rteIndex = try #require(names.firstIndex(of: "kotlin.RuntimeException"),
            "kotlin.RuntimeException must be present")
        #expect(iseIndex < rteIndex,
            "IllegalStateException must precede RuntimeException in the hierarchy list")
    }

    /// runtimeThrowableMatchesNominalTypeID must return true when checking CancellationException
    /// against the nominal type ID of kotlin.IllegalStateException — this is what catch blocks use.
    @Test func cancellationExceptionMatchesIllegalStateExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let iseTypeID = runtimeStableNominalTypeID(fqName: "kotlin.IllegalStateException")
        #expect(runtimeThrowableMatchesNominalTypeID(box, targetTypeID: iseTypeID), "catch (e: IllegalStateException) must catch CancellationException")
    }

    /// runtimeThrowableMatchesNominalTypeID must return true for kotlin.RuntimeException as well.
    @Test func cancellationExceptionMatchesRuntimeExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let rteTypeID = runtimeStableNominalTypeID(fqName: "kotlin.RuntimeException")
        #expect(runtimeThrowableMatchesNominalTypeID(box, targetTypeID: rteTypeID), "catch (e: RuntimeException) must catch CancellationException")
    }
}
#endif
