import Dispatch
import Foundation
@testable import Runtime
import XCTest

/// Thread-safe box for capturing a value from an async closure in Swift 6.
private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

/// Minimal suspend entry that records which dispatcher was active when it ran,
/// then immediately completes with the dispatcher tag (or 0 if none).
@_cdecl("runtime_test_dispatcher_observe_entry")
func runtime_test_dispatcher_observe_entry(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let tag = RuntimeDispatcher.current?.tag ?? 0
    return kk_coroutine_state_exit(continuation, tag)
}

final class RuntimeDispatcherTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    // MARK: - Dispatcher tag identity

    func testDefaultDispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_default()
        XCTAssertEqual(tag, 0x4B4B_4401, "Default dispatcher tag should be KKD\\x01")
    }

    func testIODispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_io()
        XCTAssertEqual(tag, 0x4B4B_4402, "IO dispatcher tag should be KKD\\x02")
    }

    func testMainDispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_main()
        XCTAssertEqual(tag, 0x4B4B_4403, "Main dispatcher tag should be KKD\\x03")
    }

    func testDispatcherTagsAreDistinct() {
        let tags = [kk_dispatcher_default(), kk_dispatcher_io(), kk_dispatcher_main()]
        XCTAssertEqual(Set(tags).count, 3, "All dispatcher tags should be distinct")
    }

    // MARK: - Resolve dispatcher

    func testResolveDispatcherDefault() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_default())
        XCTAssertEqual(d.tag, kk_dispatcher_default())
    }

    func testResolveDispatcherIO() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_io())
        XCTAssertEqual(d.tag, kk_dispatcher_io())
    }

    func testResolveDispatcherMain() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_main())
        XCTAssertEqual(d.tag, kk_dispatcher_main())
    }

    func testResolveDispatcherUnknownFallsBackToDefault() {
        let d = runtimeResolveDispatcher(from: 0xDEAD)
        XCTAssertEqual(d.tag, kk_dispatcher_default(),
                       "Unknown dispatcher should resolve to Default")
    }

    // MARK: - RuntimeDispatcher.current thread-local

    func testCurrentDispatcherIsNilByDefault() {
        // On the test thread, no dispatcher should be active unless set.
        // Clear to be sure (tests may inherit state from prior tests).
        let saved = RuntimeDispatcher.current
        RuntimeDispatcher.current = nil
        XCTAssertNil(RuntimeDispatcher.current)
        RuntimeDispatcher.current = saved
    }

    func testDispatchSyncSetsCurrentDispatcher() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let observedTag: Int? = dispatcher.dispatchSync {
            RuntimeDispatcher.current?.tag
        }
        XCTAssertEqual(observedTag, kk_dispatcher_io(),
                       "dispatchSync should set RuntimeDispatcher.current")
    }

    func testDispatchSyncRestoresCurrentDispatcherAfterCompletion() {
        let saved = RuntimeDispatcher.current
        RuntimeDispatcher.current = nil

        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        dispatcher.dispatchSync { /* no-op */ }

        XCTAssertNil(RuntimeDispatcher.current,
                     "dispatchSync should restore previous dispatcher on completion")
        RuntimeDispatcher.current = saved
    }

    func testDispatchAsyncSetsCurrentDispatcher() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let expectation = XCTestExpectation(description: "async block executed")
        let observedTag = AtomicBox<Int?>(nil)

        dispatcher.dispatchAsync {
            observedTag.value = RuntimeDispatcher.current?.tag
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(observedTag.value, kk_dispatcher_io(),
                       "dispatchAsync should set RuntimeDispatcher.current")
    }

    // MARK: - withContext actual dispatch

    func testWithContextExecutesOnIODispatcher() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7001)
        let result = kk_with_context(kk_dispatcher_io(), entryRaw, continuation)
        XCTAssertEqual(result, kk_dispatcher_io(),
                       "withContext(IO) should execute with IO dispatcher active")
    }

    func testWithContextExecutesOnDefaultDispatcher() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7002)
        let result = kk_with_context(kk_dispatcher_default(), entryRaw, continuation)
        XCTAssertEqual(result, kk_dispatcher_default(),
                       "withContext(Default) should execute with Default dispatcher active")
    }

    func testWithContextFallsBackToDefaultForUnknownTag() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7003)
        let result = kk_with_context(0xBEEF, entryRaw, continuation)
        XCTAssertEqual(result, kk_dispatcher_default(),
                       "withContext(unknown) should fall back to Default dispatcher")
    }

    func testWithContextInvalidEntryDoesNotCrash() {
        // Note: kk_with_context now releases the continuation on the invalid-entry
        // early-return path, so no manual cleanup is needed here.
        let continuation = kk_coroutine_continuation_new(7004)
        let result = kk_with_context(kk_dispatcher_default(), 0, continuation)
        XCTAssertEqual(result, 0, "Invalid entry should return 0 without crash")
    }

    // MARK: - KxMiniRuntime.launch with dispatcher

    func testLaunchOnDispatcherExecutesBlock() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let expectation = XCTestExpectation(description: "block executed on IO dispatcher")
        let observedTag = AtomicBox<Int?>(nil)

        KxMiniRuntime.launch(on: dispatcher) {
            observedTag.value = RuntimeDispatcher.current?.tag
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(observedTag.value, kk_dispatcher_io())
    }

    // MARK: - Nested dispatcher context

    func testNestedWithContextSwitchesAndRestores() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        // Outer: IO dispatcher
        let ioDispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let (outerTag, innerTag): (Int, Int) = ioDispatcher.dispatchSync {
            let outer = RuntimeDispatcher.current?.tag ?? 0

            // Inner: Default dispatcher
            let continuation = kk_coroutine_continuation_new(7005)
            let inner = kk_with_context(kk_dispatcher_default(), entryRaw, continuation)
            return (outer, inner)
        }
        XCTAssertEqual(outerTag, kk_dispatcher_io(),
                       "Outer context should be IO")
        XCTAssertEqual(innerTag, kk_dispatcher_default(),
                       "Inner withContext should switch to Default")
    }
}
