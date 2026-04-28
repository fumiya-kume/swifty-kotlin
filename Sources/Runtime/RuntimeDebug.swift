import Foundation

private let runtimeAssertionStateLock = NSLock()
private nonisolated(unsafe) var runtimeAssertionsEnabled = runtimeInitialAssertionsEnabled()

private func runtimeInitialAssertionsEnabled() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    for key in ["KK_ASSERTIONS_ENABLED", "KOTLIN_ASSERTIONS_ENABLED"] {
        guard let rawValue = environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawValue.isEmpty
        else {
            continue
        }
        switch rawValue {
        case "0", "false", "no", "off":
            return false
        case "1", "true", "yes", "on":
            return true
        default:
            continue
        }
    }
    return true
}

func runtimeAreAssertionsEnabled() -> Bool {
    runtimeAssertionStateLock.lock()
    defer { runtimeAssertionStateLock.unlock() }
    return runtimeAssertionsEnabled
}

func runtimeSetAssertionsEnabled(_ enabled: Bool) {
    runtimeAssertionStateLock.lock()
    runtimeAssertionsEnabled = enabled
    runtimeAssertionStateLock.unlock()
}

func runtimeResetDebugState() {
    runtimeSetAssertionsEnabled(runtimeInitialAssertionsEnabled())
}

@_cdecl("kk_assertions_enabled")
public func kk_assertions_enabled() -> Int {
    runtimeAreAssertionsEnabled() ? 1 : 0
}

@_cdecl("kk_assertions_set_enabled")
public func kk_assertions_set_enabled(_ enabled: Int) -> Int {
    runtimeSetAssertionsEnabled(enabled != 0)
    return 0
}

@_cdecl("kk_assertions_reset")
public func kk_assertions_reset() -> Int {
    runtimeResetDebugState()
    return 0
}
