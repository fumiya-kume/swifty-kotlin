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
