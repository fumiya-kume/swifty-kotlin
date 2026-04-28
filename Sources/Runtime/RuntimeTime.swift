import Dispatch
import Foundation

// MARK: - kotlin.time experimental time runtime (STDLIB-TIME-180)
// MARK: - Platform time conversion runtime (STDLIB-TIME-181)

final class RuntimeJavaInstantBox {
    let epochSeconds: Int64
    let nanoOfSecond: Int32

    init(epochSeconds: Int64, nanoOfSecond: Int32) {
        self.epochSeconds = epochSeconds
        self.nanoOfSecond = nanoOfSecond
    }
}

final class RuntimeJavaDurationBox {
    let seconds: Int64
    let nanoAdjustment: Int32

    init(seconds: Int64, nanoAdjustment: Int32) {
        self.seconds = seconds
        self.nanoAdjustment = nanoAdjustment
    }
}

final class RuntimeJSDateBox {
    let epochMilliseconds: Double

    init(epochMilliseconds: Double) {
        self.epochMilliseconds = epochMilliseconds
    }
}

final class RuntimeTimeMarkBox {
    let uptimeNanoseconds: Int64

    init(uptimeNanoseconds: Int64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

private func runtimeKotlinInstantBox(from raw: Int) -> RuntimeInstantBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInstantBox.self)
}

private func runtimeKotlinDurationBox(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func runtimeJavaInstantBox(from raw: Int) -> RuntimeJavaInstantBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJavaInstantBox.self)
}

private func runtimeJavaDurationBox(from raw: Int) -> RuntimeJavaDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJavaDurationBox.self)
}

private func runtimeJSDateBox(from raw: Int) -> RuntimeJSDateBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJSDateBox.self)
}

private func runtimeTimeMarkBox(from raw: Int) -> RuntimeTimeMarkBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTimeMarkBox.self)
}

private func runtimeDurationBoxForTime(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func runtimeEpochMilliseconds(
    epochSeconds: Int64,
    nanoOfSecond: Int32
) -> Double {
    Double(epochSeconds) * 1_000 + Double(nanoOfSecond) / 1_000_000
}

private func runtimeInstantFromEpochMilliseconds(_ epochMilliseconds: Double) -> RuntimeInstantBox {
    if !epochMilliseconds.isFinite {
        let sentinelSeconds: Int64 = epochMilliseconds.sign == .minus ? Int64.min : Int64.max
        return RuntimeInstantBox(epochSeconds: sentinelSeconds, nanoOfSecond: 0)
    }

    let totalSeconds = floor(epochMilliseconds / 1_000)
    let remainingMilliseconds = epochMilliseconds - (totalSeconds * 1_000)
    let nanos = Int32(remainingMilliseconds * 1_000_000)
    let clampedSeconds = totalSeconds < Double(Int64.min)
        ? Int64.min
        : (totalSeconds > Double(Int64.max) ? Int64.max : Int64(totalSeconds))
    return RuntimeInstantBox(epochSeconds: clampedSeconds, nanoOfSecond: nanos)
}

private func runtimeJavaDurationComponents(from nanoseconds: Int64) -> (seconds: Int64, nanoAdjustment: Int32) {
    // Use floor division so that nanoAdjustment is always in [0, 999_999_999].
    // For positive values, truncation == floor; for negative values we adjust.
    let seconds: Int64
    if nanoseconds >= 0 {
        seconds = nanoseconds / 1_000_000_000
    } else {
        // Guard against Int64.min overflow before subtracting 999_999_999.
        let (adjusted, overflow) = nanoseconds.subtractingReportingOverflow(999_999_999)
        seconds = overflow ? Int64.min / 1_000_000_000 : adjusted / 1_000_000_000
    }
    let nanoAdjustment = Int32(nanoseconds - seconds * 1_000_000_000)
    return (seconds, nanoAdjustment)
}

private func runtimeSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return rhs < 0 ? Int64.min : Int64.max
    }
    return result
}

private func runtimeMonotonicNowNanoseconds() -> Int64 {
    let now = DispatchTime.now().uptimeNanoseconds
    return now <= UInt64(Int64.max) ? Int64(now) : Int64.max
}

