import Dispatch
import Foundation

// MARK: - kotlin.system functions (STDLIB-131/132)

private let runtimeProcessStartNanos = DispatchTime.now().uptimeNanoseconds

/// Runtime support for kotlin.system.exitProcess(status) (STDLIB-132/657).
/// Returns `Never` because `exit()` never returns – matching Kotlin's `Nothing` semantics.
@_cdecl("kk_system_exitProcess")
public func kk_system_exitProcess(_ status: Int) -> Never {
    exit(Int32(status))
}

/// Runtime support for time measurement (STDLIB-131).
/// Returns current time in milliseconds since Unix epoch.
@_cdecl("kk_system_currentTimeMillis")
public func kk_system_currentTimeMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

/// Runtime support for monotonic nanosecond clock (STDLIB-550).
/// Returns monotonic uptime in nanoseconds (not wall-clock).
@_cdecl("kk_system_nanoTime")
public func kk_system_nanoTime() -> Int {
    // Int(clamping:) is acceptable here: on 64-bit targets Int.max is ~9.2e18,
    // which corresponds to ~292 years of uptime in nanoseconds. UInt64 uptime
    // values will not exceed Int.max under any realistic scenario, so clamping
    // is effectively a no-op. On hypothetical 32-bit targets this would saturate
    // at ~2.1 seconds, but the compiler only targets 64-bit macOS (LP64).
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}

/// Runtime support for exposing the monotonic process start timestamp.
@_cdecl("kk_system_process_start_nanos")
public func kk_system_process_start_nanos() -> Int {
    Int(clamping: runtimeProcessStartNanos)
}

// MARK: - measureTimeMillis / measureNanoTime (STDLIB-550)

/// Runtime support for kotlin.system.measureTimeMillis { block }.
/// Executes [block], measures elapsed monotonic time and returns it in milliseconds.
@_cdecl("kk_system_measureTimeMillis")
public func kk_system_measureTimeMillis(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    if let ot = outThrown, ot.pointee != 0 {
        return 0
    }
    let end = DispatchTime.now().uptimeNanoseconds
    return Int(clamping: (end - start) / 1_000_000)
}

/// Runtime support for kotlin.system.measureNanoTime { block }.
/// Executes [block], measures elapsed monotonic time and returns it in nanoseconds.
@_cdecl("kk_system_measureNanoTime")
public func kk_system_measureNanoTime(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    if let ot = outThrown, ot.pointee != 0 {
        return 0
    }
    let end = DispatchTime.now().uptimeNanoseconds
    return Int(clamping: end - start)
}
