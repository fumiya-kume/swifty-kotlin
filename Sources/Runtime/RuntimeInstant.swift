import Foundation

// MARK: - kotlin.time.Instant Runtime (STDLIB-TIME-083/086)
//
// Implements the runtime entry points for kotlin.time.Instant and
// kotlin.time.Clock.  Instant is stored as a (epochSeconds: Int64,
// nanoOfSecond: Int32) pair, matching Kotlin's Instant representation.
// All functions are thread-safe because Date() and SystemRandomNumberGenerator
// are safe to call from any thread and the box objects are immutable once
// created.

// MARK: - Box

/// Immutable box holding a kotlin.time.Instant value.
/// Instant is stored as (epochSeconds: Int64, nanoOfSecond: Int32) internally,
/// matching Kotlin's Instant semantics where nanoOfSecond is in [0, 999_999_999].
final class RuntimeInstantBox {
    let epochSeconds: Int64
    let nanoOfSecond: Int32

    init(epochSeconds: Int64, nanoOfSecond rawNano: Int32) {
        // Normalise nanoOfSecond into [0, 999_999_999].
        // Use division/modulo to handle multi-second overflow or borrow:
        //   - rawNano >= 1_000_000_000: carry full seconds into epochSeconds
        //   - rawNano < 0: borrow full seconds from epochSeconds
        // Work in Int64 to avoid overflow during intermediate calculations.
        let nano64 = Int64(rawNano)
        let carry: Int64
        if nano64 >= 0 {
            carry = nano64 / 1_000_000_000
        } else {
            // Floor division for negative values: borrow enough full seconds
            // so the remainder lands in [0, 999_999_999].
            carry = (nano64 - 999_999_999) / 1_000_000_000
        }
        self.epochSeconds = epochSeconds + carry
        self.nanoOfSecond = Int32(nano64 - carry * 1_000_000_000)
    }
}

// MARK: - Helpers

private func runtimeInstantBox(from raw: Int) -> RuntimeInstantBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInstantBox.self)
}

private func runtimeDurationBox(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
    let (result, overflow) = a.addingReportingOverflow(b)
    if overflow {
        return b < 0 ? Int64.min : Int64.max
    }
    return result
}

// MARK: - Instant construction

/// Returns the current wall-clock time as a kotlin.time.Instant.
/// Thread-safe: Date() reads a system clock and is reentrant.
///
/// Kotlin: Instant.now()  /  Clock.System.now()
@_cdecl("kk_instant_now")
public func kk_instant_now() -> Int {
    let now = Date()
    let epochSec = Int64(now.timeIntervalSince1970)
    let fracSec = now.timeIntervalSince1970 - Double(epochSec)
    let nano = Int32(fracSec * 1_000_000_000)
    let box = RuntimeInstantBox(epochSeconds: epochSec, nanoOfSecond: nano)
    return registerRuntimeObject(box)
}

/// Alias used when Clock.System.now() is dispatched via the Clock.System object.
/// Both map to the same underlying wall-clock read.
///
/// Kotlin: Clock.System.now()
@_cdecl("kk_clock_system_now")
public func kk_clock_system_now() -> Int {
    kk_instant_now()
}

/// Generic Clock interface now() — delegates to the system clock.
///
/// Kotlin: clock.now()
@_cdecl("kk_clock_now")
public func kk_clock_now(_ receiver: Int) -> Int {
    kk_instant_now()
}

/// Creates an Instant from an epoch-millisecond value.
///
/// Kotlin: Instant.fromEpochMilliseconds(epochMilliseconds: Long)
@_cdecl("kk_instant_from_epoch_millis")
public func kk_instant_from_epoch_millis(_ millis: Int) -> Int {
    let epochSec = Int64(millis) / 1_000
    let nanoRem = Int32(Int64(millis) % 1_000) * 1_000_000
    let box = RuntimeInstantBox(epochSeconds: epochSec, nanoOfSecond: nanoRem)
    return registerRuntimeObject(box)
}

// MARK: - Instant properties