private func runtimeNegSaturating(_ value: Int64) -> Int64 {
    value == Int64.min ? Int64.max : -value
}

private func runtimeTimeMarkElapsedNanoseconds(_ mark: RuntimeTimeMarkBox) -> Int64 {
    runtimeSaturatingAdd(runtimeMonotonicNowNanoseconds(), runtimeNegSaturating(mark.uptimeNanoseconds))
}

private func runtimeDurationHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    registerRuntimeObject(RuntimeDurationBox(nanoseconds: nanoseconds))
}

@_cdecl("kk_instant_to_java_instant")
public func kk_instant_to_java_instant(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_java_instant received invalid Instant handle")
    }
    return registerRuntimeObject(
        RuntimeJavaInstantBox(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    )
}

@_cdecl("kk_java_instant_to_kotlin_instant")
public func kk_java_instant_to_kotlin_instant(_ instantRaw: Int) -> Int {
    guard let instant = runtimeJavaInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_instant_to_kotlin_instant received invalid java.time.Instant handle")
    }
    return registerRuntimeObject(
        RuntimeInstantBox(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    )
}

@_cdecl("kk_duration_to_java_duration")
public func kk_duration_to_java_duration(_ durationRaw: Int) -> Int {
    guard let duration = runtimeKotlinDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_to_java_duration received invalid Duration handle")
    }
    let components = runtimeJavaDurationComponents(from: duration.nanoseconds)
    return registerRuntimeObject(
        RuntimeJavaDurationBox(seconds: components.seconds, nanoAdjustment: components.nanoAdjustment)
    )
}

@_cdecl("kk_java_duration_to_kotlin_duration")
public func kk_java_duration_to_kotlin_duration(_ durationRaw: Int) -> Int {
    guard let duration = runtimeJavaDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_duration_to_kotlin_duration received invalid java.time.Duration handle")
    }
    let secondsAsNanos = saturatingMultiply(duration.seconds, 1_000_000_000)
    let totalNanoseconds = runtimeSaturatingAdd(secondsAsNanos, Int64(duration.nanoAdjustment))
    return registerRuntimeObject(RuntimeDurationBox(nanoseconds: totalNanoseconds))
}

@_cdecl("kk_instant_to_js_date")
public func kk_instant_to_js_date(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_js_date received invalid Instant handle")
    }
    return registerRuntimeObject(
        RuntimeJSDateBox(epochMilliseconds: runtimeEpochMilliseconds(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond))
    )
}

@_cdecl("kk_js_date_to_kotlin_instant")
public func kk_js_date_to_kotlin_instant(_ dateRaw: Int) -> Int {
    guard let date = runtimeJSDateBox(from: dateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_js_date_to_kotlin_instant received invalid JS Date handle")
    }
    return registerRuntimeObject(runtimeInstantFromEpochMilliseconds(date.epochMilliseconds))
}

@_cdecl("kk_time_source_mark_now")
public func kk_time_source_mark_now(_ receiver: Int) -> Int {
    let mark = RuntimeTimeMarkBox(uptimeNanoseconds: runtimeMonotonicNowNanoseconds())
    return registerRuntimeObject(mark)
}

@_cdecl("kk_time_source_monotonic_mark_now")
public func kk_time_source_monotonic_mark_now(_ receiver: Int) -> Int {
    kk_time_source_mark_now(receiver)
}

@_cdecl("kk_time_source_as_clock")
public func kk_time_source_as_clock(_ sourceRaw: Int, _ originRaw: Int) -> Int {
    guard let origin = runtimeKotlinInstantBox(from: originRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_source_as_clock received invalid Instant handle")
    }
    return registerRuntimeObject(RuntimeTimeSourceClockBox(
        origin: origin,
        baseUptimeNanoseconds: runtimeMonotonicNowNanoseconds()
    ))
}

@_cdecl("kk_time_mark_elapsed_now")
public func kk_time_mark_elapsed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_elapsed_now received invalid TimeMark handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeTimeMarkElapsedNanoseconds(mark))
}

