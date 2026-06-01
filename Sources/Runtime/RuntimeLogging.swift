import Foundation

private func loggingString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

// MARK: - SLF4J-style Logger (TRACE/DEBUG/INFO/WARN/ERROR)

/// Thread-safe numeric log level ordering for SLF4J-compatible logger.
enum SLF4JLevel: Int, Comparable {
    case trace = 0
    case debug = 1
    case info  = 2
    case warn  = 3
    case error = 4

    var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        }
    }

    static func < (lhs: SLF4JLevel, rhs: SLF4JLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

final class SLF4JLoggerBox {
    let name: String
    var minimumLevel: SLF4JLevel = .trace

    init(name: String) {
        self.name = name
    }
}

final class SLF4JLoggerRegistryBox: @unchecked Sendable {
    static let shared = SLF4JLoggerRegistryBox()

    private let lock = NSLock()
    private var loggers: [String: Int] = [:]

    func loggerRaw(named name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[name] {
            return existing
        }
        let raw = registerRuntimeObject(SLF4JLoggerBox(name: name))
        loggers[name] = raw
        return raw
    }
}

private func slf4jLoggerBox(from raw: Int) -> SLF4JLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: SLF4JLoggerBox.self)
}

/// Replace `{}` placeholders in `pattern` with successive elements of `args`.
private func slf4jFormat(pattern: String, args: [String]) -> String {
    var result = ""
    result.reserveCapacity(pattern.count)
    var argIndex = 0
    var idx = pattern.startIndex
    while idx < pattern.endIndex {
        let next = pattern.index(after: idx)
        if pattern[idx] == "{", next < pattern.endIndex, pattern[next] == "}" {
            if argIndex < args.count {
                result.append(contentsOf: args[argIndex])
                argIndex += 1
            } else {
                result.append("{}")
            }
            idx = pattern.index(after: next)
        } else {
            result.append(pattern[idx])
            idx = next
        }
    }
    return result
}

private func publishSLF4J(logger: SLF4JLoggerBox, level: SLF4JLevel, message: String) {
    guard level >= logger.minimumLevel else { return }
    let line = "[\(level.label)] \(logger.name): \(message)"
    if level >= .warn {
        var standardError = FileHandle.standardError
        print(line, to: &standardError)
    } else {
        print(line)
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.write(data)
        }
    }
}

// MARK: - LoggerFactory C entry points

@_cdecl("kk_slf4j_logger_get")
public func kk_slf4j_logger_get(_ nameRaw: Int) -> Int {
    SLF4JLoggerRegistryBox.shared.loggerRaw(
        named: loggingString(from: nameRaw, caller: #function)
    )
}

// MARK: - Log-level entry points

@_cdecl("kk_slf4j_log_trace")
public func kk_slf4j_log_trace(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .trace,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_debug")
public func kk_slf4j_log_debug(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .debug,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_info")
public func kk_slf4j_log_info(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .info,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_warn")
public func kk_slf4j_log_warn(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .warn,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_error")
public func kk_slf4j_log_error(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .error,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

// MARK: - Format helpers (SLF4J {} placeholder substitution)

/// Format a log message with one `{}` argument and log at the requested level.
@_cdecl("kk_slf4j_log_trace_1")
public func kk_slf4j_log_trace_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .trace, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_debug_1")
public func kk_slf4j_log_debug_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .debug, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_info_1")
public func kk_slf4j_log_info_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .info, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_warn_1")
public func kk_slf4j_log_warn_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .warn, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_error_1")
public func kk_slf4j_log_error_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .error, message: message)
    return 0
}

/// Format a log message with two `{}` arguments.
@_cdecl("kk_slf4j_log_info_2")
public func kk_slf4j_log_info_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .info, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_warn_2")
public func kk_slf4j_log_warn_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .warn, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_error_2")
public func kk_slf4j_log_error_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .error, message: message)
    return 0
}

// MARK: - Minimum-level control

@_cdecl("kk_slf4j_set_level")
public func kk_slf4j_set_level(_ loggerRaw: Int, _ levelRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    switch levelRaw {
    case 0: logger.minimumLevel = .trace
    case 1: logger.minimumLevel = .debug
    case 2: logger.minimumLevel = .info
    case 3: logger.minimumLevel = .warn
    case 4: logger.minimumLevel = .error
    default: break
    }
    return 0
}

@_cdecl("kk_slf4j_is_trace_enabled")
public func kk_slf4j_is_trace_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .trace ? 1 : 0
}

@_cdecl("kk_slf4j_is_debug_enabled")
public func kk_slf4j_is_debug_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .debug ? 1 : 0
}

@_cdecl("kk_slf4j_is_info_enabled")
public func kk_slf4j_is_info_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .info ? 1 : 0
}

@_cdecl("kk_slf4j_is_warn_enabled")
public func kk_slf4j_is_warn_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .warn ? 1 : 0
}

@_cdecl("kk_slf4j_is_error_enabled")
public func kk_slf4j_is_error_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .error ? 1 : 0
}
