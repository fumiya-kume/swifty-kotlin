import Foundation

final class RuntimeDateFormatBox {
    let formatter: DateFormatter

    init(pattern: String, localeIdentifier: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier.replacingOccurrences(of: "_", with: "-"))
        formatter.dateFormat = pattern
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.formatter = formatter
    }
}

private func runtimeDateFormatBox(from raw: Int) -> RuntimeDateFormatBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDateFormatBox.self)
}

private func dateFormatString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func dateFormatMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

@_cdecl("kk_dateformat_ofPattern")
public func kk_dateformat_ofPattern(_ patternRaw: Int, _ localeRaw: Int) -> Int {
    let pattern = dateFormatString(from: patternRaw, caller: #function)
    let locale = dateFormatString(from: localeRaw, caller: #function)
    return registerRuntimeObject(RuntimeDateFormatBox(pattern: pattern, localeIdentifier: locale))
}

@_cdecl("kk_dateformat_format")
public func kk_dateformat_format(_ formatRaw: Int, _ epochMillis: Int) -> Int {
    guard let box = runtimeDateFormatBox(from: formatRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_dateformat_format received invalid DateFormat handle")
    }
    let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000.0)
    return dateFormatMakeStringRaw(box.formatter.string(from: date))
}
