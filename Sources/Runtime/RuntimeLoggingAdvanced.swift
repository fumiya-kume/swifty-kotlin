import Dispatch
import Foundation

// MARK: - Advanced Logging Runtime (STDLIB-LOG-148)
// File appender, rolling file appender, structured (JSON) logging,
// MDC (Mapped Diagnostic Context), package/class filter, async logging.

// MARK: - MDC (Mapped Diagnostic Context)

/// Per-thread key→value context storage for structured log enrichment.
final class RuntimeMDCBox: @unchecked Sendable {
    static let shared = RuntimeMDCBox()

    private let lock = NSLock()
    // keyed by (thread identifier, key)
    private var store: [ObjectIdentifier: [String: String]] = [:]

    func put(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(Thread.current)
        var map = store[id] ?? [:]
        map[key] = value
        store[id] = map
    }

    func get(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[ObjectIdentifier(Thread.current)]?[key]
    }

    func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(Thread.current)
        store[id]?[key] = nil
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        store[ObjectIdentifier(Thread.current)] = nil
    }

    func copyContext() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return store[ObjectIdentifier(Thread.current)] ?? [:]
    }
}

// MARK: - Log Level numeric rank

private func logLevelRank(_ level: String) -> Int {
    switch level.uppercased() {
    case "FINEST": return 0
    case "FINER": return 1
    case "FINE": return 2
    case "CONFIG": return 3
    case "INFO": return 4
    case "WARNING": return 5
    case "SEVERE": return 6
    default: return 4
    }
}

// MARK: - Appender protocol (internal)

protocol RuntimeAppender: AnyObject, Sendable {
    func append(record: RuntimeLogRecord)
}

struct RuntimeLogRecord {
    let timestamp: Date
    let level: String
    let loggerName: String
    let message: String
    let throwableMessage: String?
    let mdc: [String: String]
}

// MARK: - Console Appender

private final class RuntimeConsoleAppender: RuntimeAppender, @unchecked Sendable {
    func append(record: RuntimeLogRecord) {
        print(renderText(record))
    }

    private func renderText(_ r: RuntimeLogRecord) -> String {
        var line = "[\(r.level)] \(r.loggerName): \(r.message)"
        if let t = r.throwableMessage { line += " | \(t)" }
        return line
    }
}

// MARK: - File Appender

final class RuntimeFileAppenderBox: RuntimeAppender, @unchecked Sendable {
    private let lock = NSLock()
    let path: String

    init(path: String) {
        self.path = path
    }

    func append(record: RuntimeLogRecord) {
        let line = renderText(record) + "\n"
        lock.lock()
        defer { lock.unlock() }
        writeLineToFile(line, at: path)
    }

    fileprivate func renderText(_ r: RuntimeLogRecord) -> String {
        var line = "[\(r.level)] \(r.loggerName): \(r.message)"
        if let t = r.throwableMessage { line += " | \(t)" }
        return line
    }
}

private func writeLineToFile(_ line: String, at path: String) {
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Rolling File Appender

final class RuntimeRollingFileAppenderBox: RuntimeAppender, @unchecked Sendable {
    private let lock = NSLock()
    let basePath: String
    let maxBytes: Int64
    let maxFiles: Int

    private var currentSize: Int64 = 0
    private var generation: Int = 0

    init(basePath: String, maxBytes: Int64, maxFiles: Int) {
        self.basePath = basePath
        self.maxBytes = max(1, maxBytes)
        self.maxFiles = max(1, maxFiles)
        // measure existing file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: basePath),
           let size = attrs[.size] as? Int64
        {
            self.currentSize = size
        }
    }

    private func rolledPath(generation gen: Int) -> String {
        "\(basePath).\(gen)"
    }

    private func rotate() {
        // delete the oldest generation so the shift below can succeed
        let oldest = rolledPath(generation: maxFiles - 1)
        _ = try? FileManager.default.removeItem(atPath: oldest)
        // shift old generations
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let old = rolledPath(generation: i - 1)
            let new = rolledPath(generation: i)
            _ = try? FileManager.default.moveItem(atPath: old, toPath: new)
        }
        // rename current file to .0
        _ = try? FileManager.default.moveItem(atPath: basePath, toPath: rolledPath(generation: 0))
        currentSize = 0
        generation += 1
    }

    func append(record: RuntimeLogRecord) {
        let line = renderText(record) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        if currentSize + Int64(data.count) > maxBytes {
            rotate()
        }
        writeLineToFile(line, at: basePath)
        currentSize += Int64(data.count)
    }

    private func renderText(_ r: RuntimeLogRecord) -> String {
        var line = "[\(r.level)] \(r.loggerName): \(r.message)"
        if let t = r.throwableMessage { line += " | \(t)" }
        return line
    }
}

