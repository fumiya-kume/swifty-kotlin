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
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func runtimeDurationIsInfinite(_ nanoseconds: Int64) -> Bool {
    nanoseconds == Int64.max || nanoseconds == Int64.min
}

private func runtimeDurationHandle(fromNanoseconds nanoseconds: Int64) -> Int {
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

private func runtimeFormatScaledDuration(_ absNs: Int64, unitDivisor: Int64, suffix: String) -> String {
    let whole = absNs / unitDivisor
    let remainder = absNs % unitDivisor
    guard remainder != 0 else {
        return "\(whole)\(suffix)"
    }

    var fraction = String(remainder)
    let targetWidth = String(unitDivisor - 1).count
    if fraction.count < targetWidth {
        fraction = String(repeating: "0", count: targetWidth - fraction.count) + fraction
    }
    while fraction.last == "0" {
        fraction.removeLast()
    }
    return "\(whole).\(fraction)\(suffix)"
}

private func runtimeDurationMakeString(_ value: String) -> Int {
    return Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
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

private func runtimeDurationISOSecondComponent(seconds: Int64, nanoseconds: Int64) -> String {
    guard nanoseconds != 0 else {
        return "\(seconds)S"
    }

    let width: Int
    if nanoseconds % 1_000_000 == 0 {
        width = 3
    } else if nanoseconds % 1_000 == 0 {
        width = 6
    } else {
        width = 9
    }
    let divisor = Int64(pow(10.0, Double(9 - width)))
    let fractionValue = nanoseconds / divisor
    let fraction = String(format: "%0\(width)d", Int(fractionValue))
    return "\(seconds).\(fraction)S"
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

private func runtimeDurationInvokeComponents(
    _ result: Int,
    thrown: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if thrown != 0 {
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return result
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

@_cdecl("kk_duration_from_seconds")
public func kk_duration_from_seconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_milliseconds")
public func kk_duration_from_milliseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_microseconds")
public func kk_duration_from_microseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_nanoseconds")
public func kk_duration_from_nanoseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_minutes")
public func kk_duration_from_minutes(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 60 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_hours")
public func kk_duration_from_hours(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 3600 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_days")
public func kk_duration_from_days(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 86_400 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_seconds_long")
public func kk_duration_from_seconds_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_milliseconds_long")
public func kk_duration_from_milliseconds_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_microseconds_long")
public func kk_duration_from_microseconds_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 1_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_nanoseconds_long")
public func kk_duration_from_nanoseconds_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_minutes_long")
public func kk_duration_from_minutes_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 60 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_hours_long")
public func kk_duration_from_hours_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 3600 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_days_long")
public func kk_duration_from_days_long(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: saturatingMultiply(Int64(value), 86_400 * 1_000_000_000))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_seconds_double")
public func kk_duration_from_seconds_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 1_000_000_000))
}

@_cdecl("kk_duration_from_milliseconds_double")
public func kk_duration_from_milliseconds_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 1_000_000))
}

@_cdecl("kk_duration_from_microseconds_double")
public func kk_duration_from_microseconds_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 1_000))
}

@_cdecl("kk_duration_from_nanoseconds_double")
public func kk_duration_from_nanoseconds_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 1))
}

@_cdecl("kk_duration_from_minutes_double")
public func kk_duration_from_minutes_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 60 * 1_000_000_000))
}

@_cdecl("kk_duration_from_hours_double")
public func kk_duration_from_hours_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 3_600 * 1_000_000_000))
}

@_cdecl("kk_duration_from_days_double")
public func kk_duration_from_days_double(_ valueBits: Int) -> Int {
    runtimeDurationHandle(fromNanoseconds: runtimeDurationNanoseconds(fromDoubleBits: valueBits, scale: 86_400 * 1_000_000_000))
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

@_cdecl("kk_duration_inWholeMilliseconds")
public func kk_duration_inWholeMilliseconds(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeMilliseconds received invalid Duration handle")
    }
    return Int(box.nanoseconds / 1_000_000)
}

