import Foundation

final class RuntimeLocaleBox {
    let locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }
}

final class RuntimeResourceBundleBox {
    let values: [String: String]
    let parent: RuntimeResourceBundleBox?

    init(values: [String: String], parent: RuntimeResourceBundleBox? = nil) {
        self.values = values
        self.parent = parent
    }

    func value(for key: String) -> String? {
        values[key] ?? parent?.value(for: key)
    }

    func allKeys() -> [String] {
        let inherited = parent?.allKeys() ?? []
        return Array(Set(values.keys).union(inherited)).sorted()
    }
}

final class RuntimeNumberFormatBox {
    let formatter: NumberFormatter

    init(style: NumberFormatter.Style, locale: Locale?) {
        let formatter = NumberFormatter()
        formatter.locale = locale ?? Locale.current
        formatter.numberStyle = style
        if style == .decimal {
            formatter.generatesDecimalNumbers = true
        }
        if style == .none {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
            formatter.generatesDecimalNumbers = false
        }
        self.formatter = formatter
    }
}

func runtimeLocaleBox(from raw: Int) -> RuntimeLocaleBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLocaleBox.self)
}

private func runtimeResourceBundleBox(from raw: Int) -> RuntimeResourceBundleBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeResourceBundleBox.self)
}

private func runtimeNumberFormatBox(from raw: Int) -> RuntimeNumberFormatBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeNumberFormatBox.self)
}

private func i18nString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func i18nMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

private func resourceRootDirectory() -> URL {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_RESOURCE_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func parseProperties(_ text: String) -> [String: String] {
    func hasUnescapedTrailingBackslash(_ line: String) -> Bool {
        var slashCount = 0
        for scalar in line.unicodeScalars.reversed() {
            if scalar == "\\" {
                slashCount += 1
            } else {
                break
            }
        }
        return slashCount % 2 == 1
    }

    func splitProperty(_ line: String) -> (String, String) {
        var separatorIndex: String.Index?
        var sawNonWhitespace = false
        var escaped = false
        var index = line.startIndex

        while index < line.endIndex {
            let ch = line[index]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "=" || ch == ":" || (ch.isWhitespace && sawNonWhitespace) {
                separatorIndex = index
                break
            } else if !ch.isWhitespace {
                sawNonWhitespace = true
            }
            index = line.index(after: index)
        }

        guard let separatorIndex else {
            return (line.trimmingCharacters(in: .whitespaces), "")
        }

        var valueStart = line.index(after: separatorIndex)
        while valueStart < line.endIndex, line[valueStart].isWhitespace {
            valueStart = line.index(after: valueStart)
        }
        let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    var logicalLines: [String] = []
    var current = ""
    var isContinuation = false
    for physicalLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        // Per the .properties spec, leading whitespace of a continuation line must be stripped.
        let line = isContinuation
            ? String(physicalLine).trimmingCharacters(in: .whitespaces)
            : String(physicalLine)
        if current.isEmpty {
            current = line
        } else {
            current += line
        }

        if hasUnescapedTrailingBackslash(current) {
            current.removeLast()
            isContinuation = true
            continue
        }

        logicalLines.append(current)
        current = ""
        isContinuation = false
    }
    if !current.isEmpty {
        logicalLines.append(current)
    }

    var result: [String: String] = [:]
    for line in logicalLines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!") else { continue }
        let (key, value) = splitProperty(trimmed)
        if !key.isEmpty {
            result[key] = value
        }
    }
    return result
}

/// Normalizes a locale identifier from Kotlin/Java format (e.g. "en_US") to the IETF BCP 47
/// format expected by Apple APIs (e.g. "en-US") by replacing underscores with hyphens.
/// Used wherever locale identifiers are processed in the runtime (I18N, DateFormat, etc.).
func normalizeLocaleIdentifier(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "_", with: "-")
}

@_cdecl("kk_locale_new")
public func kk_locale_new(_ identifierRaw: Int) -> Int {
    let identifier = i18nString(from: identifierRaw, caller: #function)
        .replacingOccurrences(of: "_", with: "-")
    return registerRuntimeObject(RuntimeLocaleBox(locale: Locale(identifier: identifier)))
}

private func runtimeNumberFormatterLocale(from raw: Int) -> Locale? {
    runtimeLocaleBox(from: raw)?.locale
}

private func runtimeNumberFormatCreate(style: NumberFormatter.Style, localeRaw: Int) -> Int {
    registerRuntimeObject(
        RuntimeNumberFormatBox(
            style: style,
            locale: runtimeNumberFormatterLocale(from: localeRaw)
        )
    )
}

private func runtimeNumberFormatString(_ formatterRaw: Int, value: NSNumber, caller: StaticString) -> Int {
    guard let box = runtimeNumberFormatBox(from: formatterRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid NumberFormat handle")
    }
    guard let formatted = box.formatter.string(from: value) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) failed to format number")
    }
    return i18nMakeStringRaw(formatted)
}

