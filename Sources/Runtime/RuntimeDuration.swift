import Dispatch
import Foundation

// MARK: - kotlin.time.Duration Runtime (STDLIB-230/231)

/// Duration is stored as nanoseconds internally.
final class RuntimeDurationBox {
    let nanoseconds: Int64
    init(nanoseconds: Int64) { self.nanoseconds = nanoseconds }
}

private func runtimeDurationBox(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isRegisteredObject = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isRegisteredObject else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

/// Reads both the legacy boxed representation and Duration's source-backed
/// value-class payload. Raw values are only treated as object handles when the
/// runtime has registered the pointer, so ordinary small Long payloads are safe.
func runtimeDurationNanosecondsValue(from raw: Int) -> Int64? {
    if let box = runtimeDurationBox(from: raw) {
        return box.nanoseconds
    }
    return Int64(bitPattern: UInt64(bitPattern: Int64(raw)))
}

private func runtimeDurationIsInfinite(_ nanoseconds: Int64) -> Bool {
    nanoseconds == Int64.max || nanoseconds == Int64.min
}

private func runtimeDurationHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    Int(truncatingIfNeeded: nanoseconds)
}

private func runtimeDurationBoxHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    registerRuntimeObject(RuntimeDurationBox(nanoseconds: nanoseconds))
}

private func runtimeDurationNanoseconds(
    fromDoubleBits valueBits: Int,
    scale: Double
) -> Int64 {
    let value = kk_bits_to_double(valueBits)
    guard value.isFinite else {
        if value.isNaN {
            return 0
        }
        return value.sign == .minus ? Int64.min : Int64.max
    }

    let scaled = value * scale
    guard scaled.isFinite else {
        return scaled.sign == .minus ? Int64.min : Int64.max
    }

    let rounded = scaled.rounded()
    if rounded >= Double(Int64.max) {
        return Int64.max
    }
    if rounded <= Double(Int64.min) {
        return Int64.min
    }
    return Int64(rounded)
}

/// Formats `whole.fraction<unit>` following kotlin-stdlib's `Duration.toString()`
/// trimming rule: fewer than 3 significant fractional digits are kept as-is,
/// otherwise the fraction is padded out to the next multiple of 3 digits
/// (e.g. 4500ns of a second -> ".000004500", 500000ns -> ".000500").
private func runtimeDurationFormatFractional(
    whole: Int64,
    fractionalRemainder: Int64,
    fractionalWidth: Int,
    suffix: String
) -> String {
    guard fractionalRemainder != 0 else {
        return "\(whole)\(suffix)"
    }

    var fraction = String(fractionalRemainder)
    if fraction.count < fractionalWidth {
        fraction = String(repeating: "0", count: fractionalWidth - fraction.count) + fraction
    }
    let digits = Array(fraction)
    var significantDigits = digits.count
    while significantDigits > 0, digits[significantDigits - 1] == "0" {
        significantDigits -= 1
    }
    let keepDigits = significantDigits < 3 ? significantDigits : ((significantDigits + 2) / 3) * 3
    let trimmed = String(digits.prefix(keepDigits))
    return "\(whole).\(trimmed)\(suffix)"
}

private func runtimeDurationMakeString(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeDurationComponents(
    _ nanoseconds: Int64,
    topUnit: Int64,
    lowerUnits: [Int64]
) -> (top: Int64, lower: [Int]) {
    var remaining = nanoseconds
    let top = remaining / topUnit
    remaining %= topUnit
    let lower = lowerUnits.map { unit -> Int in
        let component = remaining / unit
        remaining %= unit
        return Int(component)
    }
    return (top, lower)
}

private func runtimeDurationString(from raw: Int) -> String? {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
}

private let runtimeDurationNanosPerMicrosecond: Int64 = 1_000
private let runtimeDurationNanosPerMillisecond: Int64 = 1_000_000
private let runtimeDurationNanosPerSecond: Int64 = 1_000_000_000
private let runtimeDurationNanosPerMinute: Int64 = 60 * runtimeDurationNanosPerSecond
private let runtimeDurationNanosPerHour: Int64 = 60 * runtimeDurationNanosPerMinute
private let runtimeDurationNanosPerDay: Int64 = 24 * runtimeDurationNanosPerHour

/// DurationUnit ordinals mirror Kotlin's enum entry order:
/// 0=NANOSECONDS, 1=MICROSECONDS, 2=MILLISECONDS, 3=SECONDS,
/// 4=MINUTES, 5=HOURS, 6=DAYS.
private func runtimeDurationUnitScale(fromOrdinal ordinal: Int) -> Int64 {
    switch ordinal {
    case 0: return 1
    case 1: return runtimeDurationNanosPerMicrosecond
    case 2: return runtimeDurationNanosPerMillisecond
    case 3: return runtimeDurationNanosPerSecond
    case 4: return runtimeDurationNanosPerMinute
    case 5: return runtimeDurationNanosPerHour
    case 6: return runtimeDurationNanosPerDay
    default:
        assertionFailure("KSwiftK: unknown DurationUnit ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return 1
    }
}

private func runtimeDurationSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return lhs >= 0 && rhs >= 0 ? Int64.max : Int64.min
    }
    return result
}