// MARK: - Structured (JSON) Appender

final class RuntimeStructuredAppenderBox: RuntimeAppender, @unchecked Sendable {
    private let lock = NSLock()
    let path: String?   // nil → stdout

    init(path: String?) {
        self.path = path
    }

    func append(record: RuntimeLogRecord) {
        let json = buildJSON(record)
        lock.lock()
        defer { lock.unlock() }
        if let p = path {
            writeLineToFile(json + "\n", at: p)
        } else {
            print(json)
        }
    }

    private func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func buildJSON(_ r: RuntimeLogRecord) -> String {
        var pairs: [String] = []
        let isoFormatter = ISO8601DateFormatter()
        pairs.append("\"timestamp\":\"\(jsonEscape(isoFormatter.string(from: r.timestamp)))\"")
        pairs.append("\"level\":\"\(jsonEscape(r.level))\"")
        pairs.append("\"logger\":\"\(jsonEscape(r.loggerName))\"")
        pairs.append("\"message\":\"\(jsonEscape(r.message))\"")
        if let t = r.throwableMessage {
            pairs.append("\"throwable\":\"\(jsonEscape(t))\"")
        }
        if !r.mdc.isEmpty {
            let mdcPairs = r.mdc
                .sorted { $0.key < $1.key }
                .map { "\"\(jsonEscape($0.key))\":\"\(jsonEscape($0.value))\"" }
                .joined(separator: ",")
            pairs.append("\"mdc\":{\(mdcPairs)}")
        }
        return "{\(pairs.joined(separator: ","))}"
    }
}

// MARK: - Async Appender

final class RuntimeAsyncAppenderBox: RuntimeAppender, @unchecked Sendable {
    private let queue: DispatchQueue
    private let delegate: RuntimeAppender

    init(delegate: RuntimeAppender, label: String = "kswiftk.async-log") {
        self.delegate = delegate
        self.queue = DispatchQueue(label: label, qos: .utility)
    }

    func append(record: RuntimeLogRecord) {
        queue.async { [delegate] in
            delegate.append(record: record)
        }
    }
}

// MARK: - Advanced Logger Box

final class RuntimeAdvancedLoggerBox {
    let name: String
    private let lock = NSLock()
    private var appenders: [RuntimeAppender] = []
    var minimumLevel: String = "INFO"
    var packageFilter: String? = nil   // optional prefix filter

    init(name: String) {
        self.name = name
    }

    func addAppender(_ appender: RuntimeAppender) {
        lock.lock()
        defer { lock.unlock() }
        appenders.append(appender)
    }

    func publish(level: String, message: String, throwableMessage: String?) {
        // package/class filter
        if let filter = packageFilter, !name.hasPrefix(filter) { return }
        // level filter
        guard logLevelRank(level) >= logLevelRank(minimumLevel) else { return }
        let record = RuntimeLogRecord(
            timestamp: Date(),
            level: level,
            loggerName: name,
            message: message,
            throwableMessage: throwableMessage,
            mdc: RuntimeMDCBox.shared.copyContext()
        )
        let snapshot: [RuntimeAppender] = lock.withLockAdvanced { appenders }
        if snapshot.isEmpty {
            print("[\(level)] \(name): \(message)\(throwableMessage.map { " | \($0)" } ?? "")")
        } else {
            for appender in snapshot {
                appender.append(record: record)
            }
        }
    }
}

