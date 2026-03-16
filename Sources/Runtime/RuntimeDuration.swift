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

// MARK: - Duration factory: Int.seconds, Int.milliseconds, etc.

@_cdecl("kk_duration_from_seconds")
public func kk_duration_from_seconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value) * 1_000_000_000)
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_milliseconds")
public func kk_duration_from_milliseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value) * 1_000_000)
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_microseconds")
public func kk_duration_from_microseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value) * 1_000)
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_nanoseconds")
public func kk_duration_from_nanoseconds(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value))
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_minutes")
public func kk_duration_from_minutes(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value) * 60 * 1_000_000_000)
    return registerRuntimeObject(box)
}

@_cdecl("kk_duration_from_hours")
public func kk_duration_from_hours(_ value: Int) -> Int {
    let box = RuntimeDurationBox(nanoseconds: Int64(value) * 3600 * 1_000_000_000)
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

@_cdecl("kk_duration_inWholeNanoseconds")
public func kk_duration_inWholeNanoseconds(_ durationRaw: Int) -> Int {
    guard let box = runtimeDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeNanoseconds received invalid Duration handle")
    }
    return Int(box.nanoseconds)
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
    } else if ns % 1_000_000_000 == 0 {
        str = "\(ns / 1_000_000_000)s"
    } else if ns % 1_000_000 == 0 {
        str = "\(ns / 1_000_000)ms"
    } else if ns % 1_000 == 0 {
        str = "\(ns / 1_000)us"
    } else {
        str = "\(ns)ns"
    }
    let utf8 = Array(str.utf8)
    return Int(bitPattern: utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    })
}

// MARK: - measureTime / measureTimedValue (STDLIB-231)

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
    let elapsed = Int64(end) - Int64(start)
    let box = RuntimeDurationBox(nanoseconds: elapsed)
    return registerRuntimeObject(box)
}
