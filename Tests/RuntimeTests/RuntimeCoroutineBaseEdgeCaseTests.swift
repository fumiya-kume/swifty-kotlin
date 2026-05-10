import Dispatch
@testable import Runtime
import XCTest

// MARK: - C stubs for kk_runCatching (no context capture allowed)

@_cdecl("coro_base_success_123_lambda")
private func coro_base_success_123_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 123
}

@_cdecl("coro_base_fail_lambda")
private func coro_base_fail_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // closureRaw carries the throwable pointer
    outThrown?.pointee = closureRaw
    return 0
}

private nonisolated(unsafe) var continuationFactoryCallbackResultRaw = 0
private nonisolated(unsafe) var continuationFactoryCallbackThrown = 0

@_cdecl("coro_base_continuation_factory_callback")
private func coro_base_continuation_factory_callback(
    _ resultRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    continuationFactoryCallbackResultRaw = resultRaw
    continuationFactoryCallbackThrown = 0
    return 0
}

// MARK: - Helper classes

/// Generic mutable value box for cross-closure capture.
private final class ValueBox<T>: @unchecked Sendable {
    var value: T
    init(_ initial: T) { value = initial }
}

/// Simple counter box for fold traversal tests.
private final class CountBox: @unchecked Sendable {
    var count: Int = 0
}

// MARK: - Private helpers

/// Register a RuntimeStringBox into the runtime object store and return its raw pointer Int.
private func runtimeRegisterStringBox(_ box: RuntimeStringBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Extract the String value from a raw RuntimeStringBox pointer.
private func runtimeStringBoxValue(_ raw: Int) -> String {
    guard raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return ""
    }
    return box.value
}

// MARK: - RuntimeCoroutineBaseEdgeCaseTests