@_cdecl("kk_numberformat_getIntegerInstance")
public func kk_numberformat_getIntegerInstance(_ localeRaw: Int) -> Int {
    runtimeNumberFormatCreate(style: .none, localeRaw: localeRaw)
}

@_cdecl("kk_numberformat_getNumberInstance")
public func kk_numberformat_getNumberInstance(_ localeRaw: Int) -> Int {
    runtimeNumberFormatCreate(style: .decimal, localeRaw: localeRaw)
}

@_cdecl("kk_numberformat_getCurrencyInstance")
public func kk_numberformat_getCurrencyInstance(_ localeRaw: Int) -> Int {
    runtimeNumberFormatCreate(style: .currency, localeRaw: localeRaw)
}

@_cdecl("kk_numberformat_getPercentInstance")
public func kk_numberformat_getPercentInstance(_ localeRaw: Int) -> Int {
    runtimeNumberFormatCreate(style: .percent, localeRaw: localeRaw)
}

@_cdecl("kk_numberformat_formatInt")
public func kk_numberformat_formatInt(_ formatRaw: Int, _ value: Int) -> Int {
    runtimeNumberFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

@_cdecl("kk_numberformat_formatLong")
public func kk_numberformat_formatLong(_ formatRaw: Int, _ value: Int) -> Int {
    runtimeNumberFormatString(formatRaw, value: NSNumber(value: Int64(value)), caller: #function)
}

@_cdecl("kk_numberformat_formatFloat")
public func kk_numberformat_formatFloat(_ formatRaw: Int, _ value: Float) -> Int {
    runtimeNumberFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

@_cdecl("kk_numberformat_formatDouble")
public func kk_numberformat_formatDouble(_ formatRaw: Int, _ value: Double) -> Int {
    runtimeNumberFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

private func bundleURL(name: String, suffix: String?) -> URL? {
    let root = resourceRootDirectory()
    let fileName = suffix.map { "\(name)_\($0).properties" } ?? "\(name).properties"
    let url = root.appendingPathComponent(fileName)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

private func bundleCandidateSuffixes(localeIdentifier: String?) -> [String?] {
    guard let localeIdentifier, !localeIdentifier.isEmpty else { return [nil] }

    let normalized = normalizeLocaleIdentifier(localeIdentifier)
        .replacingOccurrences(of: "-", with: "_")
    let parts = normalized.split(separator: "_").map(String.init).filter { !$0.isEmpty }
    guard !parts.isEmpty else { return [nil] }

    var suffixes: [String?] = []
    for count in stride(from: parts.count, through: 1, by: -1) {
        suffixes.append(parts.prefix(count).joined(separator: "_"))
    }
    suffixes.append(nil)
    return suffixes
}

private func loadBundle(name: String, localeIdentifier: String?) -> RuntimeResourceBundleBox? {
    var loadedBundle: RuntimeResourceBundleBox?

    for suffix in bundleCandidateSuffixes(localeIdentifier: localeIdentifier).reversed() {
        guard let url = bundleURL(name: name, suffix: suffix),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            continue
        }
        loadedBundle = RuntimeResourceBundleBox(values: parseProperties(text), parent: loadedBundle)
    }

    return loadedBundle
}

@_cdecl("kk_resource_bundle_getBundle")
public func kk_resource_bundle_getBundle(_ nameRaw: Int, _ localeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let name = i18nString(from: nameRaw, caller: #function)
    let localeIdentifier = runtimeLocaleBox(from: localeRaw)?.locale.identifier
    guard let bundle = loadBundle(name: name, localeIdentifier: localeIdentifier) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MissingResourceException: \(name)")
        return 0
    }
    return registerRuntimeObject(bundle)
}

@_cdecl("kk_resource_bundle_getString")
public func kk_resource_bundle_getString(_ bundleRaw: Int, _ keyRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bundle = runtimeResourceBundleBox(from: bundleRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_bundle_getString received invalid ResourceBundle handle")
    }
    let key = i18nString(from: keyRaw, caller: #function)
    guard let value = bundle.value(for: key) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MissingResourceException: \(key)")
        return i18nMakeStringRaw("")
    }
    return i18nMakeStringRaw(value)
}

@_cdecl("kk_resource_bundle_getObject")
public func kk_resource_bundle_getObject(_ bundleRaw: Int, _ keyRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_resource_bundle_getString(bundleRaw, keyRaw, outThrown)
}

@_cdecl("kk_resource_bundle_getKeys")
public func kk_resource_bundle_getKeys(_ bundleRaw: Int) -> Int {
    guard let bundle = runtimeResourceBundleBox(from: bundleRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_bundle_getKeys received invalid ResourceBundle handle")
    }
    let raws = bundle.allKeys().map(i18nMakeStringRaw)
    return registerRuntimeObject(RuntimeListBox(elements: raws))
}
