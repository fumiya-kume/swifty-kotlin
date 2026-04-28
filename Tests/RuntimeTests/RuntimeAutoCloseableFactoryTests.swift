import Foundation
@testable import Runtime
import XCTest

private final class AutoCloseableFactoryTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var closeCount = 0
    private var lastClosureRaw = 0

    func reset() {
        lock.lock()
        closeCount = 0
        lastClosureRaw = 0
        lock.unlock()
    }

    func recordClose(closureRaw: Int) {
        lock.lock()
        closeCount += 1
        lastClosureRaw = closureRaw
        lock.unlock()
    }

    func snapshot() -> (count: Int, closureRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (closeCount, lastClosureRaw)
    }
}

private let autoCloseableFactoryState = AutoCloseableFactoryTestState()
private let autoCloseableCloseMessage = "factory close failure"

private let autoCloseableCloseAction: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, _ in
    autoCloseableFactoryState.recordClose(closureRaw: closureRaw)
    return 0
}

private let autoCloseableThrowingCloseAction: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: autoCloseableCloseMessage)
    return runtimeExceptionCaughtSentinel
}

private let autoCloseableUseBody: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    99
}

private func autoCloseableThrowableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard handle != 0,
          handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

final class RuntimeAutoCloseableFactoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        autoCloseableFactoryState.reset()
    }

    func testFactoryRegistersCloseMethod() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableCloseAction, to: Int.self),
            41
        )
        let closeFnPtr = kk_itable_lookup(resourceRaw, 0, 0)
        XCTAssertNotEqual(closeFnPtr, 0)

        let closeFn = unsafeBitCast(closeFnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var outThrown = 0
        let result = closeFn(resourceRaw, &outThrown)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(outThrown, 0)
        let snapshot = autoCloseableFactoryState.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.closureRaw, 41)
    }

    func testUseClosesFactoryResourceAfterBody() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableCloseAction, to: Int.self),
            77
        )

        var outThrown = 0
        let result = kk_use(
            resourceRaw,
            unsafeBitCast(autoCloseableUseBody, to: Int.self),
            0,
            &outThrown
        )

        XCTAssertEqual(result, 99)
        XCTAssertEqual(outThrown, 0)
        let snapshot = autoCloseableFactoryState.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.closureRaw, 77)
    }

    func testUsePropagatesFactoryCloseException() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableThrowingCloseAction, to: Int.self),
            0
        )

        var outThrown = 0
        let result = kk_use(
            resourceRaw,
            unsafeBitCast(autoCloseableUseBody, to: Int.self),
            0,
            &outThrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertEqual(autoCloseableThrowableBox(from: outThrown)?.message, autoCloseableCloseMessage)
    }
}