private func runtimeDurationSaturatingNegate(_ value: Int64) -> Int64 {
    value == Int64.min ? Int64.max : -value
}

private func runtimeDurationApplySign(_ value: Int64, sign: Int) -> Int64 {
    if sign >= 0 {
        return value
    }
    if value == Int64.max {
        return Int64.min
    }
    return runtimeDurationSaturatingNegate(value)
}

private func runtimeDurationNanoseconds(from value: Double, scale: Int64) -> Int64? {
    guard value.isFinite else {
        return nil
    }
    let scaled = value * Double(scale)
    guard scaled.isFinite else {
        return scaled.sign == .minus ? Int64.min : Int64.max
    }
    let rounded = scaled.rounded()
    if rounded >= Double(Int64.max) {
        return Int64.max
    }
    if rounded <= Double(Int64.min) {
        return Int64.min
    }
    return Int64(rounded)
}

private func runtimeDurationParseNumber(_ chars: [Character], index: inout Int) -> Double? {
    let start = index
    if index < chars.count, chars[index] == "+" || chars[index] == "-" {
        index += 1
    }

    var sawDigit = false
    while index < chars.count, chars[index].isNumber {
        sawDigit = true
        index += 1
    }
    if index < chars.count, chars[index] == "." {
        index += 1
        while index < chars.count, chars[index].isNumber {
            sawDigit = true
            index += 1
        }
    }

    guard sawDigit else {
        return nil
    }
    return Double(String(chars[start..<index]))
}

private func runtimeDurationParseISO(_ input: String) -> Int64? {
    var chars = Array(input.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !chars.isEmpty else { return nil }

    var sign = 1
    if chars.first == "+" || chars.first == "-" {
        sign = chars.first == "-" ? -1 : 1
        chars.removeFirst()
    }
    guard chars.first == "P" else { return nil }
    var index = 1
    var inTime = false
    var sawComponent = false
    var total: Int64 = 0

    while index < chars.count {
        if chars[index] == "T" {
            guard !inTime else { return nil }
            inTime = true
            index += 1
            continue
        }

        guard let number = runtimeDurationParseNumber(chars, index: &index),
              index < chars.count
        else {
            return nil
        }

        let designator = chars[index]
        index += 1
        let scale: Int64
        switch (designator, inTime) {
        case ("D", false):
            scale = runtimeDurationNanosPerDay
        case ("H", true):
            scale = runtimeDurationNanosPerHour
        case ("M", true):
            scale = runtimeDurationNanosPerMinute
        case ("S", true):
            scale = runtimeDurationNanosPerSecond
        default:
            return nil
        }

        guard let component = runtimeDurationNanoseconds(from: number, scale: scale) else {
            return nil
        }
        total = runtimeDurationSaturatingAdd(total, component)
        sawComponent = true
    }

    guard sawComponent else { return nil }
    return runtimeDurationApplySign(total, sign: sign)
}

private func runtimeDurationParseDefaultToken(_ token: String) -> Int64? {
    let units: [(suffix: String, scale: Int64)] = [
        ("ms", runtimeDurationNanosPerMillisecond),
        ("us", runtimeDurationNanosPerMicrosecond),
        ("µs", runtimeDurationNanosPerMicrosecond),
        ("ns", 1),
        ("d", runtimeDurationNanosPerDay),
        ("h", runtimeDurationNanosPerHour),
        ("m", runtimeDurationNanosPerMinute),
        ("s", runtimeDurationNanosPerSecond),
    ]
    for unit in units where token.hasSuffix(unit.suffix) {
        let numberText = String(token.dropLast(unit.suffix.count))
        guard !numberText.isEmpty,
              let number = Double(numberText)
        else {
            return nil
        }
        return runtimeDurationNanoseconds(from: number, scale: unit.scale)
    }
    return nil
}

private func runtimeDurationParseDefault(_ input: String) -> Int64? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if text == "Infinity" || text == "+Infinity" {
        return Int64.max
    }
    if text == "-Infinity" {
        return Int64.min
    }

    var sign = 1
    if text.hasPrefix("-("), text.hasSuffix(")") {
        sign = -1
        text = String(text.dropFirst(2).dropLast())
    } else if text.hasPrefix("+") || text.hasPrefix("-") {
        sign = text.first == "-" ? -1 : 1
        text = String(text.dropFirst())
    }

    let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
    guard !parts.isEmpty else { return nil }

    var total: Int64 = 0
    for part in parts {
        guard let component = runtimeDurationParseDefaultToken(String(part)) else {
            return nil
        }
        total = runtimeDurationSaturatingAdd(total, component)
    }
    return runtimeDurationApplySign(total, sign: sign)
}