@_cdecl("kk_duration_inWholeSeconds")
public func kk_duration_inWholeSeconds(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeSeconds received invalid Duration handle")
    }
    return Int(box.nanoseconds / 1_000_000_000)
}

@_cdecl("kk_duration_inWholeMinutes")
public func kk_duration_inWholeMinutes(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeMinutes received invalid Duration handle")
    }
    return Int(box.nanoseconds / Int64(60_000_000_000))
}

@_cdecl("kk_duration_inWholeMicroseconds")
public func kk_duration_inWholeMicroseconds(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeMicroseconds received invalid Duration handle")
    }
    return Int(box.nanoseconds / 1_000)
}

@_cdecl("kk_duration_inWholeNanoseconds")
public func kk_duration_inWholeNanoseconds(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeNanoseconds received invalid Duration handle")
    }
    return Int(box.nanoseconds)
}

@_cdecl("kk_duration_inWholeHours")
public func kk_duration_inWholeHours(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeHours received invalid Duration handle")
    }
    return Int(box.nanoseconds / Int64(3_600_000_000_000))
}

@_cdecl("kk_duration_inWholeDays")
public func kk_duration_inWholeDays(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeDays received invalid Duration handle")
    }
    return Int(box.nanoseconds / Int64(86_400_000_000_000))
}

@_cdecl("kk_duration_toString")
public func kk_duration_toString(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toString received invalid Duration handle")
    }
    let ns = box.nanoseconds
    let str: String

    if ns == 0 {
        str = "0s"
    } else {
        let isNegative = ns < 0
        let absNs = isNegative ? (ns == Int64.min ? Int64.max : -ns) : ns
        if absNs % 3_600_000_000_000 == 0 {
            let hours = absNs / 3_600_000_000_000
            str = isNegative ? "-\(hours)h" : "\(hours)h"
        } else if absNs % 60_000_000_000 == 0 {
            let minutes = absNs / 60_000_000_000
            str = isNegative ? "-\(minutes)m" : "\(minutes)m"
        } else if absNs % 1_000_000_000 == 0 {
            let seconds = absNs / 1_000_000_000
            str = isNegative ? "-\(seconds)s" : "\(seconds)s"
        } else if absNs >= 1_000_000 {
            let formatted = runtimeFormatScaledDuration(absNs, unitDivisor: 1_000_000, suffix: "ms")
            str = isNegative ? "-\(formatted)" : formatted
        } else if absNs >= 1_000 {
            let formatted = runtimeFormatScaledDuration(absNs, unitDivisor: 1_000, suffix: "us")
            str = isNegative ? "-\(formatted)" : formatted
        } else {
            str = isNegative ? "-\(absNs)ns" : "\(absNs)ns"
        }
    }
    return Int(bitPattern: str.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: str.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(str.utf8.count))
        }
    })
}

