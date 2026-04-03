import Foundation

public enum RuntimeCompilerPluginExtensionKind: String, CaseIterable, Sendable {
    case commandProcessor = "command-processor"
    case extensionRegistrar = "extension-registrar"
    case irGeneration = "ir-generation"
    case classBuilderInterceptor = "class-builder-interceptor"
}

public struct RuntimeCompilerPluginExtensionRecord: Equatable, Sendable {
    public let name: String
    public let kind: RuntimeCompilerPluginExtensionKind

    public init(name: String, kind: RuntimeCompilerPluginExtensionKind) {
        self.name = name
        self.kind = kind
    }
}

public struct RuntimeCompilerPluginMetadataEntry: Equatable, Sendable {
    public let pluginID: String
    public var displayName: String
    public var version: String
    public var commandProcessorName: String?
    public var registrarName: String?
    public var registeredExtensions: [RuntimeCompilerPluginExtensionRecord]
    public var options: [String: String]
    public var generatedModules: [String]
    public var interceptedClasses: [String]

    public init(
        pluginID: String,
        displayName: String,
        version: String,
        commandProcessorName: String? = nil,
        registrarName: String? = nil,
        registeredExtensions: [RuntimeCompilerPluginExtensionRecord] = [],
        options: [String: String] = [:],
        generatedModules: [String] = [],
        interceptedClasses: [String] = []
    ) {
        self.pluginID = pluginID
        self.displayName = displayName
        self.version = version
        self.commandProcessorName = commandProcessorName
        self.registrarName = registrarName
        self.registeredExtensions = registeredExtensions
        self.options = options
        self.generatedModules = generatedModules
        self.interceptedClasses = interceptedClasses
    }
}

final class RuntimeCompilerPluginRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: RuntimeCompilerPluginMetadataEntry] = [:]

    func register(pluginID: String, displayName: String, version: String) -> RuntimeCompilerPluginMetadataEntry {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[pluginID] ?? RuntimeCompilerPluginMetadataEntry(
            pluginID: pluginID,
            displayName: displayName,
            version: version
        )
        entry.displayName = displayName
        entry.version = version
        entries[pluginID] = entry
        return entry
    }

    func lookup(pluginID: String) -> RuntimeCompilerPluginMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[pluginID]
    }

    func update(pluginID: String, _ body: (inout RuntimeCompilerPluginMetadataEntry) -> Void) -> RuntimeCompilerPluginMetadataEntry {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[pluginID] ?? RuntimeCompilerPluginMetadataEntry(
            pluginID: pluginID,
            displayName: pluginID,
            version: ""
        )
        body(&entry)
        entries[pluginID] = entry
        return entry
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: false)
    }
}

let runtimeCompilerPluginRegistry = RuntimeCompilerPluginRegistry()

final class RuntimeCompilerPluginMetadataBox {
    let pluginID: String

    init(pluginID: String) {
        self.pluginID = pluginID
    }
}

final class RuntimeCommandProcessorBox {
    let pluginID: String
    let name: String
    let acceptedOptions: [String]

    init(pluginID: String, name: String, acceptedOptions: [String]) {
        self.pluginID = pluginID
        self.name = name
        self.acceptedOptions = acceptedOptions
    }

