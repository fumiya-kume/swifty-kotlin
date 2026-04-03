import Foundation

final class RuntimeKSPLoggerBox {
    var messages: [String] = []
}

final class RuntimeKSPResolverBox {
    var files: [String] = []
    var symbols: [String] = []
    var annotatedSymbols: [String: [String]] = [:]
}

final class RuntimeKSPCodeGeneratorBox {
    var generatedFiles: [String] = []
    var fileContents: [String: String] = [:]
}

final class RuntimeKSPRegistryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var registeredProcessors: [String] = []

    func register(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        runtimeKSPAppendUnique(name, to: &registeredProcessors)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return registeredProcessors
    }
}

private let runtimeKSPRegistry = RuntimeKSPRegistryBox()

private func runtimeKSPString(from raw: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: ptr)
}

private func runtimeKSPStringRaw(_ value: String) -> Int {
    let utf8 = Array(value.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}

private func runtimeKSPLogger(from raw: Int) -> RuntimeKSPLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKSPLoggerBox.self)
}

private func runtimeKSPResolver(from raw: Int) -> RuntimeKSPResolverBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKSPResolverBox.self)
}

private func runtimeKSPCodeGenerator(from raw: Int) -> RuntimeKSPCodeGeneratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKSPCodeGeneratorBox.self)
}

private func runtimeKSPStringListRaw(_ values: [String]) -> Int {
    let raws = values.map(runtimeKSPStringRaw)
    return registerRuntimeObject(RuntimeListBox(elements: raws))
}

private func runtimeKSPAppendUnique(_ value: String, to values: inout [String]) {
    guard !values.contains(value) else { return }
    values.append(value)
}

@_cdecl("kk_ksp_logger_new")
public func kk_ksp_logger_new() -> Int {
    registerRuntimeObject(RuntimeKSPLoggerBox())
}

private func runtimeKSPLog(_ loggerRaw: Int, level: String, messageRaw: Int) -> Int {
    guard let logger = runtimeKSPLogger(from: loggerRaw),
          let message = runtimeKSPString(from: messageRaw)
    else {
        return 0
    }
    logger.messages.append("\(level):\(message)")
    return 0
}

@_cdecl("kk_ksp_logger_info")
public func kk_ksp_logger_info(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    runtimeKSPLog(loggerRaw, level: "INFO", messageRaw: messageRaw)
}

@_cdecl("kk_ksp_logger_warn")
public func kk_ksp_logger_warn(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    runtimeKSPLog(loggerRaw, level: "WARN", messageRaw: messageRaw)
}

@_cdecl("kk_ksp_logger_error")
public func kk_ksp_logger_error(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    runtimeKSPLog(loggerRaw, level: "ERROR", messageRaw: messageRaw)
}

@_cdecl("kk_ksp_logger_messages")
public func kk_ksp_logger_messages(_ loggerRaw: Int) -> Int {
    guard let logger = runtimeKSPLogger(from: loggerRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKSPStringListRaw(logger.messages)
}

@_cdecl("kk_ksp_resolver_new")
public func kk_ksp_resolver_new() -> Int {
    registerRuntimeObject(RuntimeKSPResolverBox())
}

@_cdecl("kk_ksp_resolver_add_file")
public func kk_ksp_resolver_add_file(_ resolverRaw: Int, _ fileNameRaw: Int) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw),
          let fileName = runtimeKSPString(from: fileNameRaw)
    else {
        return 0
    }
    runtimeKSPAppendUnique(fileName, to: &resolver.files)
    return 0
}

@_cdecl("kk_ksp_resolver_add_symbol")
public func kk_ksp_resolver_add_symbol(_ resolverRaw: Int, _ symbolNameRaw: Int) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw),
          let symbolName = runtimeKSPString(from: symbolNameRaw)
    else {
        return 0
    }
    runtimeKSPAppendUnique(symbolName, to: &resolver.symbols)
    return 0
}

