import Dispatch
import Foundation
@testable import Runtime
import XCTest

private func withThreadLocalTestTypeInfo(
    fieldOffsets: [UInt32],
    body: (UnsafePointer<KTypeInfo>) -> Void
) {
    let typeName = Array("ThreadLocal.Test.Type\0".utf8).map(CChar.init)
    let offsetStorage = fieldOffsets.isEmpty ? [UInt32(0)] : fieldOffsets
    var emptyVtableEntry = UnsafeRawPointer(bitPattern: 0x1)!

    typeName.withUnsafeBufferPointer { nameBuffer in
        offsetStorage.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &emptyVtableEntry) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: UInt32(fieldOffsets.count),
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 0,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo, body)
            }
        }
    }
}

private func withThreadLocalDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    withThreadLocalTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
        body(UnsafeRawPointer(typeInfoPtr))
    }
}

private final class ThreadLocalThunkState: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var configuredReturnValue = 0

    func reset() {
        lock.lock()
        callCount = 0
        configuredReturnValue = 0
        lock.unlock()
    }

    func incrementingValue() -> Int {
        lock.lock()
        callCount += 1
        let value = callCount
        lock.unlock()
        return value
    }

    func configuredValue() -> Int {
        lock.lock()
        callCount += 1
        let value = configuredReturnValue
        lock.unlock()
        return value
    }

    func setConfiguredReturnValue(_ value: Int) {
        lock.lock()
        configuredReturnValue = value
        lock.unlock()
    }

    func callCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
}

private let threadLocalThunkState = ThreadLocalThunkState()

private let incrementingThreadLocalThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    threadLocalThunkState.incrementingValue()
}

private let configuredThreadLocalThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    threadLocalThunkState.configuredValue()
}

private let incrementingThreadLocalThunkPtr = unsafeBitCast(incrementingThreadLocalThunk, to: Int.self)
private let configuredThreadLocalThunkPtr = unsafeBitCast(configuredThreadLocalThunk, to: Int.self)

private final class ThreadLocalBackgroundValueBox: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<Int>

    init(initialValue: Int) {
        pointer = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        pointer.initialize(to: initialValue)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

final class RuntimeThreadLocalTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        threadLocalThunkState.reset()
    }

    func testGetOrSetCachesWithinSameThread() {
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(threadLocalThunkState.callCountSnapshot(), 1)
    }

    func testGetOrSetIsThreadLocalAcrossThreads() {
        let receiver = kk_thread_local_new()

        let mainValue = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        let backgroundValue = ThreadLocalBackgroundValueBox(initialValue: -1)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            backgroundValue.pointer.pointee = kk_thread_local_getOrSet(
                receiver,
                incrementingThreadLocalThunkPtr,
                0,
                nil as UnsafeMutablePointer<Int>?
            )
            group.leave()
        }
        XCTAssertEqual(group.wait(timeout: .now() + .seconds(5)), .success)

        let secondMainValue = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        XCTAssertEqual(mainValue, 1)
        XCTAssertEqual(backgroundValue.pointer.pointee, 2)
        XCTAssertEqual(secondMainValue, 1)
        XCTAssertEqual(threadLocalThunkState.callCountSnapshot(), 2)
    }

    func testGetOrSetDoesNotCacheRuntimeNullSentinel() {
        threadLocalThunkState.setConfiguredReturnValue(runtimeNullSentinelInt)
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        XCTAssertEqual(first, runtimeNullSentinelInt)
        XCTAssertEqual(second, runtimeNullSentinelInt)
        XCTAssertEqual(threadLocalThunkState.callCountSnapshot(), 2)
    }

    func testGetOrSetCachesZero() {
        threadLocalThunkState.setConfiguredReturnValue(0)
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(threadLocalThunkState.callCountSnapshot(), 1)
    }

    func testGetOrSetKeepsAllocatedObjectAliveAcrossGC() {
        withThreadLocalDummyTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectHandle = Int(bitPattern: object)
            threadLocalThunkState.setConfiguredReturnValue(objectHandle)
            let receiver = kk_thread_local_new()

            let stored = kk_thread_local_getOrSet(
                receiver,
                configuredThreadLocalThunkPtr,
                0,
                nil as UnsafeMutablePointer<Int>?
            )

            XCTAssertEqual(stored, objectHandle)
            XCTAssertEqual(threadLocalThunkState.callCountSnapshot(), 1)
            XCTAssertEqual(kk_runtime_heap_object_count(), 1)

            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 1)
        }
    }
}
