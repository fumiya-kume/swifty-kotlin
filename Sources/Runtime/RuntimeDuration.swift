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


/// Clamp-safe multiplication: returns `Int64.max` / `Int64.min` on overflow
/// instead of trapping, matching Kotlin's Duration saturation semantics.
private func saturatingMultiply(_ a: Int64, _ b: Int64) -> Int64 {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    if overflow {
        // If signs differ the overflow is negative, otherwise positive
        return (a ^ b) < 0 ? Int64.min : Int64.max
    }
    return result
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

/// Format a fractional value with up to 3 decimal places, trimming trailing zeros.
/// E.g. formatFractional(1, 500_000_000, 1_000_000_000) → "1.5"
///      formatFractional(1, 1_000_000, 1_000_000_000) → "1.001"
///      formatFractional(1, 0, 1_000_000_000) → "1"
private func formatFractional(_ whole: Int64, _ remainder: Int64, _ divisor: Int64) -> String {
    if remainder == 0 {
        return "\(whole)"
    }
    // Scale remainder to get up to 3 decimal digits
    let millis = remainder * 1000 / divisor
    if millis % 100 == 0 {
        return "\(whole).\(millis / 100)"
    } else if millis % 10 == 0 {
        return "\(whole).\(String(format: "%02d", millis / 10))"
    } else {
        return "\(whole).\(String(format: "%03d", millis))"
    }
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

        if absNs < 1_000 {
            // Nanosecond range: 1ns..999ns
            str = isNegative ? "-\(absNs)ns" : "\(absNs)ns"
        } else if absNs < 1_000_000 {
            // Microsecond range: 1us..999.999us
            let wholeUs = absNs / 1_000
            let remainderNs = absNs % 1_000
            let formatted = formatFractional(wholeUs, remainderNs, 1_000)
            str = isNegative ? "-\(formatted)us" : "\(formatted)us"
        } else if absNs < 1_000_000_000 {
            // Millisecond range: 1ms..999.999ms
            let wholeMs = absNs / 1_000_000
            let remainderNs = absNs % 1_000_000
            let formatted = formatFractional(wholeMs, remainderNs, 1_000_000)
            str = isNegative ? "-\(formatted)ms" : "\(formatted)ms"
        } else {
            // Seconds and above: decompose into h, m, s components
            let totalSeconds = absNs / 1_000_000_000
            let remainderNs = absNs % 1_000_000_000

            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            var parts: [String] = []
            if hours > 0 {
                parts.append("\(hours)h")
            }
            if minutes > 0 {
                parts.append("\(minutes)m")
            }
            if seconds > 0 || remainderNs > 0 {
                if remainderNs > 0 {
                    // Fractional seconds: up to 3 decimal places from the
                    // sub-second nanosecond remainder.
                    let formatted = formatFractional(seconds, remainderNs, 1_000_000_000)
                    parts.append("\(formatted)s")
                } else {
                    parts.append("\(seconds)s")
                }
            } else if parts.isEmpty {
                // Should not happen if absNs >= 1_000_000_000, but safety
                parts.append("0s")
            }

            let body = parts.joined(separator: " ")
            if isNegative {
                if parts.count > 1 {
                    str = "-(\(body))"
                } else {
                    str = "-\(body)"
                }
            } else {
                str = body
            }
        }
    }
    return Int(bitPattern: str.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: str.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(str.utf8.count))
        }
    })
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
