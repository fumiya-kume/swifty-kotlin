import Foundation
@testable import Runtime
import XCTest

private nonisolated(unsafe) let runtimeReadWriteLockStateLock = NSLock()
private nonisolated(unsafe) var runtimeReadWriteLockActiveReaders = 0
private nonisolated(unsafe) var runtimeReadWriteLockMaxReaders = 0
private nonisolated(unsafe) var runtimeReadWriteLockReadEnteredSemaphore = DispatchSemaphore(value: 0)
private nonisolated(unsafe) var runtimeReadWriteLockReadReleaseSemaphore = DispatchSemaphore(value: 0)
private nonisolated(unsafe) var runtimeReadWriteLockWriterEnteredSemaphore = DispatchSemaphore(value: 0)

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
    runtimeReadWriteLockActiveReaders += 1
    runtimeReadWriteLockMaxReaders = max(runtimeReadWriteLockMaxReaders, runtimeReadWriteLockActiveReaders)
    runtimeReadWriteLockStateLock.unlock()

    runtimeReadWriteLockReadEnteredSemaphore.signal()
    runtimeReadWriteLockReadReleaseSemaphore.wait()

    runtimeReadWriteLockStateLock.lock()
    runtimeReadWriteLockActiveReaders -= 1
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

final class RuntimeReadWriteLockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        runtimeReadWriteLockStateLock.lock()
        runtimeReadWriteLockActiveReaders = 0
        runtimeReadWriteLockMaxReaders = 0
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
        XCTAssertGreaterThanOrEqual(runtimeReadWriteLockMaxReaders, 2)

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