    func process(arguments: [String]) -> Int {
        var processed = 0
        for argument in arguments {
            guard let parsed = parse(argument: argument) else {
                continue
            }
            guard acceptsOption(named: parsed.key) else {
                continue
            }
            processed += 1
            _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
                entry.commandProcessorName = name
                entry.options[parsed.key] = parsed.value
            }
        }
        return processed
    }

    private func acceptsOption(named option: String) -> Bool {
        guard !acceptedOptions.isEmpty else { return true }
        return acceptedOptions.contains(where: { accepted in
            option == accepted || option.hasPrefix(accepted + ".")
        })
    }

    private func parse(argument: String) -> (key: String, value: String)? {
        var candidate = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if candidate.hasPrefix("-P ") {
            candidate.removeFirst(3)
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if candidate.hasPrefix("plugin:") {
            let components = candidate.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard components.count == 3, String(components[1]) == pluginID else {
                return nil
            }
            return splitKeyValue(String(components[2]))
        }

        return splitKeyValue(candidate)
    }

    private func splitKeyValue(_ source: String) -> (key: String, value: String)? {
        guard !source.isEmpty else { return nil }
        if let separator = source.firstIndex(of: "=") {
            let key = String(source[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(source[source.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return (key, value)
        }
        return (source, "true")
    }
}

final class RuntimeExtensionRegistrarBox {
    let pluginID: String
    let name: String

    init(pluginID: String, name: String) {
        self.pluginID = pluginID
        self.name = name
    }

    func registerExtension(name extensionName: String, kind: RuntimeCompilerPluginExtensionKind) {
        _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
            entry.registrarName = name
            if !entry.registeredExtensions.contains(where: { $0.name == extensionName && $0.kind == kind }) {
                entry.registeredExtensions.append(.init(name: extensionName, kind: kind))
            }
        }
    }
}

final class RuntimeIrGenerationExtensionBox {
    let pluginID: String
    let name: String

    init(pluginID: String, name: String) {
        self.pluginID = pluginID
        self.name = name
    }

    func generate(for moduleName: String) {
        _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
            if !entry.registeredExtensions.contains(where: { $0.name == name && $0.kind == .irGeneration }) {
                entry.registeredExtensions.append(.init(name: name, kind: .irGeneration))
            }
            entry.generatedModules.append(moduleName)
        }
    }
}

final class RuntimeClassBuilderInterceptorBox {
    let pluginID: String
    let name: String

    init(pluginID: String, name: String) {
        self.pluginID = pluginID
        self.name = name
    }

    func intercept(className: String) {
        _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
            if !entry.registeredExtensions.contains(where: { $0.name == name && $0.kind == .classBuilderInterceptor }) {
                entry.registeredExtensions.append(.init(name: name, kind: .classBuilderInterceptor))
            }
            entry.interceptedClasses.append(className)
        }
    }
}

private func runtimeCompilerPluginString(_ raw: Int) -> String? {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
}

private func runtimeCompilerPluginStringOrDefault(_ raw: Int, default defaultValue: String) -> String {
    runtimeCompilerPluginString(raw) ?? defaultValue
}

private func runtimeCompilerPluginStringList(_ raw: Int) -> [String] {
    guard raw != 0,
          raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeStorage.withLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let list = tryCast(ptr, to: RuntimeListBox.self)
    else {
        return []
    }
    return list.elements.compactMap { runtimeCompilerPluginString($0) }
}

private func runtimeCompilerPluginObject<T: AnyObject>(_ raw: Int, as _: T.Type) -> T? {
    guard raw != 0,
          raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeStorage.withLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: T.self)
}

private func runtimeCompilerPluginMetadata(from raw: Int) -> RuntimeCompilerPluginMetadataEntry? {
    guard let box = runtimeCompilerPluginObject(raw, as: RuntimeCompilerPluginMetadataBox.self) else {
        return nil
    }
    return runtimeCompilerPluginRegistry.lookup(pluginID: box.pluginID)
}

private func runtimeCompilerPluginMetadataHandle(pluginID: String) -> Int {
    registerRuntimeObject(RuntimeCompilerPluginMetadataBox(pluginID: pluginID))
}

private func runtimeCompilerPluginStringHandle(_ value: String) -> Int {
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

private func runtimeCompilerPluginListHandle(_ values: [String]) -> Int {
    registerRuntimeObject(RuntimeListBox(elements: values.map(runtimeCompilerPluginStringHandle)))
}

@_cdecl("kk_compiler_plugin_register")
public func kk_compiler_plugin_register(
    _ pluginIDRaw: Int,
    _ displayNameRaw: Int,
    _ versionRaw: Int
) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "anonymous-plugin")
    let displayName = runtimeCompilerPluginStringOrDefault(displayNameRaw, default: pluginID)
    let version = runtimeCompilerPluginStringOrDefault(versionRaw, default: "")
    _ = runtimeCompilerPluginRegistry.register(pluginID: pluginID, displayName: displayName, version: version)
    return runtimeCompilerPluginMetadataHandle(pluginID: pluginID)
}

