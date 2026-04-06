// MARK: - Flow Error Handling Public API (STDLIB-FLOW-179)
//
// Public `@_cdecl` entry points for Kotlin Flow error-handling operators.
// Each function appends an op to the existing flow's op chain and returns
// a new registered flow handle — the same copy-on-write pattern used by
// `kk_flow_emit`.
//
// Operator semantics:
//   catch { }          – handle upstream exceptions; suppress or re-throw
//   retry(n)           – retry the source up to n times on failure
//   retryWhen { }      – conditional retry with (cause, attempt) -> Boolean
//   onErrorReturn(v)   – emit a fallback value on error, then complete normally
//   onErrorResume(f)   – switch to a fallback flow on error
//   onCompletion { }   – run a side-effect on completion (success or error)

/// Append a `catch` handler to the given flow.
///
/// `handlerFnPtr`: `(closureRaw: Int, throwable: Int, outThrown: *Int) -> Int`
/// The handler receives the exception pointer.  If it returns normally the
/// exception is swallowed; if it itself throws the new exception propagates.
@_cdecl("kk_flow_catch")
public func kk_flow_catch(_ flowHandle: Int, _ handlerFnPtr: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, handlerFnPtr, RuntimeFlowTagValues.catchHandler)
}

/// Append a `retry` operator to the given flow.
///
/// `retries`: maximum number of retry attempts (0 means no retries beyond the
/// initial attempt).
@_cdecl("kk_flow_retry")
public func kk_flow_retry(_ flowHandle: Int, _ retries: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, retries, RuntimeFlowTagValues.retry)
}

/// Append a `retryWhen` operator to the given flow.
///
/// `predicateFnPtr`: `(closureRaw: Int, cause: Int, attempt: Int, outThrown: *Int) -> Int`
/// Returns non-zero to retry, zero to stop retrying and propagate the failure.
@_cdecl("kk_flow_retry_when")
public func kk_flow_retry_when(_ flowHandle: Int, _ predicateFnPtr: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, predicateFnPtr, RuntimeFlowTagValues.retryWhen)
}

/// Append an `onErrorReturn` operator to the given flow.
///
/// `fallbackValue`: the value to emit when an upstream error occurs.
/// After emitting the fallback value the flow completes normally.
@_cdecl("kk_flow_on_error_return")
public func kk_flow_on_error_return(_ flowHandle: Int, _ fallbackValue: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, fallbackValue, RuntimeFlowTagValues.onErrorReturn)
}

/// Append an `onErrorResume` operator to the given flow.
///
/// `fallbackFlowHandle`: a flow handle whose emissions replace the failed
/// upstream on error.
@_cdecl("kk_flow_on_error_resume")
public func kk_flow_on_error_resume(_ flowHandle: Int, _ fallbackFlowHandle: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, fallbackFlowHandle, RuntimeFlowTagValues.onErrorResume)
}

/// Append an `onCompletion` handler to the given flow.
///
/// `handlerFnPtr`: `(closureRaw: Int, throwable: Int, outThrown: *Int) -> Int`
/// Called when the flow completes, whether successfully (throwable == 0) or
/// with an error (throwable != 0).  The handler's return value is ignored.
@_cdecl("kk_flow_on_completion")
public func kk_flow_on_completion(_ flowHandle: Int, _ handlerFnPtr: Int, _: Int) -> Int {
    return kk_flow_emit(flowHandle, handlerFnPtr, RuntimeFlowTagValues.onCompletion)
}

// MARK: - Tag constant shim
//
// RuntimeFlowTag is private, so we expose its raw values through this
// internal namespace so the @_cdecl wrappers above can call kk_flow_emit
// without duplicating magic numbers.

internal enum RuntimeFlowTagValues {
    static let catchHandler = 6
    static let retry = 7
    static let retryWhen = 8
    static let onErrorReturn = 9
    static let onErrorResume = 10
    static let onCompletion = 20
}
