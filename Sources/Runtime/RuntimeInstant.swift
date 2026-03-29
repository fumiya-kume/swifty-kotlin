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
final class RuntimeInstantBox {
    let epochSeconds: Int64
    let nanoOfSecond: Int32

    init(epochSeconds: Int64, nanoOfSecond rawNano: Int32) {
        // Normalise nanoOfSecond into [0, 999_999_999].
        // A negative rawNano can appear when the fractional part of
        // timeIntervalSince1970 rounds toward –∞.
        if rawNano < 0 {
            self.epochSeconds = epochSeconds - 1
            self.nanoOfSecond = rawNano + 1_000_000_000
        } else {
            self.epochSeconds = epochSeconds
            self.nanoOfSecond = rawNano
        }
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

// MARK: - Instant.now() / Clock.System.now()

/// Returns the current wall-clock time as a kotlin.time.Instant.
/// Thread-safe: Date() reads a system clock and is reentrant.
///
/// Kotlin: Instant.now()  /  Clock.System.now()
@_cdecl("kk_instant_now")
public func kk_instant_now() -> Int {
    let ti = Date().timeIntervalSince1970
    let sec = Int64(ti)
    let nano = Int32((ti - Double(sec)) * 1_000_000_000)
    let box = RuntimeInstantBox(epochSeconds: sec, nanoOfSecond: nano)
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

// MARK: - Instant.fromEpochMilliseconds(Long)

/// Creates an Instant from an epoch-millisecond value.
///
/// Kotlin: Instant.fromEpochMilliseconds(epochMilliseconds: Long)
@_cdecl("kk_instant_from_epoch_millis")
public func kk_instant_from_epoch_millis(_ epochMilliseconds: Int) -> Int {
    let ms = Int64(epochMilliseconds)
    let sec = ms / 1_000
    let nano = Int32((ms % 1_000) * 1_000_000)
    let box = RuntimeInstantBox(epochSeconds: sec, nanoOfSecond: nano)
    return registerRuntimeObject(box)
}

// MARK: - Instant properties

/// Returns the epochSeconds component of an Instant as Long.
///
/// Kotlin: instant.epochSeconds
@_cdecl("kk_instant_epoch_seconds")
public func kk_instant_epoch_seconds(_ receiver: Int) -> Int {
    guard let box = runtimeInstantBox(from: receiver) else { return 0 }
    return Int(box.epochSeconds)
}

/// Returns the nanoOfSecond component of an Instant as Int.
///
/// Kotlin: instant.nanoOfSecond
@_cdecl("kk_instant_nano_of_second")
public func kk_instant_nano_of_second(_ receiver: Int) -> Int {
    guard let box = runtimeInstantBox(from: receiver) else { return 0 }
    return Int(box.nanoOfSecond)
}

// MARK: - Instant arithmetic

/// Returns a new Instant shifted forward by the given Duration.
///
/// Kotlin: instant + duration
@_cdecl("kk_instant_plus_duration")
public func kk_instant_plus_duration(_ receiver: Int, _ durationRaw: Int) -> Int {
    guard let instant = runtimeInstantBox(from: receiver),
          let duration = runtimeDurationBox(from: durationRaw)
    else { return receiver }
    let nanos = duration.nanoseconds
    let addedSec = nanos / 1_000_000_000
    let addedNano = Int32(nanos % 1_000_000_000)
    let newSec = instant.epochSeconds + addedSec
    let newNano = instant.nanoOfSecond + addedNano
    let box = RuntimeInstantBox(epochSeconds: newSec, nanoOfSecond: newNano)
    return registerRuntimeObject(box)
}

/// Returns a new Instant shifted backward by the given Duration.
///
/// Kotlin: instant - duration
@_cdecl("kk_instant_minus_duration")
public func kk_instant_minus_duration(_ receiver: Int, _ durationRaw: Int) -> Int {
    guard let instant = runtimeInstantBox(from: receiver),
          let duration = runtimeDurationBox(from: durationRaw)
    else { return receiver }
    let nanos = duration.nanoseconds
    let subSec = nanos / 1_000_000_000
    let subNano = Int32(nanos % 1_000_000_000)
    let newSec = instant.epochSeconds - subSec
    let newNano = instant.nanoOfSecond - subNano
    let box = RuntimeInstantBox(epochSeconds: newSec, nanoOfSecond: newNano)
    return registerRuntimeObject(box)
}

// MARK: - Instant comparison

/// Compares two Instants, returning negative / zero / positive.
///
/// Kotlin: instant.compareTo(other)
@_cdecl("kk_instant_compare")
public func kk_instant_compare(_ receiver: Int, _ otherRaw: Int) -> Int {
    guard let a = runtimeInstantBox(from: receiver),
          let b = runtimeInstantBox(from: otherRaw)
    else { return 0 }
    if a.epochSeconds != b.epochSeconds {
        return a.epochSeconds < b.epochSeconds ? -1 : 1
    }
    if a.nanoOfSecond != b.nanoOfSecond {
        return a.nanoOfSecond < b.nanoOfSecond ? -1 : 1
    }
    return 0
}

// MARK: - Instant.until(other): Duration

/// Returns the Duration from this Instant until the other Instant.
///
/// Kotlin: instant.until(other)
@_cdecl("kk_instant_until")
public func kk_instant_until(_ receiver: Int, _ otherRaw: Int) -> Int {
    guard let a = runtimeInstantBox(from: receiver),
          let b = runtimeInstantBox(from: otherRaw)
    else {
        let zero = RuntimeDurationBox(nanoseconds: 0)
        return registerRuntimeObject(zero)
    }
    let secDiff = b.epochSeconds - a.epochSeconds
    let nanoDiff = Int64(b.nanoOfSecond) - Int64(a.nanoOfSecond)
    let totalNanos = secDiff * 1_000_000_000 + nanoDiff
    let durationBox = RuntimeDurationBox(nanoseconds: totalNanos)
    return registerRuntimeObject(durationBox)
}
