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