@_cdecl("kk_time_mark_has_passed_now")
public func kk_time_mark_has_passed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_has_passed_now received invalid TimeMark handle")
    }
    return runtimeTimeMarkElapsedNanoseconds(mark) >= 0 ? 1 : 0
}

@_cdecl("kk_time_mark_has_not_passed_now")
public func kk_time_mark_has_not_passed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_has_not_passed_now received invalid TimeMark handle")
    }
    return runtimeTimeMarkElapsedNanoseconds(mark) < 0 ? 1 : 0
}

@_cdecl("kk_time_mark_plus_duration")
public func kk_time_mark_plus_duration(_ markRaw: Int, _ durationRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw),
          let duration = runtimeDurationBoxForTime(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_plus_duration received invalid handle")
    }
    let shifted = RuntimeTimeMarkBox(
        uptimeNanoseconds: runtimeSaturatingAdd(mark.uptimeNanoseconds, duration.nanoseconds)
    )
    return registerRuntimeObject(shifted)
}

@_cdecl("kk_time_mark_minus_duration")
public func kk_time_mark_minus_duration(_ markRaw: Int, _ durationRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw),
          let duration = runtimeDurationBoxForTime(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_minus_duration received invalid handle")
    }
    let shifted = RuntimeTimeMarkBox(
        uptimeNanoseconds: runtimeSaturatingAdd(mark.uptimeNanoseconds, runtimeNegSaturating(duration.nanoseconds))
    )
    return registerRuntimeObject(shifted)
}

@_cdecl("kk_time_mark_minus_mark")
public func kk_time_mark_minus_mark(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeTimeMarkBox(from: lhsRaw),
          let rhs = runtimeTimeMarkBox(from: rhsRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_minus_mark received invalid TimeMark handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeSaturatingAdd(lhs.uptimeNanoseconds, runtimeNegSaturating(rhs.uptimeNanoseconds)))
}

@_cdecl("kk_time_mark_compare")
public func kk_time_mark_compare(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeTimeMarkBox(from: lhsRaw),
          let rhs = runtimeTimeMarkBox(from: rhsRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_compare received invalid TimeMark handle")
    }
    if lhs.uptimeNanoseconds < rhs.uptimeNanoseconds { return -1 }
    if lhs.uptimeNanoseconds > rhs.uptimeNanoseconds { return 1 }
    return 0
}

// MARK: - java.time.Instant property accessors (STDLIB-TIME-181)

/// Returns the epochSeconds field of a java.time.Instant handle.
///
/// Kotlin/JVM: javaInstant.epochSecond
@_cdecl("kk_java_instant_epoch_seconds")
public func kk_java_instant_epoch_seconds(_ instantRaw: Int) -> Int {
    guard let instant = runtimeJavaInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_instant_epoch_seconds received invalid java.time.Instant handle")
    }
    return Int(instant.epochSeconds)
}

/// Returns the nanoOfSecond field of a java.time.Instant handle.
///
/// Kotlin/JVM: javaInstant.nano
@_cdecl("kk_java_instant_nano_of_second")
public func kk_java_instant_nano_of_second(_ instantRaw: Int) -> Int {
    guard let instant = runtimeJavaInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_instant_nano_of_second received invalid java.time.Instant handle")
    }
    return Int(instant.nanoOfSecond)
}

/// Returns the epoch-millisecond value of a java.time.Instant handle.
///
/// Kotlin/JVM: javaInstant.toEpochMilli()
@_cdecl("kk_java_instant_to_epoch_milli")
public func kk_java_instant_to_epoch_milli(_ instantRaw: Int) -> Int {
    guard let instant = runtimeJavaInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_instant_to_epoch_milli received invalid java.time.Instant handle")
    }
    let millis = runtimeEpochMilliseconds(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    return Int(millis)
}

