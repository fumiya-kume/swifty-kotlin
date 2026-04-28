import Dispatch
@testable import Runtime
import XCTest

// MARK: - kotlin.system edge case coverage (STDLIB-SYSTEM-003)
//
// Covers: measureTimeMillis, measureNanoTime, getTimeMillis (currentTimeMillis),
// getTimeNanos (nanoTime), processStartNanos, and exitProcess signature check.
//
// NOTE: exitProcess is not invoked in tests because it calls exit() which is
// process-terminating (Nothing semantics). Compile-time visibility is verified
// by referencing the function pointer type without calling it.

// MARK: - Shared thunks

/// Noop thunk – returns immediately.
private let systemNoopThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 0 }

/// Thunk that simulates a thrown exception via sentinel value.
private let systemThrowingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xDEAD
    return 0
}

/// Thunk that sleeps ~10ms (short, deterministic).
private let system10msThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    Thread.sleep(forTimeInterval: 0.010)
    return 0
}

/// Thunk that captures closureRaw for passthrough verification.
private let systemCaptureLock = NSLock()
nonisolated(unsafe) private var _systemCapturedRaw: Int = 0
private var systemCapturedRaw: Int {
    get { systemCaptureLock.lock(); defer { systemCaptureLock.unlock() }; return _systemCapturedRaw }
    set { systemCaptureLock.lock(); defer { systemCaptureLock.unlock() }; _systemCapturedRaw = newValue }
}

private let systemCaptureThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, _ in
    systemCapturedRaw = raw
    return 0
}

// MARK: - RuntimeSystemEdgeCaseTests

final class RuntimeSystemEdgeCaseTests: XCTestCase {