private extension NSLock {
    @discardableResult
    func withLockAdvanced<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

// MARK: - Registry

final class RuntimeAdvancedLoggerRegistryBox: @unchecked Sendable {
    static let shared = RuntimeAdvancedLoggerRegistryBox()
    private let lock = NSLock()
    private var loggers: [String: Int] = [:]

    func loggerRaw(named name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[name] { return existing }
        let raw = registerRuntimeObject(RuntimeAdvancedLoggerBox(name: name))
        loggers[name] = raw
        return raw
    }
}

// MARK: - Pointer helpers

private func advancedLoggerBox(from raw: Int) -> RuntimeAdvancedLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeAdvancedLoggerBox.self)
}

private func fileAppenderBox(from raw: Int) -> RuntimeFileAppenderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileAppenderBox.self)
}

private func rollingFileAppenderBox(from raw: Int) -> RuntimeRollingFileAppenderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeRollingFileAppenderBox.self)
}

private func structuredAppenderBox(from raw: Int) -> RuntimeStructuredAppenderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeStructuredAppenderBox.self)
}

private func asyncAppenderBox(from raw: Int) -> RuntimeAsyncAppenderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeAsyncAppenderBox.self)
}

private func advancedLoggingString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func advancedLoggingOptionalString(from raw: Int) -> String? {
    guard raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else { return nil }
    return extractString(from: ptr)
}

private func advancedLoggingMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

// MARK: - Advanced Logger C API

@_cdecl("kk_adv_logger_get")
public func kk_adv_logger_get(_ nameRaw: Int) -> Int {
    RuntimeAdvancedLoggerRegistryBox.shared.loggerRaw(
        named: advancedLoggingString(from: nameRaw, caller: #function)
    )
}

@_cdecl("kk_adv_logger_set_level")
public func kk_adv_logger_set_level(_ loggerRaw: Int, _ levelRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_set_level received invalid Logger handle")
    }
    logger.minimumLevel = advancedLoggingString(from: levelRaw, caller: #function)
    return 0
}

@_cdecl("kk_adv_logger_set_filter")
public func kk_adv_logger_set_filter(_ loggerRaw: Int, _ prefixRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_set_filter received invalid Logger handle")
    }
    logger.packageFilter = advancedLoggingOptionalString(from: prefixRaw)
    return 0
}

@_cdecl("kk_adv_logger_log")
public func kk_adv_logger_log(_ loggerRaw: Int, _ levelRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_log received invalid Logger handle")
    }
    logger.publish(
        level: advancedLoggingString(from: levelRaw, caller: #function),
        message: advancedLoggingString(from: messageRaw, caller: #function),
        throwableMessage: nil
    )
    return 0
}

@_cdecl("kk_adv_logger_log_throwable")
public func kk_adv_logger_log_throwable(
    _ loggerRaw: Int,
    _ levelRaw: Int,
    _ messageRaw: Int,
    _ throwableRaw: Int
) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_log_throwable received invalid Logger handle")
    }
    var throwableMessage: String? = nil
    if throwableRaw != runtimeNullSentinelInt,
       let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
       let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    {
        throwableMessage = throwable.message
    }
    logger.publish(
        level: advancedLoggingString(from: levelRaw, caller: #function),
        message: advancedLoggingString(from: messageRaw, caller: #function),
        throwableMessage: throwableMessage
    )
    return 0
}

// MARK: - File Appender C API

@_cdecl("kk_file_appender_new")
public func kk_file_appender_new(_ pathRaw: Int) -> Int {
    let path = advancedLoggingString(from: pathRaw, caller: #function)
    return registerRuntimeObject(RuntimeFileAppenderBox(path: path))
}

@_cdecl("kk_adv_logger_add_file_appender")
public func kk_adv_logger_add_file_appender(_ loggerRaw: Int, _ appenderRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw),
          let appender = fileAppenderBox(from: appenderRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_add_file_appender received invalid handle")
    }
    logger.addAppender(appender)
    return 0
}

// MARK: - Rolling File Appender C API

@_cdecl("kk_rolling_appender_new")
public func kk_rolling_appender_new(_ pathRaw: Int, _ maxBytes: Int, _ maxFiles: Int) -> Int {
    let path = advancedLoggingString(from: pathRaw, caller: #function)
    return registerRuntimeObject(
        RuntimeRollingFileAppenderBox(basePath: path, maxBytes: Int64(maxBytes), maxFiles: maxFiles)
    )
}

@_cdecl("kk_adv_logger_add_rolling_appender")
public func kk_adv_logger_add_rolling_appender(_ loggerRaw: Int, _ appenderRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw),
          let appender = rollingFileAppenderBox(from: appenderRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_add_rolling_appender received invalid handle")
    }
    logger.addAppender(appender)
    return 0
}

// MARK: - Structured (JSON) Appender C API

/// pathRaw == runtimeNullSentinelInt → stdout
@_cdecl("kk_structured_appender_new")
public func kk_structured_appender_new(_ pathRaw: Int) -> Int {
    let path = advancedLoggingOptionalString(from: pathRaw)
    return registerRuntimeObject(RuntimeStructuredAppenderBox(path: path))
}

@_cdecl("kk_adv_logger_add_structured_appender")
public func kk_adv_logger_add_structured_appender(_ loggerRaw: Int, _ appenderRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw),
          let appender = structuredAppenderBox(from: appenderRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_add_structured_appender received invalid handle")
    }
    logger.addAppender(appender)
    return 0
}