private func runtimeDurationParse(_ input: String) -> Int64? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let iso = runtimeDurationParseISO(trimmed) {
        return iso
    }
    return runtimeDurationParseDefault(trimmed)
}

/// Clamp-safe multiplication: returns `Int64.max` / `Int64.min` on overflow
/// instead of trapping, matching Kotlin's Duration saturation semantics.
func saturatingMultiply(_ a: Int64, _ b: Int64) -> Int64 {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    if overflow {
        // If signs differ the overflow is negative, otherwise positive
        return (a ^ b) < 0 ? Int64.min : Int64.max
    }
    return result
}

@_cdecl("kk_duration_zero")
public func kk_duration_zero() -> Int {
    runtimeDurationHandle(fromNanoseconds: 0)
}

@_cdecl("kk_duration_infinite")
public func kk_duration_infinite() -> Int {
    runtimeDurationHandle(fromNanoseconds: Int64.max)
}

@_cdecl("kk_duration_toDuration_int")
public func kk_duration_toDuration_int(_ value: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: saturatingMultiply(Int64(value), runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
    )
}

@_cdecl("kk_duration_toDuration_long")
public func kk_duration_toDuration_long(_ value: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: saturatingMultiply(Int64(value), runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
    )
}

@_cdecl("kk_duration_toDuration_double")
public func kk_duration_toDuration_double(_ valueBits: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: runtimeDurationNanoseconds(
            fromDoubleBits: valueBits,
            scale: Double(runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
        )
    )
}

// MARK: - Duration properties

@_cdecl("kk_duration_inWholeNanoseconds")
public func kk_duration_inWholeNanoseconds(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeNanoseconds received invalid Duration handle")
    }
    return Int(truncatingIfNeeded: nanoseconds)
}

@_cdecl("kk_duration_toString")
public func kk_duration_toString(_ durationRaw: Int) -> Int {
    guard let ns = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toString received invalid Duration handle")
    }

    if ns == 0 {
        return runtimeDurationMakeString("0s")
    }
    if ns == Int64.max {
        return runtimeDurationMakeString("Infinity")
    }
    if ns == Int64.min {
        return runtimeDurationMakeString("-Infinity")
    }

    let isNegative = ns < 0
    let absNs = isNegative ? -ns : ns

    // Decompose into days/hours/minutes/seconds/nanoseconds, matching
    // kotlin-stdlib's Duration.toString() component breakdown (values > 24h
    // roll up into days, e.g. 25h -> "1d 1h").
    let components = runtimeDurationComponents(
        absNs,
        topUnit: runtimeDurationNanosPerDay,
        lowerUnits: [runtimeDurationNanosPerHour, runtimeDurationNanosPerMinute, runtimeDurationNanosPerSecond, 1]
    )
    let days = components.top
    let hours = components.lower[0]
    let minutes = components.lower[1]
    let seconds = components.lower[2]
    let subsecondNanos = components.lower[3]

    let hasDays = days != 0
    let hasHours = hours != 0
    let hasMinutes = minutes != 0
    let hasSeconds = seconds != 0 || subsecondNanos != 0

    var out = ""
    var componentCount = 0

    if hasDays {
        out += "\(days)d"
        componentCount += 1
    }
    // Intermediate zero components stay visible once a higher and a lower
    // component are both present, e.g. 1 day + 5 minutes -> "1d 0h 5m".
    if hasHours || (hasDays && (hasMinutes || hasSeconds)) {
        if componentCount > 0 { out += " " }
        out += "\(hours)h"
        componentCount += 1
    }
    if hasMinutes || (hasSeconds && (hasHours || hasDays)) {
        if componentCount > 0 { out += " " }
        out += "\(minutes)m"
        componentCount += 1
    }
    if hasSeconds {
        if componentCount > 0 { out += " " }
        if seconds != 0 || hasDays || hasHours || hasMinutes {
            out += runtimeDurationFormatFractional(
                whole: Int64(seconds), fractionalRemainder: Int64(subsecondNanos), fractionalWidth: 9, suffix: "s"
            )
        } else if subsecondNanos >= 1_000_000 {
            out += runtimeDurationFormatFractional(
                whole: Int64(subsecondNanos / 1_000_000), fractionalRemainder: Int64(subsecondNanos % 1_000_000),
                fractionalWidth: 6, suffix: "ms"
            )
        } else if subsecondNanos >= 1_000 {
            out += runtimeDurationFormatFractional(
                whole: Int64(subsecondNanos / 1_000), fractionalRemainder: Int64(subsecondNanos % 1_000),
                fractionalWidth: 3, suffix: "us"
            )
        } else {
            out += "\(subsecondNanos)ns"
        }
        componentCount += 1
    }

    // A single negative component is prefixed with "-"; multiple components
    // are wrapped in parens, e.g. "-12m" vs. "-(1h 30m)".
    let str: String
    if isNegative && componentCount > 1 {
        str = "-(\(out))"
    } else if isNegative {
        str = "-\(out)"
    } else {
        str = out
    }
    return runtimeDurationMakeString(str)
}

