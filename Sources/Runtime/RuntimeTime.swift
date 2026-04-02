import Foundation

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
    let remainingMillis = Int64(epochMilliseconds - (totalSeconds * 1_000))
    let nanos = Int32(remainingMillis * 1_000_000)
    let clampedSeconds = totalSeconds < Double(Int64.min)
        ? Int64.min
        : (totalSeconds > Double(Int64.max) ? Int64.max : Int64(totalSeconds))
    return RuntimeInstantBox(epochSeconds: clampedSeconds, nanoOfSecond: nanos)
}

private func runtimeJavaDurationComponents(from nanoseconds: Int64) -> (seconds: Int64, nanoAdjustment: Int32) {
    let seconds = nanoseconds / 1_000_000_000
    let nanoAdjustment = Int32(nanoseconds % 1_000_000_000)
    return (seconds, nanoAdjustment)
}

private func runtimeSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return rhs < 0 ? Int64.min : Int64.max
    }
    return result
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