@_cdecl("kk_duration_toIsoString")
public func kk_duration_toIsoString(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toIsoString received invalid Duration handle")
    }

    if box.nanoseconds == Int64.max {
        return runtimeDurationMakeString("PT9999999999999H")
    }
    if box.nanoseconds == Int64.min {
        return runtimeDurationMakeString("-PT9999999999999H")
    }

    let isNegative = box.nanoseconds < 0
    var remaining = isNegative ? -box.nanoseconds : box.nanoseconds
    let hours = remaining / runtimeDurationNanosPerHour
    remaining %= runtimeDurationNanosPerHour
    let minutes = remaining / runtimeDurationNanosPerMinute
    remaining %= runtimeDurationNanosPerMinute
    let seconds = remaining / runtimeDurationNanosPerSecond
    let nanos = remaining % runtimeDurationNanosPerSecond

    var result = isNegative ? "-PT" : "PT"
    if hours != 0 {
        result += "\(hours)H"
    }
    if minutes != 0 || (hours != 0 && (seconds != 0 || nanos != 0)) {
        result += "\(minutes)M"
    }
    if seconds != 0 || nanos != 0 || (hours == 0 && minutes == 0) {
        result += runtimeDurationISOSecondComponent(seconds: seconds, nanoseconds: nanos)
    }
    return runtimeDurationMakeString(result)
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
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
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
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_toComponents_seconds")
public func kk_duration_toComponents_seconds(
    _ durationRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toComponents_seconds received invalid Duration handle")
    }

    let seconds: Int64
    let nanoseconds: Int
    if box.nanoseconds == Int64.max || box.nanoseconds == Int64.min {
        seconds = box.nanoseconds
        nanoseconds = 0
    } else {
        let components = runtimeDurationComponents(
            box.nanoseconds,
            topUnit: runtimeDurationNanosPerSecond,
            lowerUnits: [1]
        )
        seconds = components.top
        nanoseconds = components.lower[0]
    }

    var thrown = 0
    let result = runtimeInvokeCollectionLambda2(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        lhs: Int(seconds),
        rhs: nanoseconds,
        outThrown: &thrown
    )
    return runtimeDurationInvokeComponents(result, thrown: thrown, outThrown: outThrown)
}

@_cdecl("kk_duration_toComponents_minutes")
public func kk_duration_toComponents_minutes(
    _ durationRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toComponents_minutes received invalid Duration handle")
    }

    let minutes: Int64
    let seconds: Int
    let nanoseconds: Int
    if box.nanoseconds == Int64.max || box.nanoseconds == Int64.min {
        minutes = box.nanoseconds
        seconds = 0
        nanoseconds = 0
    } else {
        let components = runtimeDurationComponents(
            box.nanoseconds,
            topUnit: runtimeDurationNanosPerMinute,
            lowerUnits: [runtimeDurationNanosPerSecond, 1]
        )
        minutes = components.top
        seconds = components.lower[0]
        nanoseconds = components.lower[1]
    }

    var thrown = 0
    let result = runtimeInvokeCollectionLambda3(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        arg1: Int(minutes),
        arg2: seconds,
        arg3: nanoseconds,
        outThrown: &thrown
    )
    return runtimeDurationInvokeComponents(result, thrown: thrown, outThrown: outThrown)
}

@_cdecl("kk_duration_toComponents_hours")
public func kk_duration_toComponents_hours(
    _ durationRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toComponents_hours received invalid Duration handle")
    }

    let hours: Int64
    let minutes: Int
    let seconds: Int
    let nanoseconds: Int
    if box.nanoseconds == Int64.max || box.nanoseconds == Int64.min {
        hours = box.nanoseconds
        minutes = 0
        seconds = 0
        nanoseconds = 0
    } else {
        let components = runtimeDurationComponents(
            box.nanoseconds,
            topUnit: runtimeDurationNanosPerHour,
            lowerUnits: [runtimeDurationNanosPerMinute, runtimeDurationNanosPerSecond, 1]
        )
        hours = components.top
        minutes = components.lower[0]
        seconds = components.lower[1]
        nanoseconds = components.lower[2]
    }

    var thrown = 0
    let result = runtimeInvokeCollectionLambda4(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        arg1: Int(hours),
        arg2: minutes,
        arg3: seconds,
        arg4: nanoseconds,
        outThrown: &thrown
    )
    return runtimeDurationInvokeComponents(result, thrown: thrown, outThrown: outThrown)
}