@_cdecl("kk_duration_parse")
public func kk_duration_parse(_ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParse(value)
    else {
        let displayValue = runtimeDurationString(from: valueRaw) ?? "<null>"
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid duration string format: '\(displayValue)'."
        )
        return runtimeNullSentinelInt
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseOrNull")
public func kk_duration_parseOrNull(_ valueRaw: Int) -> Int {
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParse(value)
    else {
        return runtimeNullSentinelInt
    }
    return runtimeDurationBoxHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseIsoString")
public func kk_duration_parseIsoString(_ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParseISO(value)
    else {
        let displayValue = runtimeDurationString(from: valueRaw) ?? "<null>"
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid ISO duration string format: '\(displayValue)'."
        )
        return runtimeNullSentinelInt
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseIsoStringOrNull")
public func kk_duration_parseIsoStringOrNull(_ valueRaw: Int) -> Int {
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParseISO(value)
    else {
        return runtimeNullSentinelInt
    }
    return runtimeDurationBoxHandle(fromNanoseconds: nanoseconds)
}

// MARK: - Duration advanced operations (STDLIB-TIME-082)

@_cdecl("kk_duration_absoluteValue")
public func kk_duration_absoluteValue(_ durationRaw: Int) -> Int {
    guard let ns = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_absoluteValue received invalid Duration handle")
    }
    let absNs = ns == Int64.min ? Int64.max : (ns < 0 ? -ns : ns)
    return runtimeDurationHandle(fromNanoseconds: absNs)
}

@_cdecl("kk_duration_isNegative")
public func kk_duration_isNegative(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isNegative received invalid Duration handle")
    }
    return nanoseconds < 0 ? 1 : 0
}

@_cdecl("kk_duration_isPositive")
public func kk_duration_isPositive(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isPositive received invalid Duration handle")
    }
    return nanoseconds > 0 ? 1 : 0
}

@_cdecl("kk_duration_isInfinite")
public func kk_duration_isInfinite(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isInfinite received invalid Duration handle")
    }
    return (nanoseconds == Int64.max || nanoseconds == Int64.min) ? 1 : 0
}

@_cdecl("kk_duration_plus")
public func kk_duration_plus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_plus received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeDurationSaturatingAdd(lhs, rhs))
}

@_cdecl("kk_duration_minus")
public func kk_duration_minus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_minus received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeDurationSaturatingAdd(lhs, -rhs))
}

@_cdecl("kk_duration_times_int")
public func kk_duration_times_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_times_int received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: saturatingMultiply(nanoseconds, Int64(scale)))
}

@_cdecl("kk_duration_div_int")
public func kk_duration_div_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_int received invalid Duration handle")
    }
    guard scale != 0 else {
        let ns: Int64 = nanoseconds >= 0 ? Int64.max : Int64.min
        return runtimeDurationHandle(fromNanoseconds: ns)
    }
    if nanoseconds == Int64.min, scale == -1 {
        return runtimeDurationHandle(fromNanoseconds: Int64.max)
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds / Int64(scale))
}

@_cdecl("kk_duration_div_duration")
public func kk_duration_div_duration(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_duration received invalid Duration handle")
    }
    let lhsValue = runtimeDurationIsInfinite(lhs)
        ? (lhs > 0 ? Double.infinity : -Double.infinity)
        : Double(lhs)
    let rhsValue = runtimeDurationIsInfinite(rhs)
        ? (rhs > 0 ? Double.infinity : -Double.infinity)
        : Double(rhs)
    return kk_double_to_bits(lhsValue / rhsValue)
}

@_cdecl("kk_duration_unary_minus")
public func kk_duration_unary_minus(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_unary_minus received invalid Duration handle")
    }
    let ns: Int64
    if nanoseconds == Int64.min {
        ns = Int64.max
    } else if nanoseconds == Int64.max {
        ns = Int64.min
    } else {
        ns = -nanoseconds
    }
    return runtimeDurationHandle(fromNanoseconds: ns)
}

@_cdecl("kk_duration_compareTo")
public func kk_duration_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_compareTo received invalid Duration handle")
    }
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}
