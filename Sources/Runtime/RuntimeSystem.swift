import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - kotlin.system functions (STDLIB-131/132, STDLIB-TIME-085)

private let runtimeProcessStartNanos = runtimeComputeProcessStartNanos()

private func runtimeComputeProcessStartNanos() -> UInt64 {
#if canImport(Darwin)
    var processInfo = proc_bsdinfo()
    let infoSize = MemoryLayout<proc_bsdinfo>.size
    let readSize = withUnsafeMutablePointer(to: &processInfo) { infoPtr in
        proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, infoPtr, Int32(infoSize))
    }

    guard Int(readSize) == infoSize else {
        return DispatchTime.now().uptimeNanoseconds
    }

    let startEpochNanos = processInfo.pbi_start_tvsec &* 1_000_000_000
        &+ processInfo.pbi_start_tvusec &* 1_000
    let nowEpochNanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    let nowUptimeNanos = DispatchTime.now().uptimeNanoseconds

    guard nowEpochNanos >= startEpochNanos else {
        return nowUptimeNanos
    }

    let elapsedNanos = nowEpochNanos - startEpochNanos
    guard nowUptimeNanos >= elapsedNanos else {
        return 0
    }
    return nowUptimeNanos - elapsedNanos
#else
    return DispatchTime.now().uptimeNanoseconds
#endif
}

/// Runtime support for kotlin.system.exitProcess(status) (STDLIB-132/657).
/// Returns `Never` because `exit()` never returns – matching Kotlin's `Nothing` semantics.
@_cdecl("kk_system_exitProcess")
public func kk_system_exitProcess(_ status: Int) -> Never {
    exit(Int32(status))
}

/// Runtime support for time measurement (STDLIB-131, STDLIB-TIME-085).
/// Returns current time in milliseconds since Unix epoch.
/// Precision: millisecond.  Resolution: depends on the host OS wall-clock
/// (typically sub-millisecond on macOS).  Uses `Date()` which reads the
/// system real-time clock – **not monotonic** and may jump on NTP
/// adjustments.
@_cdecl("kk_system_currentTimeMillis")
public func kk_system_currentTimeMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

/// Runtime support for monotonic nanosecond clock (STDLIB-550, STDLIB-TIME-085).
/// Returns monotonic uptime in nanoseconds (not wall-clock).
///
/// Monotonic guarantee: backed by `DispatchTime.now().uptimeNanoseconds`
/// which uses `mach_absolute_time` on macOS – guaranteed never to go
/// backwards and unaffected by NTP or manual clock changes.
///
/// Precision: nanosecond.  Resolution: hardware-dependent, typically
/// ≤100 ns on Apple Silicon / ≤1 µs on Intel Macs.
@_cdecl("kk_system_nanoTime")
public func kk_system_nanoTime() -> Int {
    // Int(clamping:) is acceptable here: on 64-bit targets Int.max is ~9.2e18,
    // which corresponds to ~292 years of uptime in nanoseconds. UInt64 uptime
    // values will not exceed Int.max under any realistic scenario, so clamping
    // is effectively a no-op. On hypothetical 32-bit targets this would saturate
    // at ~2.1 seconds, but the compiler only targets 64-bit macOS (LP64).
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}

// MARK: - processStartNanos (STDLIB-TIME-085)

/// Captured once at process startup: the monotonic nanosecond timestamp
/// at which the runtime was first initialised.  Because Swift top-level
/// `let` initialisers are thread-safe and execute exactly once (dispatch_once
/// semantics), this value is immutable after first access and safe to read
/// from any thread.
private let processStartNanosValue: Int = {
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}()

/// Returns the monotonic nanosecond timestamp captured at process start.
///
/// Kotlin: `System.processStartNanos`
///
/// This is useful for computing elapsed time since program start without
/// needing to manually record a start time.  The value is monotonic and
/// uses the same clock source as `nanoTime()`.
@_cdecl("kk_system_process_start_nanos")
public func kk_system_process_start_nanos() -> Int {
    processStartNanosValue
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
