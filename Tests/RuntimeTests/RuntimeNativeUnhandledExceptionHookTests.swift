@testable import Runtime
import XCTest

private final class RuntimeNativeUnhandledExceptionHookTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedThrowable = 0

    func reset() {
        lock.lock()
        capturedThrowable = 0
        lock.unlock()
    }

    func record(_ throwableRaw: Int) {
        lock.lock()
        capturedThrowable = throwableRaw
        lock.unlock()
    }

    func captured() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedThrowable
    }
}

private let runtimeNativeUnhandledExceptionHookTestState = RuntimeNativeUnhandledExceptionHookTestState()

private func runtimeNativeUnhandledExceptionHook(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeNativeUnhandledExceptionHookTestState.record(throwableRaw)
    outThrown?.pointee = 0
    return 0
}

private func runtimeNativeUnhandledExceptionThrowingHook(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = throwableRaw
    return 0
}

final class RuntimeNativeUnhandledExceptionHookTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        runtimeNativeUnhandledExceptionHookTestState.reset()
        _ = kk_native_setUnhandledExceptionHook(0)
    }

    func testGetAndSetUnhandledExceptionHookRoundTrip() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        XCTAssertEqual(kk_native_getUnhandledExceptionHook(), runtimeNullSentinelInt)
        XCTAssertEqual(kk_native_setUnhandledExceptionHook(hookRaw), 0)
        XCTAssertEqual(kk_native_getUnhandledExceptionHook(), hookRaw)
        XCTAssertEqual(kk_native_setUnhandledExceptionHook(runtimeNullSentinelInt), 0)
        XCTAssertEqual(kk_native_getUnhandledExceptionHook(), runtimeNullSentinelInt)
    }

    func testProcessUnhandledExceptionInvokesRegisteredHook() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let throwableRaw = 0x1234

        _ = kk_native_setUnhandledExceptionHook(hookRaw)
        XCTAssertEqual(kk_native_processUnhandledException(throwableRaw, nil), 0)

        XCTAssertEqual(runtimeNativeUnhandledExceptionHookTestState.captured(), throwableRaw)
    }

    func testProcessUnhandledExceptionPropagatesHookThrownChannel() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionThrowingHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let throwableRaw = 0x5678
        var thrown = 0

        _ = kk_native_setUnhandledExceptionHook(hookRaw)
        XCTAssertEqual(kk_native_processUnhandledException(throwableRaw, &thrown), 0)

        XCTAssertEqual(thrown, throwableRaw)
    }

    func testProcessUnhandledExceptionNoopsWithoutHook() {
        let throwableRaw = 0x9abc

        XCTAssertEqual(kk_native_processUnhandledException(throwableRaw, nil), 0)
        XCTAssertEqual(runtimeNativeUnhandledExceptionHookTestState.captured(), 0)
    }
}
