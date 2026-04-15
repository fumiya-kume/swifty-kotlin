import Foundation
@testable import Runtime
import XCTest

private let runtimeReadWriteLockStateLock = NSLock()
nonisolated(unsafe) private var _runtimeReadWriteLockActiveReaders = 0
nonisolated(unsafe) private var _runtimeReadWriteLockMaxReaders = 0
nonisolated(unsafe) private var runtimeReadWriteLockReadEnteredSemaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) private var runtimeReadWriteLockReadReleaseSemaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) private var runtimeReadWriteLockWriterEnteredSemaphore = DispatchSemaphore(value: 0)

private var runtimeReadWriteLockActiveReaders: Int {
    get {
        runtimeReadWriteLockStateLock.lock()
        defer { runtimeReadWriteLockStateLock.unlock() }
        return _runtimeReadWriteLockActiveReaders
    }
    set {
        runtimeReadWriteLockStateLock.lock()
        defer { runtimeReadWriteLockStateLock.unlock() }
        _runtimeReadWriteLockActiveReaders = newValue
    }
}

private var runtimeReadWriteLockMaxReaders: Int {
    get {
        runtimeReadWriteLockStateLock.lock()
        defer { runtimeReadWriteLockStateLock.unlock() }
        return _runtimeReadWriteLockMaxReaders
    }
    set {
        runtimeReadWriteLockStateLock.lock()
        defer { runtimeReadWriteLockStateLock.unlock() }
        _runtimeReadWriteLockMaxReaders = newValue
    }
}

@_cdecl("runtime_read_write_lock_passthrough")
private func runtime_read_write_lock_passthrough(
    _ closureRaw: Int
) -> Int {
    return 123
}

@_cdecl("runtime_read_write_lock_reader")
private func runtime_read_write_lock_reader(
    _ closureRaw: Int
) -> Int {
    runtimeReadWriteLockStateLock.lock()
    _runtimeReadWriteLockActiveReaders += 1
    _runtimeReadWriteLockMaxReaders = max(_runtimeReadWriteLockMaxReaders, _runtimeReadWriteLockActiveReaders)
    runtimeReadWriteLockStateLock.unlock()

    runtimeReadWriteLockReadEnteredSemaphore.signal()
    guard runtimeReadWriteLockReadReleaseSemaphore.wait(timeout: .now() + .seconds(5)) == .success else {
        return 0
    }

    runtimeReadWriteLockStateLock.lock()
    _runtimeReadWriteLockActiveReaders -= 1
    runtimeReadWriteLockStateLock.unlock()
    return 77
}

@_cdecl("runtime_read_write_lock_writer")
private func runtime_read_write_lock_writer(
    _ closureRaw: Int
) -> Int {
    runtimeReadWriteLockWriterEnteredSemaphore.signal()
    return 99
}

final class RuntimeReadWriteLockLegacyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        runtimeReadWriteLockStateLock.lock()
        _runtimeReadWriteLockActiveReaders = 0
        _runtimeReadWriteLockMaxReaders = 0
        runtimeReadWriteLockStateLock.unlock()
        runtimeReadWriteLockReadEnteredSemaphore = DispatchSemaphore(value: 0)
        runtimeReadWriteLockReadReleaseSemaphore = DispatchSemaphore(value: 0)
        runtimeReadWriteLockWriterEnteredSemaphore = DispatchSemaphore(value: 0)
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testReadWriteLockReturnsActionResult() {
        let lock = kk_read_write_lock_create()
        let fn = unsafeBitCast(
            runtime_read_write_lock_passthrough as @convention(c) (Int) -> Int,
            to: Int.self
        )

        XCTAssertEqual(kk_read_write_lock_read(lock, fn, 0), 123)
        XCTAssertEqual(kk_read_write_lock_write(lock, fn, 0), 123)
    }

    func testReadWriteLockAllowsConcurrentReaders() {
        let lock = kk_read_write_lock_create()
        let fn = unsafeBitCast(
            runtime_read_write_lock_reader as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, fn, 0)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, fn, 0)
            group.leave()
        }

        XCTAssertEqual(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)), .success)
        XCTAssertEqual(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)), .success)
        runtimeReadWriteLockStateLock.lock()
        let maxReaders = _runtimeReadWriteLockMaxReaders
        runtimeReadWriteLockStateLock.unlock()
        XCTAssertGreaterThanOrEqual(maxReaders, 2)

        runtimeReadWriteLockReadReleaseSemaphore.signal()
        runtimeReadWriteLockReadReleaseSemaphore.signal()
        XCTAssertEqual(group.wait(timeout: .now() + .seconds(2)), .success)
    }

    func testReadWriteLockBlocksWriterWhileReaderIsHeld() {
        let lock = kk_read_write_lock_create()
        let readerFn = unsafeBitCast(
            runtime_read_write_lock_reader as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let writerFn = unsafeBitCast(
            runtime_read_write_lock_writer as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let readerGroup = DispatchGroup()
        let writerGroup = DispatchGroup()

        readerGroup.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, readerFn, 0)
            readerGroup.leave()
        }

        XCTAssertEqual(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)), .success)

        writerGroup.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_write(lock, writerFn, 0)
            writerGroup.leave()
        }

        XCTAssertEqual(runtimeReadWriteLockWriterEnteredSemaphore.wait(timeout: .now() + .milliseconds(200)), .timedOut)

        runtimeReadWriteLockReadReleaseSemaphore.signal()
        XCTAssertEqual(runtimeReadWriteLockWriterEnteredSemaphore.wait(timeout: .now() + .seconds(2)), .success)
        XCTAssertEqual(readerGroup.wait(timeout: .now() + .seconds(2)), .success)
        XCTAssertEqual(writerGroup.wait(timeout: .now() + .seconds(2)), .success)
    }
}

nonisolated(unsafe) private var readWriteLockHandle: Int = 0
nonisolated(unsafe) private var capturedReadClosureRaw: Int = 0

private let readEchoThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, outThrown in
    capturedReadClosureRaw = closureRaw
    outThrown?.pointee = 0
    return closureRaw
}

private let readThrowingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xC0DE
    return 0
}

private let readNestedThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, outThrown in
    var innerThrown = 0
    let innerResult = kk_reentrant_read_write_lock_read(
        readWriteLockHandle,
        unsafeBitCast(readEchoThunk, to: Int.self),
        closureRaw + 1,
        &innerThrown
    )
    if innerThrown != 0 {
        outThrown?.pointee = innerThrown
        return 0
    }
    outThrown?.pointee = 0
    return innerResult + 1
}

final class RuntimeReadWriteLockTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        readWriteLockHandle = 0
        capturedReadClosureRaw = 0
    }

    func testConstructorAndReadPassThroughClosureRaw() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        var thrown = 0
        let fnPtr = unsafeBitCast(readEchoThunk, to: Int.self)
        let sentinel = 0x1234
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, sentinel, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, sentinel)
        XCTAssertEqual(capturedReadClosureRaw, sentinel)
    }

    func testReadPropagatesThrownValues() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        var thrown = 0
        let fnPtr = unsafeBitCast(readThrowingThunk, to: Int.self)
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, 0, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(thrown, 0xC0DE)
    }

    func testReadIsReentrantForTheSameHandle() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        capturedReadClosureRaw = 0
        var thrown = 0
        let fnPtr = unsafeBitCast(readNestedThunk, to: Int.self)
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, 0x20, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0x22)
        XCTAssertEqual(capturedReadClosureRaw, 0x21)
    }
}