    func testSystemMeasurementRuntimeSignaturesAreFixed() {
        let _: () -> Int = kk_system_currentTimeMillis
        let _: () -> Int = kk_system_nanoTime
        let _: () -> Int = kk_system_process_start_nanos
        let _: (Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_system_measureTimeMillis
        let _: (Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_system_measureNanoTime
    }

    // MARK: - kk_system_currentTimeMillis

    func testCurrentTimeMillisIsPositive() {
        let ms = kk_system_currentTimeMillis()
        XCTAssertGreaterThan(ms, 0, "currentTimeMillis must be positive (Unix epoch since 1970)")
    }

    func testCurrentTimeMillisIsReasonableEpoch() {
        // 2020-01-01 00:00:00 UTC in ms = 1_577_836_800_000
        let ms = kk_system_currentTimeMillis()
        XCTAssertGreaterThan(ms, 1_577_836_800_000, "currentTimeMillis should be after 2020-01-01")
    }

    func testCurrentTimeMillisNonDecreasingAcrossConsecutiveCalls() {
        // Wall clock may not be strictly monotonic (NTP), but should be
        // non-decreasing at millisecond granularity across two rapid calls.
        let t1 = kk_system_currentTimeMillis()
        let t2 = kk_system_currentTimeMillis()
        // Allow equal (same millisecond tick) but not backwards.
        XCTAssertGreaterThanOrEqual(t2, t1, "Consecutive currentTimeMillis calls must not decrease")
    }

    func testCurrentTimeMillisReturnsDifferentValuesAfterSleep() {
        let before = kk_system_currentTimeMillis()
        Thread.sleep(forTimeInterval: 0.020) // 20ms — well above 1ms resolution
        let after = kk_system_currentTimeMillis()
        XCTAssertGreaterThan(after, before, "currentTimeMillis should advance after a 20ms sleep")
    }

    // MARK: - kk_system_nanoTime (monotonic)

    func testNanoTimeIsPositive() {
        let t = kk_system_nanoTime()
        XCTAssertGreaterThan(t, 0, "nanoTime must be positive")
    }

    func testNanoTimeIsStrictlyMonotonicAcrossConsecutiveCalls() {
        // mach_absolute_time is strictly monotonic; two successive reads should differ.
        let t1 = kk_system_nanoTime()
        let t2 = kk_system_nanoTime()
        // t2 >= t1 is the hard requirement. t2 > t1 is expected on any real hardware.
        XCTAssertGreaterThanOrEqual(t2, t1, "nanoTime must be non-decreasing (monotonic)")
    }

    func testNanoTimeAdvancesMeasurably() {
        let t1 = kk_system_nanoTime()
        Thread.sleep(forTimeInterval: 0.010) // 10ms
        let t2 = kk_system_nanoTime()
        let delta = t2 - t1
        // Expect at least 5ms worth of nanoseconds to account for scheduling jitter.
        XCTAssertGreaterThan(delta, 5_000_000, "nanoTime should advance by > 5ms after a 10ms sleep")
    }

    func testNanoTimeIsConsistentWithMonotonicClock() {
        // Verify nanoTime is backed by monotonic clock by checking many successive readings.
        var previous = kk_system_nanoTime()
        for _ in 0..<100 {
            let current = kk_system_nanoTime()
            XCTAssertGreaterThanOrEqual(current, previous, "nanoTime went backwards — not monotonic")
            previous = current
        }
    }

    // MARK: - kk_system_process_start_nanos (stability)

    func testProcessStartNanosIsStableAcrossManyCalls() {
        let baseline = kk_system_process_start_nanos()
        for _ in 0..<20 {
            XCTAssertEqual(kk_system_process_start_nanos(), baseline,
                           "processStartNanos must be immutable after initialisation")
        }
    }

    func testProcessStartNanosIsBeforeCurrentNanoTime() {
        let start = kk_system_process_start_nanos()
        let now = kk_system_nanoTime()
        XCTAssertLessThanOrEqual(start, now, "processStartNanos must not be in the future")
    }

    func testProcessStartNanosIsNonNegative() {
        XCTAssertGreaterThanOrEqual(kk_system_process_start_nanos(), 0)
    }

    // MARK: - kk_system_measureTimeMillis

    func testMeasureTimeMillisZeroWorkIsNonNegative() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(ms, 0, "measureTimeMillis for zero-work block must be >= 0")
    }

    func testMeasureTimeMillisWithSleepIsPlausible() {
        // 10ms sleep should produce >= 5ms (allowing scheduling jitter) and < 500ms
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(ms, 5, "measureTimeMillis should capture at least ~5ms of a 10ms sleep")
        XCTAssertLessThan(ms, 500, "measureTimeMillis should not exceed 500ms for a 10ms sleep")
    }

    func testMeasureTimeMillisExceptionReturnsZero() {
        // Kotlin spec: if block throws, exception propagates and no return value.
        // Runtime maps this as: outThrown is set, return value is 0.
        let fnPtr = unsafeBitCast(systemThrowingThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "Exception sentinel must be propagated via outThrown")
        XCTAssertEqual(thrown, 0xDEAD, "outThrown must carry the exact exception value")
        XCTAssertEqual(ms, 0, "Return value must be 0 when block throws")
    }

    func testMeasureTimeMillisOutThrownResetBeforeInvocation() {
        // Verify outThrown is cleared to 0 before the block runs.
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0xBEEF  // garbage pre-fill
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0, "outThrown must be cleared for a non-throwing block")
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testMeasureTimeMillisClosureRawPassthrough() {
        systemCapturedRaw = 0
        let fnPtr = unsafeBitCast(systemCaptureThunk, to: Int.self)
        var thrown: Int = 0
        _ = kk_system_measureTimeMillis(fnPtr, 42, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(systemCapturedRaw, 42, "measureTimeMillis must forward closureRaw to the thunk")
    }

    func testMeasureTimeMillisNilOutThrownDoesNotCrash() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        let ms = kk_system_measureTimeMillis(fnPtr, 0, nil)
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testMeasureTimeMillisConsecutiveCallsAreIndependent() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown1: Int = 0
        var thrown2: Int = 0
        let ms1 = kk_system_measureTimeMillis(fnPtr, 0, &thrown1)
        let ms2 = kk_system_measureTimeMillis(fnPtr, 0, &thrown2)
        XCTAssertEqual(thrown1, 0)
        XCTAssertEqual(thrown2, 0)
        // Both should be non-negative; exact values may differ.
        XCTAssertGreaterThanOrEqual(ms1, 0)
        XCTAssertGreaterThanOrEqual(ms2, 0)
    }

    // MARK: - kk_system_measureNanoTime

    func testMeasureNanoTimeZeroWorkIsNonNegative() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(ns, 0, "measureNanoTime for zero-work block must be >= 0")
    }

