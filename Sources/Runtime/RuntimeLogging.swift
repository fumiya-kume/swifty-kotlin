import Foundation

final class RuntimeLoggerBox {
    let name: String
    var handlers: [Int] = []

    init(name: String) {
        self.name = name
    }
}

enum RuntimeLogHandlerKind {
    case console
    case file(path: String)
}

final class RuntimeLogHandlerBox {
    let kind: RuntimeLogHandlerKind

    init(kind: RuntimeLogHandlerKind) {
        self.kind = kind
    }
}

private func runtimeLoggerBox(from raw: Int) -> RuntimeLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLoggerBox.self)
}

private func runtimeLogHandlerBox(from raw: Int) -> RuntimeLogHandlerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLogHandlerBox.self)
}

private func loggingString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func loggingMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

private func renderLogLine(level: String, loggerName: String, message: String) -> String {
    "[\(level)] \(loggerName): \(message)"
}

private func publishLog(_ logger: RuntimeLoggerBox, level: String, message: String) {
    let line = renderLogLine(level: level, loggerName: logger.name, message: message)
    if logger.handlers.isEmpty {
        print(line)
        return
    }
    for handlerRaw in logger.handlers {
        guard let handler = runtimeLogHandlerBox(from: handlerRaw) else { continue }
        switch handler.kind {
        case .console:
            print(line)
        case let .file(path):
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    if let data = (line + "\n").data(using: .utf8) {
                        try? handle.write(contentsOf: data)
                    }
                    try? handle.close()
                }
            } else {
                try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

@_cdecl("kk_logger_getLogger")
public func kk_logger_getLogger(_ nameRaw: Int) -> Int {
    registerRuntimeObject(RuntimeLoggerBox(name: loggingString(from: nameRaw, caller: #function)))
}

@_cdecl("kk_logging_level_info")
public func kk_logging_level_info() -> Int { loggingMakeStringRaw("INFO") }

@_cdecl("kk_logging_level_warning")
public func kk_logging_level_warning() -> Int { loggingMakeStringRaw("WARNING") }

@_cdecl("kk_logging_level_severe")
public func kk_logging_level_severe() -> Int { loggingMakeStringRaw("SEVERE") }

@_cdecl("kk_console_handler_new")
public func kk_console_handler_new() -> Int {
    registerRuntimeObject(RuntimeLogHandlerBox(kind: .console))
}

@_cdecl("kk_file_handler_new")
public func kk_file_handler_new(_ pathRaw: Int) -> Int {
    registerRuntimeObject(RuntimeLogHandlerBox(kind: .file(path: loggingString(from: pathRaw, caller: #function))))
}

@_cdecl("kk_logger_addHandler")
public func kk_logger_addHandler(_ loggerRaw: Int, _ handlerRaw: Int) -> Int {
    guard let logger = runtimeLoggerBox(from: loggerRaw),
          runtimeLogHandlerBox(from: handlerRaw) != nil
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_logger_addHandler received invalid handle")
    }
    logger.handlers.append(handlerRaw)
    return 0
}

@_cdecl("kk_logger_log")
public func kk_logger_log(_ loggerRaw: Int, _ levelRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = runtimeLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_logger_log received invalid Logger handle")
    }
    publishLog(logger, level: loggingString(from: levelRaw, caller: #function), message: loggingString(from: messageRaw, caller: #function))
    return 0
}

@_cdecl("kk_logger_info")
public func kk_logger_info(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_info(), messageRaw)
}

@_cdecl("kk_logger_warning")
public func kk_logger_warning(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_warning(), messageRaw)
}

@_cdecl("kk_logger_severe")
public func kk_logger_severe(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_severe(), messageRaw)
}
