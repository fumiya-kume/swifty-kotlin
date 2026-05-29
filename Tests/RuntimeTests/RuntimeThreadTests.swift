import Foundation
@testable import Runtime
import XCTest

private final class RuntimeThreadLaunchState: @unchecked Sendable {
    private let condition = NSCondition()
    private var launchCount = 0
    private var lastThreadName: String?
    private var lastThreadPriority: Double?

    func reset() {
        condition.lock()
        launchCount = 0
        lastThreadName = nil
        lastThreadPriority = nil
        condition.broadcast()
        condition.unlock()
    }

    func record(_ thread: Thread) {
        condition.lock()
        launchCount += 1
        lastThreadName = thread.name
        #if canImport(ObjectiveC)
        lastThreadPriority = thread.threadPriority
        #else
        lastThreadPriority = nil
        #endif
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> (launchCount: Int, lastThreadName: String?, lastThreadPriority: Double?) {
        condition.lock()
        defer { condition.unlock() }
        return (launchCount, lastThreadName, lastThreadPriority)
    }

    func waitForLaunch(after baseline: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while launchCount <= baseline {
            if !condition.wait(until: deadline) {
                return launchCount > baseline
            }
        }
        return true
    }
}

private let runtimeThreadLaunchState = RuntimeThreadLaunchState()

private let runtimeThreadThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    runtimeThreadLaunchState.record(Thread.current)
    return 0
}

private let runtimeThreadThunkPtr = unsafeBitCast(runtimeThreadThunk, to: Int.self)

final class RuntimeThreadTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    override func resetIsolatedRuntimeTestState() {
        runtimeThreadLaunchState.reset()
    }

    private func stringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func threadObject(from raw: Int) -> RuntimeManagedThread {
        let pointer = UnsafeMutableRawPointer(bitPattern: raw)
        return Unmanaged<RuntimeManagedThread>.fromOpaque(pointer!).takeUnretainedValue()
    }

    private func foundationThread(from raw: Int) -> Thread {
        let pointer = UnsafeMutableRawPointer(bitPattern: raw)
        return Unmanaged<Thread>.fromOpaque(pointer!).takeUnretainedValue()
    }

    func testThreadCreateStartsImmediatelyWhenRequested() throws {
        let baseline = runtimeThreadLaunchState.snapshot().launchCount
        let raw = kk_thread_create(
            1,
            1,
            runtimeNullSentinelInt,
            stringRaw("worker"),
            7,
            runtimeThreadThunkPtr,
            0
        )
        let createdThread = threadObject(from: raw)

        XCTAssertEqual(createdThread.name, "worker")
        XCTAssertGreaterThan(createdThread.threadPriority, 0.6)
        XCTAssertLessThan(createdThread.threadPriority, 0.8)

        XCTAssertTrue(runtimeThreadLaunchState.waitForLaunch(after: baseline))
        let snapshot = runtimeThreadLaunchState.snapshot()
        XCTAssertEqual(snapshot.launchCount, baseline + 1)
        #if canImport(ObjectiveC)
        XCTAssertEqual(snapshot.lastThreadName, "worker")
        XCTAssertEqual(
            try XCTUnwrap(snapshot.lastThreadPriority),
            createdThread.threadPriority,
            accuracy: 0.0001
        )
        #endif

        let launchBox = try XCTUnwrap(createdThread.launchBox)
        XCTAssertEqual(launchBox.isDaemon, true)
        XCTAssertEqual(launchBox.contextClassLoaderRaw, runtimeNullSentinelInt)
        XCTAssertEqual(launchBox.priority, 7)
    }

    func testThreadCreateDefersExecutionUntilStart() throws {
        let baseline = runtimeThreadLaunchState.snapshot().launchCount
        let raw = kk_thread_create(
            0,
            0,
            runtimeNullSentinelInt,
            stringRaw("manual"),
            5,
            runtimeThreadThunkPtr,
            0
        )
        let createdThread = threadObject(from: raw)

        XCTAssertEqual(createdThread.name, "manual")
        XCTAssertGreaterThan(createdThread.threadPriority, 0.4)
        XCTAssertLessThan(createdThread.threadPriority, 0.6)

        let launchBox = try XCTUnwrap(createdThread.launchBox)
        XCTAssertEqual(launchBox.isDaemon, false)
        XCTAssertEqual(launchBox.contextClassLoaderRaw, runtimeNullSentinelInt)
        XCTAssertEqual(launchBox.priority, 5)

        XCTAssertEqual(runtimeThreadLaunchState.snapshot().launchCount, baseline)

        createdThread.start()

        XCTAssertTrue(runtimeThreadLaunchState.waitForLaunch(after: baseline))
        let snapshot = runtimeThreadLaunchState.snapshot()
        XCTAssertEqual(snapshot.launchCount, baseline + 1)
        #if canImport(ObjectiveC)
        XCTAssertEqual(snapshot.lastThreadName, "manual")
        XCTAssertEqual(
            try XCTUnwrap(snapshot.lastThreadPriority),
            createdThread.threadPriority,
            accuracy: 0.0001
        )
        #endif
    }

    func testCurrentThreadReturnsCurrentFoundationThread() {
        let raw = kk_thread_currentThread()
        XCTAssertNotEqual(raw, 0)

        let thread = foundationThread(from: raw)
        XCTAssertEqual(thread.isMainThread, Thread.current.isMainThread)
    }

    func testThreadSleepAcceptsZeroDuration() {
        XCTAssertEqual(kk_thread_sleep(0), 0)
    }

    func testThreadJoinWaitsForStartedManagedThread() {
        let baseline = runtimeThreadLaunchState.snapshot().launchCount
        let raw = kk_thread_create(
            1,
            0,
            runtimeNullSentinelInt,
            stringRaw("join-worker"),
            5,
            runtimeThreadThunkPtr,
            0
        )

        XCTAssertEqual(kk_thread_join(raw), 0)
        XCTAssertGreaterThanOrEqual(runtimeThreadLaunchState.snapshot().launchCount, baseline + 1)
    }

    func testThreadJoinOnCurrentThreadReturnsImmediately() {
        let raw = kk_thread_currentThread()
        XCTAssertEqual(kk_thread_join(raw), 0)
    }
}
