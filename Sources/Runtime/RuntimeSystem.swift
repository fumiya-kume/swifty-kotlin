import Dispatch
import Foundation

// MARK: - kotlin.system functions (STDLIB-131/132)

/// Runtime support for kotlin.system.exitProcess(status) (STDLIB-132).
@_cdecl("kk_system_exitProcess")
public func kk_system_exitProcess(_ status: Int) -> Int {
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
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
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
