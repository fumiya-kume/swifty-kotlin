import Dispatch
import Foundation
@testable import Runtime
import XCTest

private final class DelegateCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var lazyCallCount = 0
    private var observableCapturedOld = -1
    private var observableCapturedNew = -1
    private var observableHandle: Int = 0
    private var observableValueInsideCallback = -1
    private var vetoableHandle: Int = 0
    private var vetoableValueInsideCallback = -1

    func reset() {
        lock.lock()
        lazyCallCount = 0
        observableCapturedOld = -1
        observableCapturedNew = -1
        observableHandle = 0
        observableValueInsideCallback = -1
        vetoableHandle = 0
        vetoableValueInsideCallback = -1
        lock.unlock()
    }

    func incrementLazyCallCount() {
        lock.lock()
        lazyCallCount += 1
        lock.unlock()
    }

    func lazyCallCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return lazyCallCount
    }

    func setObservableCaptured(old: Int, new: Int) {
        lock.lock()
        observableCapturedOld = old
        observableCapturedNew = new
        lock.unlock()
    }

    func observableCapturedOldSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableCapturedOld
    }

    func observableCapturedNewSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableCapturedNew
    }

    func setObservableHandle(_ value: Int) {
        lock.lock()
        observableHandle = value
        lock.unlock()
    }

    func observableHandleSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableHandle
    }

    func setObservableValueInsideCallback(_ value: Int) {
        lock.lock()
        observableValueInsideCallback = value
        lock.unlock()
    }

    func observableValueInsideCallbackSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableValueInsideCallback
    }

    func setVetoableHandle(_ value: Int) {
        lock.lock()
        vetoableHandle = value
        lock.unlock()
    }

    func vetoableHandleSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return vetoableHandle
    }

    func setVetoableValueInsideCallback(_ value: Int) {
        lock.lock()
        vetoableValueInsideCallback = value
        lock.unlock()
    }

    func vetoableValueInsideCallbackSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return vetoableValueInsideCallback
    }
}

private final class LazyPublicationCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var enteredSemaphore = DispatchSemaphore(value: 0)
    private var releaseSemaphore = DispatchSemaphore(value: 0)

    func reset() {
        lock.lock()
        callCount = 0
        enteredSemaphore = DispatchSemaphore(value: 0)
        releaseSemaphore = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func recordInitializerEntry() {
        lock.lock()
        callCount += 1
        lock.unlock()
        enteredSemaphore.signal()
    }

    func waitForInitializerEntries(_ count: Int, timeout: DispatchTimeInterval = .seconds(5)) -> Bool {
        for _ in 0..<count {
            if enteredSemaphore.wait(timeout: .now() + timeout) != .success {
                return false
            }
        }
        return true
    }

    func releaseInitializers(_ count: Int) {
        for _ in 0..<count {
            releaseSemaphore.signal()
        }
    }

    func waitForRelease(timeout: DispatchTimeInterval = .seconds(5)) -> Bool {
        releaseSemaphore.wait(timeout: .now() + timeout) == .success
    }

    func callCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
}

private final class AtomicIntArrayBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int]

    init(_ value: [Int]) {
        storage = value
    }

    var value: [Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    func store(_ value: Int, at index: Int) {
        lock.lock()
        storage[index] = value
        lock.unlock()
    }
}

/// Global state for callback testing (C function pointers cannot capture context).
private let gDelegateState = DelegateCallbackState()
private let gLazyPublicationState = LazyPublicationCallbackState()

private func lazyCountingInit() -> Int {
    gDelegateState.incrementLazyCallCount()
    return 99
}

private let lazyCountingInitCConv: KKThunkEntryPoint = { _ in lazyCountingInit() }

private let lazySimple42: KKThunkEntryPoint = { _ in 42 }
private let lazySimple77: KKThunkEntryPoint = { _ in 77 }
private let lazyPublicationValue: Int = 123

private func lazyPublicationInit() -> Int {
    gLazyPublicationState.recordInitializerEntry()
    guard gLazyPublicationState.waitForRelease() else {
        return 0
    }
    return lazyPublicationValue
}

private let lazyPublicationInitCConv: KKThunkEntryPoint = { _ in lazyPublicationInit() }

private let observableNoopCallback: KKDelegateObserverEntryPoint = { _, _, _, _ in 0 }
private let observableCaptureCallback: KKDelegateObserverEntryPoint = { _, old, new, _ in
    gDelegateState.setObservableCaptured(old: old, new: new)
    return 0
}