@_cdecl("kk_ksp_resolver_add_annotated_symbol")
public func kk_ksp_resolver_add_annotated_symbol(
    _ resolverRaw: Int,
    _ annotationNameRaw: Int,
    _ symbolNameRaw: Int
) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw),
          let annotationName = runtimeKSPString(from: annotationNameRaw),
          let symbolName = runtimeKSPString(from: symbolNameRaw)
    else {
        return 0
    }
    runtimeKSPAppendUnique(symbolName, to: &resolver.symbols)
    var existing = resolver.annotatedSymbols[annotationName] ?? []
    runtimeKSPAppendUnique(symbolName, to: &existing)
    resolver.annotatedSymbols[annotationName] = existing
    return 0
}

@_cdecl("kk_ksp_resolver_get_all_files")
public func kk_ksp_resolver_get_all_files(_ resolverRaw: Int) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKSPStringListRaw(resolver.files)
}

@_cdecl("kk_ksp_resolver_get_all_symbols")
public func kk_ksp_resolver_get_all_symbols(_ resolverRaw: Int) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKSPStringListRaw(resolver.symbols)
}

@_cdecl("kk_ksp_resolver_get_symbols_with_annotation")
public func kk_ksp_resolver_get_symbols_with_annotation(_ resolverRaw: Int, _ annotationNameRaw: Int) -> Int {
    guard let resolver = runtimeKSPResolver(from: resolverRaw),
          let annotationName = runtimeKSPString(from: annotationNameRaw)
    else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKSPStringListRaw(resolver.annotatedSymbols[annotationName] ?? [])
}

@_cdecl("kk_ksp_codegen_new")
public func kk_ksp_codegen_new() -> Int {
    registerRuntimeObject(RuntimeKSPCodeGeneratorBox())
}

@_cdecl("kk_ksp_codegen_create_file")
public func kk_ksp_codegen_create_file(
    _ codeGeneratorRaw: Int,
    _ packageNameRaw: Int,
    _ fileNameRaw: Int,
    _ contentsRaw: Int
) -> Int {
    guard let codeGenerator = runtimeKSPCodeGenerator(from: codeGeneratorRaw),
          let packageName = runtimeKSPString(from: packageNameRaw),
          let fileName = runtimeKSPString(from: fileNameRaw),
          let contents = runtimeKSPString(from: contentsRaw)
    else {
        return 0
    }
    let qualifiedName = packageName.isEmpty ? fileName : "\(packageName).\(fileName)"
    runtimeKSPAppendUnique(qualifiedName, to: &codeGenerator.generatedFiles)
    codeGenerator.fileContents[qualifiedName] = contents
    return 0
}

@_cdecl("kk_ksp_codegen_generated_files")
public func kk_ksp_codegen_generated_files(_ codeGeneratorRaw: Int) -> Int {
    guard let codeGenerator = runtimeKSPCodeGenerator(from: codeGeneratorRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKSPStringListRaw(codeGenerator.generatedFiles)
}

@_cdecl("kk_ksp_register_processor")
public func kk_ksp_register_processor(_ nameRaw: Int) -> Int {
    guard let name = runtimeKSPString(from: nameRaw) else {
        return 0
    }
    runtimeKSPRegistry.register(name)
    return 0
}

@_cdecl("kk_ksp_registered_processors")
public func kk_ksp_registered_processors() -> Int {
    runtimeKSPStringListRaw(runtimeKSPRegistry.snapshot())
}

@_cdecl("kk_ksp_run_processors")
public func kk_ksp_run_processors(_ loggerRaw: Int, _ resolverRaw: Int, _ codeGeneratorRaw: Int) -> Int {
    let names = runtimeKSPRegistry.snapshot()

    if let logger = runtimeKSPLogger(from: loggerRaw) {
        for name in names {
            let symbolCount = runtimeKSPResolver(from: resolverRaw)?.symbols.count ?? 0
            let generatedCount = runtimeKSPCodeGenerator(from: codeGeneratorRaw)?.generatedFiles.count ?? 0
            logger.messages.append("INFO:run:\(name):symbols=\(symbolCount):generated=\(generatedCount)")
        }
    }

    return runtimeKSPStringListRaw(names)
}