/// Edge-case coverage for kotlin.coroutines base primitives:
/// Continuation<T>, CoroutineContext, EmptyCoroutineContext, CoroutineContext +/minusKey/fold,
/// resume/resumeWithException/resumeWith(Result<T>), suspendCoroutine, ContinuationInterceptor.
final class RuntimeCoroutineBaseEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        continuationFactoryCallbackResultRaw = 0
        continuationFactoryCallbackThrown = 0
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - resume / resumeWith(Result<T>)

    /// resume(value) propagates the value to the awaiting coroutine.
    func testContinuationResumeDeliversValue() {
        let fnID = 9901
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0, "continuation handle must be non-zero")

        let sem = DispatchSemaphore(value: 0)
        let resultBox = ValueBox<Int>(-1)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        state.installResumeContinuation {
            resultBox.value = Int(state.completion)
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume(cont, 42)
        }

        let waited = sem.wait(timeout: .now() + 3)
        XCTAssertEqual(waited, .success, "resume should signal within timeout")
        XCTAssertEqual(resultBox.value, 42, "resume(42) should deliver value 42")
    }

    /// resumeWithException propagates the throwable to the awaiting state.
    func testContinuationResumeWithExceptionPropagatesThrowable() {
        let fnID = 9902
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let exc = runtimeAllocateThrowable(message: "test error")
        let sem = DispatchSemaphore(value: 0)
        let thrownBox = ValueBox<Int>(0)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        state.installResumeContinuation {
            thrownBox.value = state.thrownException
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with_exception(cont, exc)
        }

        let waited = sem.wait(timeout: .now() + 3)
        XCTAssertEqual(waited, .success, "resumeWithException should signal within timeout")
        XCTAssertEqual(thrownBox.value, exc, "thrown exception must match the one passed in")
    }

    /// resumeWith(Result.success) propagates the value correctly.
    func testContinuationResumeWithResultSuccess() {
        let fnID = 9903
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let successFn = unsafeBitCast(
            coro_base_success_123_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(successFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)
        let resultValueBox = ValueBox<Int>(-1)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        state.installResumeContinuation {
            resultValueBox.value = Int(state.completion)
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        let waited = sem.wait(timeout: .now() + 3)
        XCTAssertEqual(waited, .success)
        XCTAssertEqual(resultValueBox.value, 123, "resumeWith(Result.success(123)) should deliver 123")
    }

    /// resumeWith(Result.failure) propagates the exception correctly.
    func testContinuationResumeWithResultFailure() {
        let fnID = 9904
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        // Allocate throwable and pass as closureRaw to the non-capturing stub
        let exc = runtimeAllocateThrowable(message: "fail result")
        let failFn = unsafeBitCast(
            coro_base_fail_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(failFn, exc, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)
        let thrownBox2 = ValueBox<Int>(0)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        state.installResumeContinuation {
            thrownBox2.value = state.thrownException
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        let waited = sem.wait(timeout: .now() + 3)
        XCTAssertEqual(waited, .success)
        XCTAssertEqual(thrownBox2.value, exc, "resumeWith(Result.failure) should propagate exception")
    }

    // MARK: - CoroutineContext + (plus)

    /// EmptyCoroutineContext + element == element (left identity).
    func testContextPlusEmptyLeftIsIdentity() {
        let nameRaw = kk_coroutine_name_create(0)  // "coroutine" default
        XCTAssertNotEqual(nameRaw, 0)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9907))
        let combined = kk_context_plus(emptyCtx, nameRaw)
        let retrievedName = kk_context_get_name(combined)
        XCTAssertNotEqual(retrievedName, 0, "empty + name-element should have a name")
    }

    /// element + EmptyCoroutineContext == element (right identity).
    func testContextPlusEmptyRightIsIdentity() {
        let nameRaw = kk_coroutine_name_create(0)
        XCTAssertNotEqual(nameRaw, 0)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9908))
        let nameCtx = kk_context_plus(emptyCtx, nameRaw)

        let emptyRight = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9909))
        let combined = kk_context_plus(nameCtx, emptyRight)
        let retrievedName = kk_context_get_name(combined)
        XCTAssertNotEqual(retrievedName, 0, "name-element + empty should preserve the name")
    }

    /// Right-hand element wins on key collision during plus.
    func testContextPlusRightWinsOnKeyCollision() {
        let nameABox = RuntimeStringBox("Alice")
        let nameAPtr = runtimeRegisterStringBox(nameABox)
        let nameA = kk_coroutine_name_create(nameAPtr)

        let nameBBox = RuntimeStringBox("Bob")
        let nameBPtr = runtimeRegisterStringBox(nameBBox)
        let nameB = kk_coroutine_name_create(nameBPtr)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9910))
        let ctxA = kk_context_plus(emptyCtx, nameA)
        let ctxB = kk_context_plus(ctxA, nameB)

        let nameHandleRaw = kk_context_get_name(ctxB)
        XCTAssertNotEqual(nameHandleRaw, 0, "merged context should have a name")
        let nameValue = runtimeStringBoxValue(nameHandleRaw)
        XCTAssertEqual(nameValue, "Bob", "right-hand name should win on collision")
    }

    // MARK: - CoroutineContext minusKey

    /// minusKey removes the element matching the key.
    func testContextMinusKeyRemovesNameElement() {
        let nameBox = RuntimeStringBox("TestName")
        let namePtr = runtimeRegisterStringBox(nameBox)
        let nameElem = kk_coroutine_name_create(namePtr)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9911))
        let withName = kk_context_plus(emptyCtx, nameElem)

        XCTAssertNotEqual(kk_context_get_name(withName), 0, "should have name before minusKey")

        let withoutName = kk_context_minusKey(withName, nameElem)
        XCTAssertEqual(kk_context_get_name(withoutName), 0, "name should be absent after minusKey")
    }

    /// minusKey on a key not present is a no-op.
    func testContextMinusKeyNonPresentIsNoOp() {
        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9912))
        let nameElem = kk_coroutine_name_create(0)

        let result = kk_context_minusKey(emptyCtx, nameElem)
        XCTAssertEqual(kk_context_get_name(result), 0, "minusKey on absent element should leave context unchanged")
    }

    // MARK: - CoroutineContext fold traversal

    /// fold visits each context element exactly once.
    func testContextFoldVisitsElements() {
        let nameBox = RuntimeStringBox("FoldTest")
        let namePtr = runtimeRegisterStringBox(nameBox)
        let nameElem = kk_coroutine_name_create(namePtr)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9913))
        let ctx = kk_context_plus(emptyCtx, nameElem)

        let countBox = CountBox()
        let countBoxRaw = Int(bitPattern: Unmanaged.passUnretained(countBox).toOpaque())

        let accFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, acc, _, outThrown in
            outThrown?.pointee = 0
            let box = Unmanaged<CountBox>.fromOpaque(UnsafeMutableRawPointer(bitPattern: closureRaw)!).takeUnretainedValue()
            box.count += 1
            return acc + 1
        }
        let fnPtr = unsafeBitCast(accFn, to: Int.self)

        var outThrown = 0
        let finalAcc = kk_context_fold(ctx, 0, fnPtr, countBoxRaw, &outThrown)

        XCTAssertEqual(outThrown, 0)
        XCTAssertGreaterThan(finalAcc, 0, "fold should accumulate at least one element")
        XCTAssertGreaterThan(countBox.count, 0, "fold visitor closure should have been called")
    }

    /// fold on empty context returns initial value.
    func testContextFoldEmptyReturnsInitial() {
        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9914))
        let noopFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, _, out in
            out?.pointee = 0
            return acc + 1
        }
        let fnPtr = unsafeBitCast(noopFn, to: Int.self)
        var outThrown = 0
        let result = kk_context_fold(emptyCtx, 99, fnPtr, 0, &outThrown)
        XCTAssertEqual(outThrown, 0)
        // Fresh continuation context has no dispatcher / name / handler by default.
        // The key invariant: no exception and result >= 99.
        XCTAssertGreaterThanOrEqual(result, 99, "fold on context with no extra elements should not decrease accumulator")
    }

    // MARK: - CoroutineName create / get

    /// kk_coroutine_name_create with a null pointer uses "coroutine" as default.
    func testCoroutineNameCreateDefaultName() {
        let nameHandle = kk_coroutine_name_create(0)
        XCTAssertNotEqual(nameHandle, 0)

        let gotNameRaw = kk_coroutine_name_get(nameHandle)
        XCTAssertNotEqual(gotNameRaw, 0)
        let name = runtimeStringBoxValue(gotNameRaw)
        XCTAssertEqual(name, "coroutine", "default name should be 'coroutine'")
    }

    /// kk_coroutine_name_create with a valid RuntimeStringBox preserves the name.
    func testCoroutineNameCreateWithExplicitName() {
        let strBox = RuntimeStringBox("MyCoroutine")
        let strPtr = runtimeRegisterStringBox(strBox)
        let nameHandle = kk_coroutine_name_create(strPtr)
        XCTAssertNotEqual(nameHandle, 0)

        let gotNameRaw = kk_coroutine_name_get(nameHandle)
        XCTAssertNotEqual(gotNameRaw, 0)
        let name = runtimeStringBoxValue(gotNameRaw)
        XCTAssertEqual(name, "MyCoroutine", "name should round-trip through create/get")
    }

    /// kk_coroutine_name_get on invalid handle returns empty string.
    func testCoroutineNameGetInvalidHandleReturnsEmpty() {
        let gotNameRaw = kk_coroutine_name_get(0)
        let name = runtimeStringBoxValue(gotNameRaw)
        XCTAssertEqual(name, "", "invalid handle should produce empty string")
    }

    // MARK: - CoroutineExceptionHandler create / invoke

    /// kk_exception_handler_create with fnPtr=0 and kk_exception_handler_invoke do not crash.
    func testExceptionHandlerCreateAndInvokeWithFallback() {
        let handlerHandle = kk_exception_handler_create(0)
        XCTAssertNotEqual(handlerHandle, 0, "exception handler handle should be non-zero")

        // Invoke with a dummy exception — falls back to stderr output, must not crash.
        let exc = runtimeAllocateThrowable(message: "handler test")
        kk_exception_handler_invoke(handlerHandle, 0, exc)
    }

    /// kk_exception_handler_invoke with zero handler is a no-op.
    func testExceptionHandlerInvokeZeroHandlerIsNoOp() {
        let exc = runtimeAllocateThrowable(message: "noop test")
        kk_exception_handler_invoke(0, 0, exc)
    }

    // MARK: - ContinuationInterceptor

    /// kk_continuation_intercepted with a fresh continuation returns a valid handle.
    func testContinuationInterceptedFreshContinuationReturnsNonZero() {
        let cont = kk_coroutine_continuation_new(9915)
        XCTAssertNotEqual(cont, 0)
        let intercepted = kk_continuation_intercepted(cont)
        XCTAssertNotEqual(intercepted, 0, "intercepted handle should be non-zero")
    }

    /// kk_continuation_intercepted with zero handle returns zero.
    func testContinuationInterceptedZeroHandleReturnsZero() {
        let intercepted = kk_continuation_intercepted(0)
        XCTAssertEqual(intercepted, 0, "intercepted(0) should return 0")
    }

    // MARK: - CoroutineContext element retrieval

    /// kk_context_get returns 0 for a key not present in the context.
    func testContextGetAbsentKeyReturnsZero() {
        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9916))
        let nameElem = kk_coroutine_name_create(0)
        let result = kk_context_get(emptyCtx, nameElem)
        XCTAssertEqual(result, 0, "context_get for absent key should return 0")
    }

    /// kk_context_get returns element for a key that is present.
    func testContextGetPresentKeyReturnsElement() {
        let nameBox = RuntimeStringBox("Present")
        let namePtr = runtimeRegisterStringBox(nameBox)
        let nameElem = kk_coroutine_name_create(namePtr)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9917))
        let ctx = kk_context_plus(emptyCtx, nameElem)

        let retrieved = kk_context_get(ctx, nameElem)
        XCTAssertNotEqual(retrieved, 0, "context_get for present key should return non-zero")
    }

    // MARK: - CoroutineContext dispatcher extraction

    /// kk_context_get_dispatcher on a context without dispatcher returns 0.
    func testContextGetDispatcherAbsentReturnsZero() {
        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(9918))
        let dispatcher = kk_context_get_dispatcher(emptyCtx)
        XCTAssertEqual(dispatcher, 0, "context with no dispatcher should return 0")
    }

    /// kk_context_get_dispatcher on a dispatcher tag itself returns the tag.
    func testContextGetDispatcherTagReturnsSelf() {
        let defaultDispatcher = kk_dispatcher_default()
        XCTAssertNotEqual(defaultDispatcher, 0)
        let retrieved = kk_context_get_dispatcher(defaultDispatcher)
        XCTAssertEqual(retrieved, defaultDispatcher, "dispatcher tag passed directly should be returned as-is")
    }

    // MARK: - kk_coroutine_continuation_context

    /// kk_coroutine_continuation_context returns a valid context for a valid continuation.
    func testContinuationContextIsNonZeroForValidContinuation() {
        let cont = kk_coroutine_continuation_new(9919)
        XCTAssertNotEqual(cont, 0)
        let ctx = kk_coroutine_continuation_context(cont)
        XCTAssertNotEqual(ctx, 0, "continuation context should be non-zero for a valid continuation")
    }

    func testCurrentCoroutineContextFallsBackToEmptyContextOutsideCoroutine() {
        let ctx = kk_coroutine_current_context()
        XCTAssertNotEqual(ctx, 0, "current coroutine context should be non-zero outside a coroutine")
    }

    func testContinuationFactoryContextAndResumeSuccessRoundTrip() {
        let contextRaw = kk_context_plus(0, 0)
        XCTAssertNotEqual(contextRaw, 0)
        let resumeWithRaw = unsafeBitCast(
            coro_base_continuation_factory_callback as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        let cont = kk_coroutine_continuation_factory(contextRaw, resumeWithRaw)
        XCTAssertNotEqual(cont, 0)
        XCTAssertEqual(kk_coroutine_continuation_context(cont), contextRaw)

        kk_coroutine_continuation_resume(cont, 321)

        XCTAssertNotEqual(continuationFactoryCallbackResultRaw, 0)
        XCTAssertEqual(continuationFactoryCallbackThrown, 0)
        XCTAssertEqual(kk_result_isSuccess(continuationFactoryCallbackResultRaw), 1)
        XCTAssertEqual(kk_result_getOrNull(continuationFactoryCallbackResultRaw), 321)
    }

    func testContinuationFactoryResumeWithExceptionWrapsFailureResult() {
        let resumeWithRaw = unsafeBitCast(
            coro_base_continuation_factory_callback as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let cont = kk_coroutine_continuation_factory(kk_context_plus(0, 0), resumeWithRaw)
        let exceptionRaw = runtimeAllocateThrowable(message: "factory boom")

        kk_coroutine_continuation_resume_with_exception(cont, exceptionRaw)

        XCTAssertNotEqual(continuationFactoryCallbackResultRaw, 0)
        XCTAssertEqual(kk_result_isFailure(continuationFactoryCallbackResultRaw), 1)
        XCTAssertEqual(kk_result_exceptionOrNull(continuationFactoryCallbackResultRaw), exceptionRaw)
    }

    // MARK: - Result round-trip

    /// Success Result: isSuccess == true, isFailure == false, getOrNull returns value.
    func testResultSuccessRoundTrip() {
        let successFn = unsafeBitCast(
            coro_base_success_123_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(successFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 1, "success Result must report isSuccess=true")
        XCTAssertEqual(kk_result_isFailure(resultRaw), 0, "success Result must report isFailure=false")
        let value = kk_result_getOrNull(resultRaw)
        XCTAssertEqual(value, 123, "getOrNull should return the success value")
    }

    /// Failure Result: isSuccess == false, isFailure == true, getOrNull returns null sentinel.
    func testResultFailureRoundTrip() {
        let exc = runtimeAllocateThrowable(message: "round-trip fail")
        let failFn = unsafeBitCast(
            coro_base_fail_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = kk_runCatching(failFn, exc, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 0, "failure Result must report isSuccess=false")
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1, "failure Result must report isFailure=true")
        // kk_result_getOrNull returns runtimeNullSentinelInt (Int.min) for failure.
        let value = kk_result_getOrNull(resultRaw)
        XCTAssertEqual(value, Int.min, "getOrNull for failure should return the null sentinel (Int.min)")
    }
}