@_cdecl("kk_compiler_plugin_metadata_lookup")
public func kk_compiler_plugin_metadata_lookup(_ pluginIDRaw: Int) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "")
    guard !pluginID.isEmpty,
          runtimeCompilerPluginRegistry.lookup(pluginID: pluginID) != nil
    else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginMetadataHandle(pluginID: pluginID)
}

@_cdecl("kk_compiler_plugin_metadata_get_plugin_id")
public func kk_compiler_plugin_metadata_get_plugin_id(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginStringHandle(metadata.pluginID)
}

@_cdecl("kk_compiler_plugin_metadata_get_display_name")
public func kk_compiler_plugin_metadata_get_display_name(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginStringHandle(metadata.displayName)
}

@_cdecl("kk_compiler_plugin_metadata_get_version")
public func kk_compiler_plugin_metadata_get_version(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginStringHandle(metadata.version)
}

@_cdecl("kk_compiler_plugin_metadata_get_command_processor_name")
public func kk_compiler_plugin_metadata_get_command_processor_name(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw),
          let name = metadata.commandProcessorName
    else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginStringHandle(name)
}

@_cdecl("kk_compiler_plugin_metadata_get_registrar_name")
public func kk_compiler_plugin_metadata_get_registrar_name(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw),
          let name = metadata.registrarName
    else {
        return runtimeNullSentinelInt
    }
    return runtimeCompilerPluginStringHandle(name)
}

@_cdecl("kk_compiler_plugin_metadata_get_extensions")
public func kk_compiler_plugin_metadata_get_extensions(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeCompilerPluginListHandle(metadata.registeredExtensions.map { "\($0.kind.rawValue):\($0.name)" })
}

@_cdecl("kk_compiler_plugin_metadata_get_options")
public func kk_compiler_plugin_metadata_get_options(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let values = metadata.options.keys.sorted().map { key in
        "\(key)=\(metadata.options[key] ?? "")"
    }
    return runtimeCompilerPluginListHandle(values)
}

@_cdecl("kk_compiler_plugin_metadata_get_generated_modules")
public func kk_compiler_plugin_metadata_get_generated_modules(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeCompilerPluginListHandle(metadata.generatedModules)
}

@_cdecl("kk_compiler_plugin_metadata_get_intercepted_classes")
public func kk_compiler_plugin_metadata_get_intercepted_classes(_ metadataRaw: Int) -> Int {
    guard let metadata = runtimeCompilerPluginMetadata(from: metadataRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeCompilerPluginListHandle(metadata.interceptedClasses)
}

@_cdecl("kk_command_processor_create")
public func kk_command_processor_create(
    _ pluginIDRaw: Int,
    _ nameRaw: Int,
    _ acceptedOptionsRaw: Int
) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "anonymous-plugin")
    let name = runtimeCompilerPluginStringOrDefault(nameRaw, default: "CommandProcessor")
    let acceptedOptions = runtimeCompilerPluginStringList(acceptedOptionsRaw)
    _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
        entry.commandProcessorName = name
    }
    return registerRuntimeObject(RuntimeCommandProcessorBox(
        pluginID: pluginID,
        name: name,
        acceptedOptions: acceptedOptions
    ))
}

@_cdecl("kk_command_processor_process")
public func kk_command_processor_process(_ processorRaw: Int, _ argumentsRaw: Int) -> Int {
    guard let processor = runtimeCompilerPluginObject(processorRaw, as: RuntimeCommandProcessorBox.self) else {
        return 0
    }
    return processor.process(arguments: runtimeCompilerPluginStringList(argumentsRaw))
}