/// Creates a java.time.Instant from epoch seconds and nanoOfSecond.
///
/// Kotlin/JVM: java.time.Instant.ofEpochSecond(epochSecond, nanoAdjustment)
@_cdecl("kk_java_instant_of_epoch_second")
public func kk_java_instant_of_epoch_second(_ epochSeconds: Int, _ nanoOfSecond: Int) -> Int {
    return registerRuntimeObject(
        RuntimeJavaInstantBox(epochSeconds: Int64(epochSeconds), nanoOfSecond: Int32(nanoOfSecond))
    )
}

/// Creates a java.time.Instant from epoch milliseconds.
///
/// Kotlin/JVM: java.time.Instant.ofEpochMilli(epochMilli)
@_cdecl("kk_java_instant_of_epoch_milli")
public func kk_java_instant_of_epoch_milli(_ epochMillis: Int) -> Int {
    let epochMillis64 = Int64(epochMillis)
    let nanoRem = epochMillis64 % 1_000
    let secs = epochMillis64 / 1_000
    let nanoOfSecond: Int32
    let epochSecs: Int64
    if nanoRem < 0 {
        nanoOfSecond = Int32((nanoRem + 1_000) * 1_000_000)
        epochSecs = secs - 1
    } else {
        nanoOfSecond = Int32(nanoRem * 1_000_000)
        epochSecs = secs
    }
    return registerRuntimeObject(RuntimeJavaInstantBox(epochSeconds: epochSecs, nanoOfSecond: nanoOfSecond))
}

/// Returns a human-readable ISO-8601 string for a java.time.Instant.
///
/// Kotlin/JVM: javaInstant.toString()
@_cdecl("kk_java_instant_to_string")
public func kk_java_instant_to_string(_ instantRaw: Int) -> Int {
    guard let instant = runtimeJavaInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_instant_to_string received invalid java.time.Instant handle")
    }
    let date = Date(timeIntervalSince1970: Double(instant.epochSeconds) + Double(instant.nanoOfSecond) / 1_000_000_000)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let str = formatter.string(from: date)
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

// MARK: - java.time.Duration property accessors (STDLIB-TIME-181)

/// Returns the seconds field of a java.time.Duration handle.
///
/// Kotlin/JVM: javaDuration.seconds
@_cdecl("kk_java_duration_seconds")
public func kk_java_duration_seconds(_ durationRaw: Int) -> Int {
    guard let duration = runtimeJavaDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_duration_seconds received invalid java.time.Duration handle")
    }
    return Int(duration.seconds)
}

/// Returns the nanoAdjustment field of a java.time.Duration handle.
///
/// Kotlin/JVM: javaDuration.nano
@_cdecl("kk_java_duration_nano")
public func kk_java_duration_nano(_ durationRaw: Int) -> Int {
    guard let duration = runtimeJavaDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_duration_nano received invalid java.time.Duration handle")
    }
    return Int(duration.nanoAdjustment)
}

/// Returns the total milliseconds of a java.time.Duration handle.
///
/// Kotlin/JVM: javaDuration.toMillis()
@_cdecl("kk_java_duration_to_millis")
public func kk_java_duration_to_millis(_ durationRaw: Int) -> Int {
    guard let duration = runtimeJavaDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_duration_to_millis received invalid java.time.Duration handle")
    }
    let secondsAsMillis = runtimeSaturatingAdd(
        saturatingMultiply(duration.seconds, 1_000),
        Int64(duration.nanoAdjustment) / 1_000_000
    )
    return Int(secondsAsMillis)
}

/// Creates a java.time.Duration from seconds and nanoAdjustment.
///
/// Kotlin/JVM: java.time.Duration.ofSeconds(seconds, nanoAdjustment)
@_cdecl("kk_java_duration_of_seconds")
public func kk_java_duration_of_seconds(_ seconds: Int, _ nanoAdjustment: Int) -> Int {
    return registerRuntimeObject(
        RuntimeJavaDurationBox(seconds: Int64(seconds), nanoAdjustment: Int32(nanoAdjustment))
    )
}

