import Foundation

final class RuntimeDateFormatBox {
    let formatter: DateFormatter

    init(pattern: String, localeIdentifier: String, timeZoneIdentifier: String? = nil) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: normalizeLocaleIdentifier(localeIdentifier))
        formatter.dateFormat = pattern
        formatter.timeZone = runtimeDateFormatTimeZone(timeZoneIdentifier)
        self.formatter = formatter
    }

    init(
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        localeIdentifier: String,
        timeZoneIdentifier: String? = nil
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: normalizeLocaleIdentifier(localeIdentifier))
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = runtimeDateFormatTimeZone(timeZoneIdentifier)
        self.formatter = formatter
    }
}

private func runtimeDateFormatTimeZone(_ identifier: String?) -> TimeZone {
    if let identifier, !identifier.isEmpty, let timeZone = TimeZone(identifier: identifier) {
        return timeZone
    }
    // Intentionally fixed to UTC for deterministic cross-platform formatting.
    // Note: Java/Kotlin DateFormat defaults to the system timezone, so this deviates from JVM
    // semantics. This choice avoids non-deterministic output when tests run in different TZs.
    return TimeZone(secondsFromGMT: 0)!
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
    var result: Int = 0
    value.utf8.withContiguousStorageIfAvailable { bytes in
        result = Int(bitPattern: kk_string_from_utf8(bytes.baseAddress!, Int32(bytes.count)))
    } ?? {
        // Fallback: copy UTF-8 bytes into a contiguous buffer.
        let bytes = Array(value.utf8)
        result = Int(bitPattern: bytes.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        })
    }()
    return result
}

@_cdecl("kk_dateformat_ofPattern")
public func kk_dateformat_ofPattern(_ patternRaw: Int, _ localeRaw: Int) -> Int {
    let pattern = dateFormatString(from: patternRaw, caller: #function)
    let locale = dateFormatString(from: localeRaw, caller: #function)
    return registerRuntimeObject(RuntimeDateFormatBox(pattern: pattern, localeIdentifier: locale))
}

@_cdecl("kk_dateformat_ofPatternWithTimeZone")
public func kk_dateformat_ofPatternWithTimeZone(_ patternRaw: Int, _ localeRaw: Int, _ timeZoneRaw: Int) -> Int {
    let pattern = dateFormatString(from: patternRaw, caller: #function)
    let locale = dateFormatString(from: localeRaw, caller: #function)
    let timeZone = dateFormatString(from: timeZoneRaw, caller: #function)
    return registerRuntimeObject(RuntimeDateFormatBox(pattern: pattern, localeIdentifier: locale, timeZoneIdentifier: timeZone))
}

private func dateFormatStyleBox(
    dateStyle: DateFormatter.Style,
    timeStyle: DateFormatter.Style,
    localeRaw: Int,
    timeZoneRaw: Int? = nil,
    caller: StaticString
) -> Int {
    let locale = dateFormatString(from: localeRaw, caller: caller)
    let timeZone = timeZoneRaw.map { dateFormatString(from: $0, caller: caller) }
    return registerRuntimeObject(
        RuntimeDateFormatBox(
            dateStyle: dateStyle,
            timeStyle: timeStyle,
            localeIdentifier: locale,
            timeZoneIdentifier: timeZone
        )
    )
}

@_cdecl("kk_dateformat_getDateInstance")
public func kk_dateformat_getDateInstance(_ localeRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .medium, timeStyle: .none, localeRaw: localeRaw, caller: #function)
}

@_cdecl("kk_dateformat_getDateInstanceWithTimeZone")
public func kk_dateformat_getDateInstanceWithTimeZone(_ localeRaw: Int, _ timeZoneRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .medium, timeStyle: .none, localeRaw: localeRaw, timeZoneRaw: timeZoneRaw, caller: #function)
}

@_cdecl("kk_dateformat_getTimeInstance")
public func kk_dateformat_getTimeInstance(_ localeRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .none, timeStyle: .medium, localeRaw: localeRaw, caller: #function)
}

@_cdecl("kk_dateformat_getTimeInstanceWithTimeZone")
public func kk_dateformat_getTimeInstanceWithTimeZone(_ localeRaw: Int, _ timeZoneRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .none, timeStyle: .medium, localeRaw: localeRaw, timeZoneRaw: timeZoneRaw, caller: #function)
}

@_cdecl("kk_dateformat_getDateTimeInstance")
public func kk_dateformat_getDateTimeInstance(_ localeRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .medium, timeStyle: .medium, localeRaw: localeRaw, caller: #function)
}

@_cdecl("kk_dateformat_getDateTimeInstanceWithTimeZone")
public func kk_dateformat_getDateTimeInstanceWithTimeZone(_ localeRaw: Int, _ timeZoneRaw: Int) -> Int {
    dateFormatStyleBox(dateStyle: .medium, timeStyle: .medium, localeRaw: localeRaw, timeZoneRaw: timeZoneRaw, caller: #function)
}

@_cdecl("kk_dateformat_ofPatternDefaultLocale")
public func kk_dateformat_ofPatternDefaultLocale(_ patternRaw: Int) -> Int {
    let pattern = dateFormatString(from: patternRaw, caller: #function)
    return registerRuntimeObject(RuntimeDateFormatBox(pattern: pattern, localeIdentifier: Locale.current.identifier))
}

@_cdecl("kk_dateformat_format")
public func kk_dateformat_format(_ formatRaw: Int, _ epochMillis: Int) -> Int {
    guard let box = runtimeDateFormatBox(from: formatRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_dateformat_format received invalid DateFormat handle")
    }
    let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000.0)
    return dateFormatMakeStringRaw(box.formatter.string(from: date))
}

@_cdecl("kk_dateformat_parse")
public func kk_dateformat_parse(_ formatRaw: Int, _ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeDateFormatBox(from: formatRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_dateformat_parse received invalid DateFormat handle")
    }
    let text = dateFormatString(from: stringRaw, caller: #function)
    guard let date = box.formatter.date(from: text) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ParseException: Unparseable date: \"\(text)\"")
        return 0
    }
    let epochMillis = Int(date.timeIntervalSince1970 * 1000.0)
    return epochMillis
}
