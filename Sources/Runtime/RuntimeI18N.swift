import Foundation

final class RuntimeLocaleBox {
    let identifier: String
    let language: String
    let country: String
    let variant: String
    let locale: Locale

    init(identifier: String, language: String, country: String, variant: String, locale: Locale) {
        self.identifier = identifier
        self.language = language
        self.country = country
        self.variant = variant
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

private final class RuntimeLocaleState: @unchecked Sendable {
    let lock = NSLock()
    var defaultLocaleBox: RuntimeLocaleBox?
}

private let runtimeLocaleState = RuntimeLocaleState()

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

private func parseLocaleComponents(_ identifier: String) -> (language: String, country: String, variant: String) {
    let normalized = normalizeLocaleIdentifier(identifier)
    let separators = CharacterSet(charactersIn: "-@")
    let rawParts = normalized
        .components(separatedBy: separators)
        .flatMap { $0.components(separatedBy: "_") }
        .filter { !$0.isEmpty }

    let language = rawParts.indices.contains(0) ? rawParts[0].lowercased() : ""
    let country = rawParts.indices.contains(1) ? rawParts[1].uppercased() : ""
    let variant = rawParts.count > 2 ? rawParts.dropFirst(2).joined(separator: "_") : ""
    return (language, country, variant)
}

private func localeIdentifier(language: String, country: String, variant: String) -> String {
    var parts: [String] = []
    if !language.isEmpty { parts.append(language.lowercased()) }
    if !country.isEmpty { parts.append(country.uppercased()) }
    if !variant.isEmpty { parts.append(variant) }
    return parts.joined(separator: "-")
}

private func makeRuntimeLocaleBox(identifier: String) -> RuntimeLocaleBox {
    let components = parseLocaleComponents(identifier)
    let canonicalIdentifier = localeIdentifier(
        language: components.language,
        country: components.country,
        variant: components.variant
    )
    let foundationIdentifier = canonicalIdentifier.isEmpty ? normalizeLocaleIdentifier(identifier) : canonicalIdentifier
    return RuntimeLocaleBox(
        identifier: canonicalIdentifier.isEmpty ? foundationIdentifier : canonicalIdentifier,
        language: components.language,
        country: components.country,
        variant: components.variant,
        locale: Locale(identifier: foundationIdentifier)
    )
}

private func makeRuntimeLocaleBox(languageOnly rawLanguage: String) -> RuntimeLocaleBox {
    let normalizedIdentifier = normalizeLocaleIdentifier(rawLanguage)
    return RuntimeLocaleBox(
        identifier: normalizedIdentifier,
        language: rawLanguage.lowercased(),
        country: "",
        variant: "",
        locale: Locale(identifier: normalizedIdentifier)
    )
}

private func makeRuntimeLocaleBox(language: String, country: String) -> RuntimeLocaleBox {
    makeRuntimeLocaleBox(identifier: localeIdentifier(language: language, country: country, variant: ""))
}

private func currentRuntimeDefaultLocaleBox() -> RuntimeLocaleBox {
    runtimeLocaleState.lock.lock()
    defer { runtimeLocaleState.lock.unlock() }
    if let box = runtimeLocaleState.defaultLocaleBox {
        return box
    }
    let box = makeRuntimeLocaleBox(identifier: Locale.current.identifier)
    runtimeLocaleState.defaultLocaleBox = box
    return box
}

private func setRuntimeDefaultLocaleBox(_ box: RuntimeLocaleBox) {
    runtimeLocaleState.lock.lock()
    runtimeLocaleState.defaultLocaleBox = box
    runtimeLocaleState.lock.unlock()
}

@_cdecl("kk_locale_new")
public func kk_locale_new(_ identifierRaw: Int) -> Int {
    let identifier = i18nString(from: identifierRaw, caller: #function)
    return registerRuntimeObject(makeRuntimeLocaleBox(languageOnly: identifier))
}

@_cdecl("kk_locale_new_language_country")
public func kk_locale_new_language_country(_ languageRaw: Int, _ countryRaw: Int) -> Int {
    let language = i18nString(from: languageRaw, caller: #function)
    let country = i18nString(from: countryRaw, caller: #function)
    return registerRuntimeObject(makeRuntimeLocaleBox(language: language, country: country))
}

@_cdecl("kk_locale_language")
public func kk_locale_language(_ localeRaw: Int) -> Int {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_language received invalid Locale handle")
    }
    return i18nMakeStringRaw(box.language)
}

@_cdecl("kk_locale_country")
public func kk_locale_country(_ localeRaw: Int) -> Int {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_country received invalid Locale handle")
    }
    return i18nMakeStringRaw(box.country)
}

@_cdecl("kk_locale_variant")
public func kk_locale_variant(_ localeRaw: Int) -> Int {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_variant received invalid Locale handle")
    }
    return i18nMakeStringRaw(box.variant)
}

@_cdecl("kk_locale_displayLanguage")
public func kk_locale_displayLanguage(_ localeRaw: Int) -> Int {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_displayLanguage received invalid Locale handle")
    }
    let displayLocale = currentRuntimeDefaultLocaleBox().locale
    let displayLanguage = displayLocale.localizedString(forLanguageCode: box.language) ?? box.language
    return i18nMakeStringRaw(displayLanguage)
}

@_cdecl("kk_locale_getDefault")
public func kk_locale_getDefault(_ companionRaw: Int) -> Int {
    _ = companionRaw
    return registerRuntimeObject(currentRuntimeDefaultLocaleBox())
}

@_cdecl("kk_locale_setDefault")
public func kk_locale_setDefault(_ companionRaw: Int, _ localeRaw: Int) -> Int {
    _ = companionRaw
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_setDefault received invalid Locale handle")
    }
    setRuntimeDefaultLocaleBox(box)
    return 0
}

@_cdecl("kk_locale_getAvailableLocales")
public func kk_locale_getAvailableLocales(_ companionRaw: Int) -> Int {
    _ = companionRaw
    let identifiers = Set(Locale.availableIdentifiers.map { makeRuntimeLocaleBox(identifier: $0).identifier })
        .sorted()
    let arrayBox = RuntimeArrayBox(length: identifiers.count)
    for (index, identifier) in identifiers.enumerated() {
        arrayBox.elements[index] = registerRuntimeObject(makeRuntimeLocaleBox(identifier: identifier))
    }
    return registerRuntimeObject(arrayBox)
}

@_cdecl("kk_locale_hashCode")
public func kk_locale_hashCode(_ localeRaw: Int) -> Int {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_locale_hashCode received invalid Locale handle")
    }
    let value = [box.language, box.country, box.variant]
        .filter { !$0.isEmpty }
        .joined(separator: "#")
    return value.unicodeScalars.reduce(0) { partial, scalar in
        31 &* partial &+ Int(Int32(bitPattern: scalar.value))
    }
}

@_cdecl("kk_locale_equals")
public func kk_locale_equals(_ localeRaw: Int, _ otherRaw: Int) -> Int {
    guard let lhs = runtimeLocaleBox(from: localeRaw),
          let rhs = runtimeLocaleBox(from: otherRaw)
    else {
        return kk_box_bool(0)
    }
    let equal = lhs.identifier == rhs.identifier &&
        lhs.language == rhs.language &&
        lhs.country == rhs.country &&
        lhs.variant == rhs.variant
    return kk_box_bool(equal ? 1 : 0)
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