/// Creates a java.time.Duration from milliseconds.
///
/// Kotlin/JVM: java.time.Duration.ofMillis(millis)
@_cdecl("kk_java_duration_of_millis")
public func kk_java_duration_of_millis(_ millis: Int) -> Int {
    let millis64 = Int64(millis)
    let nanoRem = millis64 % 1_000
    let secs = millis64 / 1_000
    let nanoAdjustment: Int32
    let seconds: Int64
    if nanoRem < 0 {
        nanoAdjustment = Int32((nanoRem + 1_000) * 1_000_000)
        seconds = secs - 1
    } else {
        nanoAdjustment = Int32(nanoRem * 1_000_000)
        seconds = secs
    }
    return registerRuntimeObject(RuntimeJavaDurationBox(seconds: seconds, nanoAdjustment: nanoAdjustment))
}

/// Returns a human-readable string for a java.time.Duration (ISO-8601 format).
///
/// Kotlin/JVM: javaDuration.toString()
///
/// Java's Duration.toString() follows the ISO-8601 pattern PTnHnMn.nS.
/// The sign is placed on each component, not as a leading "-PT" prefix.
/// For example: Duration.ofMillis(-1500) → "PT-1.500000000S"
///              Duration.ofSeconds(-3600) → "PT-1H"
@_cdecl("kk_java_duration_to_string")
public func kk_java_duration_to_string(_ durationRaw: Int) -> Int {
    guard let duration = runtimeJavaDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_java_duration_to_string received invalid java.time.Duration handle")
    }
    // duration.seconds and duration.nanoAdjustment are the canonical fields
    // (nanoAdjustment is always in [0, 999_999_999] after construction).
    let secs = duration.seconds
    let nano = Int64(duration.nanoAdjustment)

    // Build ISO-8601 duration string: PT[nH][nM][n[.nnnnnnnnn]S]
    // Components are signed individually, matching java.time.Duration.toString().
    var result = "PT"
    let absSecs = secs == Int64.min ? Int64.max : (secs < 0 ? -secs : secs)
    let hours = absSecs / 3_600
    let minutes = (absSecs % 3_600) / 60
    let seconds = absSecs % 60
    let isNegative = secs < 0

    if hours > 0 { result += isNegative ? "-\(hours)H" : "\(hours)H" }
    if minutes > 0 { result += isNegative ? "-\(minutes)M" : "\(minutes)M" }
    if seconds > 0 || nano > 0 || (hours == 0 && minutes == 0) {
        let signedSec = isNegative ? -Int64(seconds) : Int64(seconds)
        if nano == 0 {
            result += "\(signedSec)S"
        } else {
            let fracStr = String(format: "%09d", nano).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            result += "\(signedSec).\(fracStr)S"
        }
    }
    let utf8 = Array(result.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

// MARK: - JS Date property accessors (STDLIB-TIME-181)

/// Returns the epochMilliseconds of a JS Date handle.
///
/// Kotlin/JS: date.getTime()
@_cdecl("kk_js_date_epoch_millis")
public func kk_js_date_epoch_millis(_ dateRaw: Int) -> Int {
    guard let date = runtimeJSDateBox(from: dateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_js_date_epoch_millis received invalid JS Date handle")
    }
    return Int(date.epochMilliseconds)
}

/// Creates a JS Date from epoch milliseconds.
///
/// Kotlin/JS: Date(milliseconds)
@_cdecl("kk_js_date_from_epoch_millis")
public func kk_js_date_from_epoch_millis(_ epochMillis: Int) -> Int {
    return registerRuntimeObject(RuntimeJSDateBox(epochMilliseconds: Double(epochMillis)))
}

/// Returns a human-readable ISO-8601 string for a JS Date.
///
/// Kotlin/JS: date.toISOString()
@_cdecl("kk_js_date_to_string")
public func kk_js_date_to_string(_ dateRaw: Int) -> Int {
    guard let jsDate = runtimeJSDateBox(from: dateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_js_date_to_string received invalid JS Date handle")
    }
    let foundationDate = Date(timeIntervalSince1970: jsDate.epochMilliseconds / 1_000)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let str = formatter.string(from: foundationDate)
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

// MARK: - Native: Foundation Date bridge (STDLIB-TIME-181)

/// Converts a kotlin.time.Instant to a Foundation.Date (Native/macOS bridge).
///
/// Kotlin/Native: instant.toNSDate()
@_cdecl("kk_instant_to_foundation_date")
public func kk_instant_to_foundation_date(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_foundation_date received invalid Instant handle")
    }
    let timeInterval = Double(instant.epochSeconds) + Double(instant.nanoOfSecond) / 1_000_000_000
    // Represent Foundation.Date as epoch milliseconds in a JS-style box for interop.
    return registerRuntimeObject(RuntimeJSDateBox(epochMilliseconds: timeInterval * 1_000))
}

/// Converts a Foundation.Date (represented as epoch-millisecond JS box) to a kotlin.time.Instant.
///
/// Kotlin/Native: nsDate.toKotlinInstant()
@_cdecl("kk_foundation_date_to_kotlin_instant")
public func kk_foundation_date_to_kotlin_instant(_ dateRaw: Int) -> Int {
    guard let jsDate = runtimeJSDateBox(from: dateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_foundation_date_to_kotlin_instant received invalid NSDate handle")
    }
    return registerRuntimeObject(runtimeInstantFromEpochMilliseconds(jsDate.epochMilliseconds))
}

// MARK: - Native: clock_gettime bridge (STDLIB-TIME-181)

/// Returns wall-clock time as a kotlin.time.Instant using POSIX clock_gettime(CLOCK_REALTIME).
///
/// This is a lower-level alternative to kk_instant_now that bypasses Foundation.Date.
@_cdecl("kk_clock_gettime_realtime")
public func kk_clock_gettime_realtime() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_REALTIME, &ts)
    return registerRuntimeObject(
        RuntimeInstantBox(epochSeconds: Int64(ts.tv_sec), nanoOfSecond: Int32(ts.tv_nsec))
    )
}

