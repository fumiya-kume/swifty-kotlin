import Foundation

final class RuntimeLocaleBox {
    let locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }
}

private func i18nString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

@_cdecl("kk_locale_new")
public func kk_locale_new(_ identifierRaw: Int) -> Int {
    let identifier = i18nString(from: identifierRaw, caller: #function).replacingOccurrences(of: "_", with: "-")
    return registerRuntimeObject(RuntimeLocaleBox(locale: Locale(identifier: identifier)))
}