    func testMeasureNanoTimeWithSleepIsPlausible() {
        // 10ms sleep -> expect >= 5_000_000 ns (5ms) and < 500_000_000 ns (500ms)
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(ns, 5_000_000, "measureNanoTime should capture >= 5ms of a 10ms sleep")
        XCTAssertLessThan(ns, 500_000_000, "measureNanoTime should not exceed 500ms for a 10ms sleep")
    }

    func testMeasureNanoTimeExceptionReturnsZero() {
        let fnPtr = unsafeBitCast(systemThrowingThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "Exception sentinel must be propagated via outThrown")
        XCTAssertEqual(thrown, 0xDEAD)
        XCTAssertEqual(ns, 0, "Return value must be 0 when block throws")
    }

    func testMeasureNanoTimeOutThrownResetBeforeInvocation() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0xBEEF
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0, "outThrown must be cleared for a non-throwing block")
        XCTAssertGreaterThanOrEqual(ns, 0)
    }

    func testMeasureNanoTimeClosureRawPassthrough() {
        systemCapturedRaw = 0
        let fnPtr = unsafeBitCast(systemCaptureThunk, to: Int.self)
        var thrown: Int = 0
        _ = kk_system_measureNanoTime(fnPtr, 99, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(systemCapturedRaw, 99, "measureNanoTime must forward closureRaw to the thunk")
    }

    func testMeasureNanoTimeNilOutThrownDoesNotCrash() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        let ns = kk_system_measureNanoTime(fnPtr, 0, nil)
        XCTAssertGreaterThanOrEqual(ns, 0)
    }

    func testMeasureNanoTimeIsMonotonicRelativeToNanoTime() {
        // measureNanoTime elapsed must be <= actual wall-clock delta + slack.
        let before = kk_system_nanoTime()
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let measured = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        let after = kk_system_nanoTime()
        XCTAssertEqual(thrown, 0)
        let wall = after - before
        // measured <= wall (plus a 2ms slack for measurement overhead)
        let slackNs = 2_000_000
        XCTAssertLessThanOrEqual(measured, wall + slackNs,
            "measureNanoTime elapsed should not exceed enclosing wall-clock time")
    }

    func testMeasureNanoTimeExceedsMillisPrecision() {
        // nanoTime should provide sub-millisecond precision; verify it's not
        // constrained to millisecond granularity like measureTimeMillis.
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        var hasSubMillisecond = false
        for _ in 0..<20 {
            let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
            if ns > 0 && ns < 1_000_000 { // 0 < ns < 1ms
                hasSubMillisecond = true
                break
            }
        }
        XCTAssertTrue(hasSubMillisecond,
            "measureNanoTime should occasionally return sub-millisecond values for a noop block")
    }

    // MARK: - exitProcess compile-time visibility

    func testExitProcessSymbolIsVisible() {
        // We cannot call exit() in a test (it terminates the process).
        // Verify the symbol is accessible at compile time by referencing its type.
        // The type `(Int) -> Never` matches Kotlin's Nothing semantics.
        let _: (Int) -> Never = kk_system_exitProcess
        // If this line compiles, the symbol is correctly exported.
    }
}