@_cdecl("kk_duration_toComponents_days")
public func kk_duration_toComponents_days(
    _ durationRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toComponents_days received invalid Duration handle")
    }

    let days: Int64
    let hours: Int
    let minutes: Int
    let seconds: Int
    let nanoseconds: Int
    if box.nanoseconds == Int64.max || box.nanoseconds == Int64.min {
        days = box.nanoseconds
        hours = 0
        minutes = 0
        seconds = 0
        nanoseconds = 0
    } else {
        let components = runtimeDurationComponents(
            box.nanoseconds,
            topUnit: runtimeDurationNanosPerDay,
            lowerUnits: [
                runtimeDurationNanosPerHour,
                runtimeDurationNanosPerMinute,
                runtimeDurationNanosPerSecond,
                1,
            ]
        )
        days = components.top
        hours = components.lower[0]
        minutes = components.lower[1]
        seconds = components.lower[2]
        nanoseconds = components.lower[3]
    }

    var thrown = 0
    let result = runtimeInvokeCollectionLambda5(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        arg1: Int(days),
        arg2: hours,
        arg3: minutes,
        arg4: seconds,
        arg5: nanoseconds,
        outThrown: &thrown
    )
    return runtimeDurationInvokeComponents(result, thrown: thrown, outThrown: outThrown)
}

// MARK: - Duration advanced operations (STDLIB-TIME-082)

@_cdecl("kk_duration_absoluteValue")
public func kk_duration_absoluteValue(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_absoluteValue received invalid Duration handle")
    }
    let ns = box.nanoseconds
    let absNs = ns == Int64.min ? Int64.max : (ns < 0 ? -ns : ns)
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: absNs))
}

@_cdecl("kk_duration_isNegative")
public func kk_duration_isNegative(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isNegative received invalid Duration handle")
    }
    return box.nanoseconds < 0 ? 1 : 0
}

@_cdecl("kk_duration_isPositive")
public func kk_duration_isPositive(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isPositive received invalid Duration handle")
    }
    return box.nanoseconds > 0 ? 1 : 0
}

@_cdecl("kk_duration_isInfinite")
public func kk_duration_isInfinite(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isInfinite received invalid Duration handle")
    }
    return (box.nanoseconds == Int64.max || box.nanoseconds == Int64.min) ? 1 : 0
}

@_cdecl("kk_duration_isFinite")
public func kk_duration_isFinite(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isFinite received invalid Duration handle")
    }
    return (box.nanoseconds == Int64.max || box.nanoseconds == Int64.min) ? 0 : 1
}

@_cdecl("kk_duration_plus")
public func kk_duration_plus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationBox(from: lhsRaw),
          let rhs = runtimeDurationBox(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_plus received invalid Duration handle")
    }
    let (result, overflow) = lhs.nanoseconds.addingReportingOverflow(rhs.nanoseconds)
    let ns: Int64 = overflow ? ((lhs.nanoseconds > 0) ? Int64.max : Int64.min) : result
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: ns))
}

@_cdecl("kk_duration_minus")
public func kk_duration_minus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationBox(from: lhsRaw),
          let rhs = runtimeDurationBox(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_minus received invalid Duration handle")
    }
    let (result, overflow) = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
    let ns: Int64 = overflow ? ((lhs.nanoseconds >= 0) ? Int64.max : Int64.min) : result
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: ns))
}

@_cdecl("kk_duration_times_int")
public func kk_duration_times_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_times_int received invalid Duration handle")
    }
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: saturatingMultiply(box.nanoseconds, Int64(scale))))
}

@_cdecl("kk_duration_div_int")
public func kk_duration_div_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_int received invalid Duration handle")
    }
    guard scale != 0 else {
        let ns: Int64 = box.nanoseconds >= 0 ? Int64.max : Int64.min
        return registerRuntimeObject(RuntimeDurationBox(nanoseconds: ns))
    }
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: box.nanoseconds / Int64(scale)))
}

@_cdecl("kk_duration_div_duration")
public func kk_duration_div_duration(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationBox(from: lhsRaw),
          let rhs = runtimeDurationBox(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_duration received invalid Duration handle")
    }
    let lhsValue = runtimeDurationIsInfinite(lhs.nanoseconds)
        ? (lhs.nanoseconds > 0 ? Double.infinity : -Double.infinity)
        : Double(lhs.nanoseconds)
    let rhsValue = runtimeDurationIsInfinite(rhs.nanoseconds)
        ? (rhs.nanoseconds > 0 ? Double.infinity : -Double.infinity)
        : Double(rhs.nanoseconds)
    return kk_double_to_bits(lhsValue / rhsValue)
}