private let observableOrderCallback: KKDelegateObserverEntryPoint = { _, _, _, _ in
    let handle = gDelegateState.observableHandleSnapshot()
    gDelegateState.setObservableValueInsideCallback(kk_observable_get_value(handle))
    return 0
}

private let vetoableAcceptCallback: KKDelegateObserverEntryPoint = { _, _, _, _ in 1 }
private let vetoableRejectCallback: KKDelegateObserverEntryPoint = { _, _, _, _ in 0 }
private let vetoableOrderCallback: KKDelegateObserverEntryPoint = { _, _, _, _ in
    let handle = gDelegateState.vetoableHandleSnapshot()
    gDelegateState.setVetoableValueInsideCallback(kk_vetoable_get_value(handle))
    return 1
}

final class RuntimeDelegateTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        gDelegateState.reset()
        gLazyPublicationState.reset()
    }

    // MARK: - Lazy Delegate Tests

    func testLazyCreateReturnsNonZeroHandle() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1) // SYNCHRONIZED
        XCTAssertNotEqual(handle, 0)
    }

    func testLazyGetValueInvokesInitializerOnce() {
        let fnPtr = unsafeBitCast(lazyCountingInitCConv, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1) // SYNCHRONIZED

        let firstRead = kk_lazy_get_value(handle)
        XCTAssertEqual(firstRead, 99)
        XCTAssertEqual(gDelegateState.lazyCallCountSnapshot(), 1)

        let secondRead = kk_lazy_get_value(handle)
        XCTAssertEqual(secondRead, 99)
        XCTAssertEqual(gDelegateState.lazyCallCountSnapshot(), 1, "Initializer should only be called once")
    }

    func testLazyNoneModeAlsoWorks() {
        let fnPtr = unsafeBitCast(lazySimple77, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 0) // NONE

        let value = kk_lazy_get_value(handle)
        XCTAssertEqual(value, 77)
    }

    func testLazyGetValueWithInvalidHandleReturnsZero() {
        let value = kk_lazy_get_value(0)
        XCTAssertEqual(value, 0)
    }

    func testLazyIsInitializedReturnsFalseBeforeAccess() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)
        XCTAssertEqual(kk_lazy_is_initialized(handle), 0,
                       "Lazy should not be initialized before first access")
    }

    func testLazyIsInitializedReturnsTrueAfterAccess() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)
        _ = kk_lazy_get_value(handle)
        XCTAssertNotEqual(kk_lazy_is_initialized(handle), 0,
                          "Lazy should be initialized after first access")
    }

    func testLazyIsInitializedWithInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_lazy_is_initialized(0), 0)
    }

    func testLazyPublicationModeAllowsConcurrentInitializationButPublishesOneValue() {
        let fnPtr = unsafeBitCast(lazyPublicationInitCConv, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 2) // PUBLICATION

        let group = DispatchGroup()
        let values = AtomicIntArrayBox(Array(repeating: 0, count: 2))

        for index in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                let value = kk_lazy_get_value(handle)
                values.store(value, at: index)
                group.leave()
            }
        }

        let didObserveInitializers = gLazyPublicationState.waitForInitializerEntries(2)
        gLazyPublicationState.releaseInitializers(2)
        XCTAssertTrue(didObserveInitializers)
        XCTAssertEqual(group.wait(timeout: .now() + .seconds(5)), .success)

        XCTAssertEqual(values.value, [lazyPublicationValue, lazyPublicationValue])
        XCTAssertEqual(gLazyPublicationState.callCountSnapshot(), 2)
        XCTAssertEqual(kk_lazy_is_initialized(handle), 1)
    }

    // MARK: - Observable Delegate Tests

    func testObservableCreateAndGetValue() {
        let cbPtr = unsafeBitCast(observableNoopCallback, to: Int.self)
        let handle = kk_observable_create(10, cbPtr)
        XCTAssertNotEqual(handle, 0)

        let value = kk_observable_get_value(handle)
        XCTAssertEqual(value, 10)
    }

    func testObservableSetValueInvokesCallbackAfterChange() {
        let cbPtr = unsafeBitCast(observableCaptureCallback, to: Int.self)
        let handle = kk_observable_create(10, cbPtr)

        let result = kk_observable_set_value(handle, 20)
        XCTAssertEqual(result, 20)

        // Callback should have been invoked with old=10, new=20
        XCTAssertEqual(gDelegateState.observableCapturedOldSnapshot(), 10)
        XCTAssertEqual(gDelegateState.observableCapturedNewSnapshot(), 20)

        let current = kk_observable_get_value(handle)
        XCTAssertEqual(current, 20)
    }

    func testObservableCallbackOrderMatchesKotlinc() {
        // In kotlinc, observable callback fires AFTER the value is already changed.
        let cbPtr = unsafeBitCast(observableOrderCallback, to: Int.self)
        let handle = kk_observable_create(5, cbPtr)
        gDelegateState.setObservableHandle(handle)

        _ = kk_observable_set_value(handle, 15)
        XCTAssertEqual(gDelegateState.observableValueInsideCallbackSnapshot(), 15,
                       "Value should be updated before callback is invoked")
    }

    func testObservableGetValueWithInvalidHandleReturnsZero() {
        let value = kk_observable_get_value(0)
        XCTAssertEqual(value, 0)
    }

    // MARK: - Vetoable Delegate Tests

    func testVetoableCreateAndGetValue() {
        let cbPtr = unsafeBitCast(vetoableAcceptCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)
        XCTAssertNotEqual(handle, 0)

        let value = kk_vetoable_get_value(handle)
        XCTAssertEqual(value, 100)
    }

    func testVetoableAcceptsChangeWhenCallbackReturnsNonZero() {
        let cbPtr = unsafeBitCast(vetoableAcceptCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)

        let result = kk_vetoable_set_value(handle, 200)
        XCTAssertEqual(result, 200)

        let current = kk_vetoable_get_value(handle)
        XCTAssertEqual(current, 200)
    }

    func testVetoableRejectsChangeWhenCallbackReturnsZero() {
        let cbPtr = unsafeBitCast(vetoableRejectCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)

        let result = kk_vetoable_set_value(handle, 200)
        XCTAssertEqual(result, 100, "Value should remain unchanged when vetoed")

        let current = kk_vetoable_get_value(handle)
        XCTAssertEqual(current, 100)
    }

    func testVetoableCallbackOrderMatchesKotlinc() {
        // In kotlinc, vetoable callback fires BEFORE the value is changed.
        let cbPtr = unsafeBitCast(vetoableOrderCallback, to: Int.self)
        let handle = kk_vetoable_create(50, cbPtr)
        gDelegateState.setVetoableHandle(handle)

        _ = kk_vetoable_set_value(handle, 60)
        XCTAssertEqual(gDelegateState.vetoableValueInsideCallbackSnapshot(), 50,
                       "Value should NOT be updated before vetoable callback")
    }

    func testVetoableGetValueWithInvalidHandleReturnsZero() {
        let value = kk_vetoable_get_value(0)
        XCTAssertEqual(value, 0)
    }

    // MARK: - NotNull Delegate Tests

    func testNotNullSetThenGetReturnsAssignedValue() {
        let handle = kk_notNull_create()
        XCTAssertNotEqual(handle, 0)

        let written = kk_notNull_set_value(handle, 321)
        XCTAssertEqual(written, 321)

        var outThrown: Int = 0
        let current = kk_notNull_get_value(handle, &outThrown)
        XCTAssertEqual(outThrown, 0, "No exception should be thrown after assignment")
        XCTAssertEqual(current, 321)
    }

    // STDLIB-PROP-ABI-001: reads-before-assignment must throw IllegalStateException,
    // not crash with fatalError, so that tests and catch blocks can recover.
    func testNotNullGetBeforeSetThrowsIllegalStateException() {
        let handle = kk_notNull_create()
        XCTAssertNotEqual(handle, 0)

        var outThrown: Int = 0
        let result = kk_notNull_get_value(handle, &outThrown)

        XCTAssertEqual(result, 0, "Return value should be 0 on exception path")
        XCTAssertNotEqual(outThrown, 0, "outThrown must be set when property is uninitialized")

        // Verify the thrown object is an IllegalStateException with the correct message.
        guard let ptr = UnsafeMutableRawPointer(bitPattern: outThrown),
              let box = tryCast(ptr, to: RuntimeIllegalStateExceptionBox.self)
        else {
            XCTFail("outThrown must be a RuntimeIllegalStateExceptionBox (STDLIB-PROP-ABI-001)")
            return
        }
        XCTAssertTrue(
            box.message.contains("should be initialized before get"),
            "Message '\(box.message)' must match Kotlin spec wording"
        )
    }
}