/// Returns monotonic time in nanoseconds using POSIX clock_gettime(CLOCK_MONOTONIC).
///
/// Kotlin/Native: TimeSource.Monotonic.markNow() lower-level primitive.
@_cdecl("kk_clock_gettime_monotonic_ns")
public func kk_clock_gettime_monotonic_ns() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    let ns = runtimeSaturatingAdd(
        saturatingMultiply(Int64(ts.tv_sec), 1_000_000_000),
        Int64(ts.tv_nsec)
    )
    // Clamp to Int range (platform word size).
    if ns > Int64(Int.max) { return Int.max }
    if ns < Int64(Int.min) { return Int.min }
    return Int(ns)
}

/// Returns a TimeMark backed by POSIX CLOCK_MONOTONIC instead of DispatchTime.
///
/// Kotlin/Native: TimeSource.Monotonic.markNow() (native clock variant)
@_cdecl("kk_clock_monotonic_mark_now")
public func kk_clock_monotonic_mark_now() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    let ns = runtimeSaturatingAdd(
        saturatingMultiply(Int64(ts.tv_sec), 1_000_000_000),
        Int64(ts.tv_nsec)
    )
    return registerRuntimeObject(RuntimeTimeMarkBox(uptimeNanoseconds: ns))
}

// MARK: - Type-safe epoch conversion helpers (STDLIB-TIME-181)

/// Returns the epoch-millisecond representation of a kotlin.time.Instant as a Long.
///
/// Kotlin: instant.toEpochMilliseconds()
@_cdecl("kk_instant_to_epoch_millis")
public func kk_instant_to_epoch_millis(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_epoch_millis received invalid Instant handle")
    }
    let millis = runtimeEpochMilliseconds(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    return Int(millis)
}

/// Creates a kotlin.time.Instant from separate epoch-seconds and nanoOfSecond components.
///
/// Kotlin: Instant.fromEpochSeconds(epochSeconds, nanoOfSecond)
@_cdecl("kk_instant_from_epoch_seconds")
public func kk_instant_from_epoch_seconds(_ epochSeconds: Int, _ nanoOfSecond: Int) -> Int {
    return registerRuntimeObject(
        RuntimeInstantBox(epochSeconds: Int64(epochSeconds), nanoOfSecond: Int32(nanoOfSecond))
    )
}