@_cdecl("kk_duration_unary_minus")
public func kk_duration_unary_minus(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_unary_minus received invalid Duration handle")
    }
    let ns = box.nanoseconds == Int64.min ? Int64.max : -box.nanoseconds
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: ns))
}

@_cdecl("kk_duration_compareTo")
public func kk_duration_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationBox(from: lhsRaw),
          let rhs = runtimeDurationBox(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_compareTo received invalid Duration handle")
    }
    if lhs.nanoseconds < rhs.nanoseconds { return -1 }
    if lhs.nanoseconds > rhs.nanoseconds { return 1 }
    return 0
}

// MARK: - measureTime / measureTimedValue (STDLIB-231/660)

@_cdecl("kk_measureTime")
public func kk_measureTime(_ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    var thrown = 0
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    let end = DispatchTime.now().uptimeNanoseconds
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    // Compute delta in UInt64 first (always non-negative), then clamp to Int64 range.
    let delta = end &- start
    let elapsedNs = delta <= UInt64(Int64.max) ? Int64(delta) : Int64.max
    let box = RuntimeDurationBox(nanoseconds: elapsedNs)
    return registerRuntimeObject(box)
}

@_cdecl("kk_measureTimedValue")
public func kk_measureTimedValue(_ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    let end = DispatchTime.now().uptimeNanoseconds
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    // Compute delta in UInt64 first (always non-negative), then clamp to Int64 range.
    let delta = end &- start
    let elapsedNs = delta <= UInt64(Int64.max) ? Int64(delta) : Int64.max
    let durationBox = RuntimeDurationBox(nanoseconds: elapsedNs)
    let durationHandle = registerRuntimeObject(durationBox)
    let timedValueBox = RuntimeTimedValueBox(value: result, duration: durationHandle)
    return registerRuntimeObject(timedValueBox)
}

// MARK: - TimedValue (STDLIB-660)

/// Runtime representation of `kotlin.time.TimedValue<T>`.
/// Stores the lambda's return value and the elapsed Duration.
final class RuntimeTimedValueBox {
    let value: Int
    let duration: Int  // handle to RuntimeDurationBox
    init(value: Int, duration: Int) {
        self.value = value
        self.duration = duration
    }
}

@_cdecl("kk_timedvalue_new")
public func kk_timedvalue_new(_ value: Int, _ duration: Int) -> Int {
    let box = RuntimeTimedValueBox(value: value, duration: duration)
    return registerRuntimeObject(box)
}

@_cdecl("kk_timedvalue_value")
public func kk_timedvalue_value(_ timedValueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: timedValueRaw),
          let box = tryCast(ptr, to: RuntimeTimedValueBox.self) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_timedvalue_value received invalid TimedValue handle")
    }
    return box.value
}

@_cdecl("kk_timedvalue_duration")
public func kk_timedvalue_duration(_ timedValueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: timedValueRaw),
          let box = tryCast(ptr, to: RuntimeTimedValueBox.self) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_timedvalue_duration received invalid TimedValue handle")
    }
    return box.duration
}

@_cdecl("kk_timedvalue_toString")
public func kk_timedvalue_toString(_ timedValueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: timedValueRaw),
          let box = tryCast(ptr, to: RuntimeTimedValueBox.self) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_timedvalue_toString received invalid TimedValue handle")
    }
    let valueStr = runtimeElementToString(box.value)
    let durationStrHandle = kk_duration_toString(box.duration)
    let durationStr = runtimeElementToString(durationStrHandle)
    let result = "TimedValue(value=\(valueStr), duration=\(durationStr))"
    let utf8 = Array(result.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}