@_cdecl("kk_extension_registrar_create")
public func kk_extension_registrar_create(_ pluginIDRaw: Int, _ nameRaw: Int) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "anonymous-plugin")
    let name = runtimeCompilerPluginStringOrDefault(nameRaw, default: "ExtensionRegistrar")
    _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
        entry.registrarName = name
    }
    return registerRuntimeObject(RuntimeExtensionRegistrarBox(pluginID: pluginID, name: name))
}

@_cdecl("kk_extension_registrar_register_extension")
public func kk_extension_registrar_register_extension(
    _ registrarRaw: Int,
    _ extensionNameRaw: Int,
    _ kindRaw: Int
) -> Int {
    guard let registrar = runtimeCompilerPluginObject(registrarRaw, as: RuntimeExtensionRegistrarBox.self) else {
        return -1
    }
    let extensionName = runtimeCompilerPluginStringOrDefault(extensionNameRaw, default: "")
    guard !extensionName.isEmpty else {
        return -1
    }
    guard let kind = RuntimeCompilerPluginExtensionKind.allCases[safe: kindRaw] else {
        return -1
    }
    registrar.registerExtension(name: extensionName, kind: kind)
    return 0
}

@_cdecl("kk_ir_generation_extension_create")
public func kk_ir_generation_extension_create(_ pluginIDRaw: Int, _ nameRaw: Int) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "anonymous-plugin")
    let name = runtimeCompilerPluginStringOrDefault(nameRaw, default: "IrGenerationExtension")
    _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
        if !entry.registeredExtensions.contains(where: { $0.name == name && $0.kind == .irGeneration }) {
            entry.registeredExtensions.append(.init(name: name, kind: .irGeneration))
        }
    }
    return registerRuntimeObject(RuntimeIrGenerationExtensionBox(pluginID: pluginID, name: name))
}

@_cdecl("kk_ir_generation_extension_generate")
public func kk_ir_generation_extension_generate(_ extensionRaw: Int, _ moduleNameRaw: Int) -> Int {
    guard let irExtension = runtimeCompilerPluginObject(extensionRaw, as: RuntimeIrGenerationExtensionBox.self) else {
        return -1
    }
    let moduleName = runtimeCompilerPluginStringOrDefault(moduleNameRaw, default: "")
    guard !moduleName.isEmpty else {
        return -1
    }
    irExtension.generate(for: moduleName)
    return 0
}

@_cdecl("kk_class_builder_interceptor_create")
public func kk_class_builder_interceptor_create(_ pluginIDRaw: Int, _ nameRaw: Int) -> Int {
    let pluginID = runtimeCompilerPluginStringOrDefault(pluginIDRaw, default: "anonymous-plugin")
    let name = runtimeCompilerPluginStringOrDefault(nameRaw, default: "ClassBuilderInterceptor")
    _ = runtimeCompilerPluginRegistry.update(pluginID: pluginID) { entry in
        if !entry.registeredExtensions.contains(where: { $0.name == name && $0.kind == .classBuilderInterceptor }) {
            entry.registeredExtensions.append(.init(name: name, kind: .classBuilderInterceptor))
        }
    }
    return registerRuntimeObject(RuntimeClassBuilderInterceptorBox(pluginID: pluginID, name: name))
}

@_cdecl("kk_class_builder_interceptor_intercept")
public func kk_class_builder_interceptor_intercept(_ interceptorRaw: Int, _ classNameRaw: Int) -> Int {
    guard let interceptor = runtimeCompilerPluginObject(interceptorRaw, as: RuntimeClassBuilderInterceptorBox.self) else {
        return -1
    }
    let className = runtimeCompilerPluginStringOrDefault(classNameRaw, default: "")
    guard !className.isEmpty else {
        return -1
    }
    interceptor.intercept(className: className)
    return 0
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