/// Returns the epochSeconds component of an Instant as Long.
///
/// Kotlin: instant.epochSeconds
@_cdecl("kk_instant_epoch_seconds")
public func kk_instant_epoch_seconds(_ instantRaw: Int) -> Int {
    guard let box = runtimeInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_epoch_seconds received invalid Instant handle")
    }
    return Int(box.epochSeconds)
}

/// Returns the nanoOfSecond component of an Instant as Int.
///
/// Kotlin: instant.nanoOfSecond
@_cdecl("kk_instant_nano_of_second")
public func kk_instant_nano_of_second(_ instantRaw: Int) -> Int {
    guard let box = runtimeInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_nano_of_second received invalid Instant handle")
    }
    return Int(box.nanoOfSecond)
}

// MARK: - Instant arithmetic

/// Returns a new Instant shifted forward by the given Duration.
///
/// Kotlin: instant + duration
@_cdecl("kk_instant_plus_duration")
public func kk_instant_plus_duration(_ instantRaw: Int, _ durationRaw: Int) -> Int {
    guard let ibox = runtimeInstantBox(from: instantRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: durationRaw),
          let dbox = tryCast(ptr, to: RuntimeDurationBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_plus_duration received invalid handle")
    }
    let durationNs = dbox.nanoseconds
    let addedSec = durationNs / 1_000_000_000
    let addedNano = Int32(durationNs % 1_000_000_000)
    let result = RuntimeInstantBox(
        epochSeconds: saturatingAdd(ibox.epochSeconds, addedSec),
        nanoOfSecond: ibox.nanoOfSecond + addedNano
    )
    return registerRuntimeObject(result)
}

/// Returns a new Instant shifted backward by the given Duration.
///
/// Kotlin: instant - duration
@_cdecl("kk_instant_minus_duration")
public func kk_instant_minus_duration(_ instantRaw: Int, _ durationRaw: Int) -> Int {
    guard let ibox = runtimeInstantBox(from: instantRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: durationRaw),
          let dbox = tryCast(ptr, to: RuntimeDurationBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_minus_duration received invalid handle")
    }
    let durationNs = dbox.nanoseconds
    let subSec = durationNs / 1_000_000_000
    let subNano = Int32(durationNs % 1_000_000_000)
    let result = RuntimeInstantBox(
        epochSeconds: saturatingAdd(ibox.epochSeconds, -subSec),
        nanoOfSecond: ibox.nanoOfSecond - subNano
    )
    return registerRuntimeObject(result)
}

// MARK: - Instant comparison
// Returns: negative if a < b, 0 if a == b, positive if a > b

/// Compares two Instants, returning negative / zero / positive.
///
/// Kotlin: instant.compareTo(other)
@_cdecl("kk_instant_compare")
public func kk_instant_compare(_ aRaw: Int, _ bRaw: Int) -> Int {
    guard let a = runtimeInstantBox(from: aRaw),
          let b = runtimeInstantBox(from: bRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_compare received invalid Instant handle")
    }
    if a.epochSeconds != b.epochSeconds {
        return a.epochSeconds < b.epochSeconds ? -1 : 1
    }
    if a.nanoOfSecond != b.nanoOfSecond {
        return a.nanoOfSecond < b.nanoOfSecond ? -1 : 1
    }
    return 0
}

// MARK: - until() — Duration between two Instants

/// Returns the Duration from this Instant until the other Instant.
///
/// Kotlin: instant.until(other)
@_cdecl("kk_instant_until")
public func kk_instant_until(_ fromRaw: Int, _ toRaw: Int) -> Int {
    guard let fromBox = runtimeInstantBox(from: fromRaw),
          let toBox = runtimeInstantBox(from: toRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_until received invalid Instant handle")
    }
    let secDiff = saturatingAdd(toBox.epochSeconds, -fromBox.epochSeconds)
    let nanoDiff = Int64(toBox.nanoOfSecond) - Int64(fromBox.nanoOfSecond)
    let secNs = saturatingMultiply(secDiff, 1_000_000_000)
    let totalNs = saturatingAdd(secNs, nanoDiff)
    let durationBox = RuntimeDurationBox(nanoseconds: totalNs)
    return registerRuntimeObject(durationBox)
}
