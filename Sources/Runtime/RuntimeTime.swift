import Dispatch

// MARK: - kotlin.time experimental time runtime (STDLIB-TIME-180)

final class RuntimeTimeMarkBox {
    let uptimeNanoseconds: Int64

    init(uptimeNanoseconds: Int64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

private func runtimeTimeMarkBox(from raw: Int) -> RuntimeTimeMarkBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTimeMarkBox.self)
}

private func runtimeDurationBoxForTime(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
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

@_cdecl("kk_time_source_mark_now")
public func kk_time_source_mark_now(_ receiver: Int) -> Int {
    let mark = RuntimeTimeMarkBox(uptimeNanoseconds: runtimeMonotonicNowNanoseconds())
    return registerRuntimeObject(mark)
}

@_cdecl("kk_time_source_monotonic_mark_now")
public func kk_time_source_monotonic_mark_now(_ receiver: Int) -> Int {
    kk_time_source_mark_now(receiver)
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
