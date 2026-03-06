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

/// Global state for callback testing (C function pointers cannot capture context).
private let gDelegateState = DelegateCallbackState()

private func lazyCountingInit() -> Int {
    gDelegateState.incrementLazyCallCount()
    return 99
}

private let lazyCountingInitCConv: @convention(c) () -> Int = { lazyCountingInit() }

private let lazySimple42: @convention(c) () -> Int = { 42 }
private let lazySimple77: @convention(c) () -> Int = { 77 }

private let observableNoopCallback: @convention(c) (Int, Int, Int) -> Void = { _, _, _ in }
private let observableCaptureCallback: @convention(c) (Int, Int, Int) -> Void = { _, old, new in
    gDelegateState.setObservableCaptured(old: old, new: new)
}

private let observableOrderCallback: @convention(c) (Int, Int, Int) -> Void = { _, _, _ in
    let handle = gDelegateState.observableHandleSnapshot()
    gDelegateState.setObservableValueInsideCallback(kk_observable_get_value(handle))
}

private let vetoableAcceptCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in 1 }
private let vetoableRejectCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in 0 }
private let vetoableOrderCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in
    let handle = gDelegateState.vetoableHandleSnapshot()
    gDelegateState.setVetoableValueInsideCallback(kk_vetoable_get_value(handle))
    return 1
}

final class RuntimeDelegateTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        gDelegateState.reset()
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
}
