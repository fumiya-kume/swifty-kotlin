import Foundation

// MARK: - TimerTask box

/// Wraps a DispatchSourceTimer so the Kotlin side can hold and cancel it
/// via the opaque `TimerTask` handle returned by `schedule`.
final class RuntimeTimerTaskBox: @unchecked Sendable {
    private let source: DispatchSourceTimer
    let fnPtr: Int
    let closureRaw: Int

    init(source: DispatchSourceTimer, fnPtr: Int, closureRaw: Int) {
        self.source = source
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
    }

    func cancel() {
        source.cancel()
    }
}

// MARK: - kk_concurrent_schedule_delay

/// Runtime backing for `Timer.schedule(delay: Long, action: TimerTask.() -> Unit): TimerTask`.
///
/// Schedules a one-shot timer that fires after `delayMs` milliseconds.
/// Returns an opaque `TimerTask` handle that can be cancelled.
///
/// - Parameters:
///   - timerRaw:   Opaque handle of the owning `java.util.Timer` (unused at runtime; included for ABI parity).
///   - delayMs:    Delay before first (and only) execution, in milliseconds.
///   - fnPtr:      Function pointer of the KK closure thunk for the action lambda.
///   - closureRaw: Closure environment pointer for the action lambda.
///   - outThrown:  Written to non-zero if the action throws a Kotlin exception.
/// - Returns: Opaque `TimerTask` handle (a `RuntimeTimerTaskBox`).
@_cdecl("kk_concurrent_schedule_delay")
public func kk_concurrent_schedule_delay(
    _ timerRaw: Int,
    _ delayMs: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_concurrent_schedule_delay received nil fnPtr")
    }

    let source = DispatchSource.makeTimerSource(queue: .global())
    let box = RuntimeTimerTaskBox(source: source, fnPtr: fnPtr, closureRaw: closureRaw)

    source.schedule(deadline: .now() + .milliseconds(delayMs))
    source.setEventHandler {
        source.cancel()
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
        }
    }
    source.resume()

    return registerRuntimeObject(box)
}

// MARK: - kk_concurrent_schedule_period

/// Runtime backing for `Timer.schedule(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask`.
///
/// Schedules a repeating timer that fires first after `delayMs` milliseconds,
/// then every `periodMs` milliseconds until cancelled.
/// Returns an opaque `TimerTask` handle that can be cancelled.
///
/// - Parameters:
///   - timerRaw:   Opaque handle of the owning `java.util.Timer` (unused at runtime; included for ABI parity).
///   - delayMs:    Initial delay before first execution, in milliseconds.
///   - periodMs:   Interval between subsequent executions, in milliseconds.
///   - fnPtr:      Function pointer of the KK closure thunk for the action lambda.
///   - closureRaw: Closure environment pointer for the action lambda.
///   - outThrown:  Written to non-zero if the action throws a Kotlin exception.
/// - Returns: Opaque `TimerTask` handle (a `RuntimeTimerTaskBox`).
@_cdecl("kk_concurrent_schedule_period")
public func kk_concurrent_schedule_period(
    _ timerRaw: Int,
    _ delayMs: Int,
    _ periodMs: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_concurrent_schedule_period received nil fnPtr")
    }

    let source = DispatchSource.makeTimerSource(queue: .global())
    let box = RuntimeTimerTaskBox(source: source, fnPtr: fnPtr, closureRaw: closureRaw)

    source.schedule(
        deadline: .now() + .milliseconds(delayMs),
        repeating: .milliseconds(periodMs)
    )
    source.setEventHandler {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
        if thrown != 0 {
            source.cancel()
            outThrown?.pointee = thrown
        }
    }
    source.resume()

    return registerRuntimeObject(box)
}
