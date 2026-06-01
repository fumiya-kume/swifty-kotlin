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

func runtimeLocaleBox(from raw: Int) -> RuntimeLocaleBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLocaleBox.self)
}

private final class RuntimeLocaleState: @unchecked Sendable {
    let lock = NSLock()
    var defaultLocaleBox: RuntimeLocaleBox?
}

private let runtimeLocaleState = RuntimeLocaleState()

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