// MARK: - Async Appender C API

/// Wraps an existing appender (file, rolling, structured) in an async queue.
@_cdecl("kk_async_appender_wrap_file")
public func kk_async_appender_wrap_file(_ appenderRaw: Int) -> Int {
    guard let appender = fileAppenderBox(from: appenderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_async_appender_wrap_file received invalid handle")
    }
    return registerRuntimeObject(RuntimeAsyncAppenderBox(delegate: appender))
}

@_cdecl("kk_async_appender_wrap_rolling")
public func kk_async_appender_wrap_rolling(_ appenderRaw: Int) -> Int {
    guard let appender = rollingFileAppenderBox(from: appenderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_async_appender_wrap_rolling received invalid handle")
    }
    return registerRuntimeObject(RuntimeAsyncAppenderBox(delegate: appender))
}

@_cdecl("kk_async_appender_wrap_structured")
public func kk_async_appender_wrap_structured(_ appenderRaw: Int) -> Int {
    guard let appender = structuredAppenderBox(from: appenderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_async_appender_wrap_structured received invalid handle")
    }
    return registerRuntimeObject(RuntimeAsyncAppenderBox(delegate: appender))
}

@_cdecl("kk_adv_logger_add_async_appender")
public func kk_adv_logger_add_async_appender(_ loggerRaw: Int, _ appenderRaw: Int) -> Int {
    guard let logger = advancedLoggerBox(from: loggerRaw),
          let appender = asyncAppenderBox(from: appenderRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_adv_logger_add_async_appender received invalid handle")
    }
    logger.addAppender(appender)
    return 0
}

// MARK: - MDC C API

@_cdecl("kk_mdc_put")
public func kk_mdc_put(_ keyRaw: Int, _ valueRaw: Int) -> Int {
    RuntimeMDCBox.shared.put(
        key: advancedLoggingString(from: keyRaw, caller: #function),
        value: advancedLoggingString(from: valueRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_mdc_get")
public func kk_mdc_get(_ keyRaw: Int) -> Int {
    let key = advancedLoggingString(from: keyRaw, caller: #function)
    guard let value = RuntimeMDCBox.shared.get(key: key) else {
        return runtimeNullSentinelInt
    }
    return advancedLoggingMakeStringRaw(value)
}

@_cdecl("kk_mdc_remove")
public func kk_mdc_remove(_ keyRaw: Int) -> Int {
    RuntimeMDCBox.shared.remove(key: advancedLoggingString(from: keyRaw, caller: #function))
    return 0
}

@_cdecl("kk_mdc_clear")
public func kk_mdc_clear() -> Int {
    RuntimeMDCBox.shared.clear()
    return 0
}
