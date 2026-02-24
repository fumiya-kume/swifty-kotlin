import XCTest
@testable import Runtime

// Global state for callback testing (C function pointers cannot capture context).
private var gLazyCallCount = 0
private var gObservableCapturedOld = -1
private var gObservableCapturedNew = -1
private var gObservableHandle: Int = 0
private var gObservableValueInsideCallback = -1
private var gVetoableHandle: Int = 0
private var gVetoableValueInsideCallback = -1

private func lazyCountingInit() -> Int {
    gLazyCallCount += 1
    return 99
}
private let lazyCountingInitCConv: @convention(c) () -> Int = { lazyCountingInit() }

private let lazySimple42: @convention(c) () -> Int = { 42 }
private let lazySimple77: @convention(c) () -> Int = { 77 }

private let observableNoopCallback: @convention(c) (Int, Int, Int) -> Void = { _, _, _ in }
private let observableCaptureCallback: @convention(c) (Int, Int, Int) -> Void = { _, old, new in
    gObservableCapturedOld = old
    gObservableCapturedNew = new
}
private let observableOrderCallback: @convention(c) (Int, Int, Int) -> Void = { _, _, _ in
    gObservableValueInsideCallback = kk_observable_get_value(gObservableHandle)
}

private let vetoableAcceptCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in 1 }
private let vetoableRejectCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in 0 }
private let vetoableOrderCallback: @convention(c) (Int, Int, Int) -> Int = { _, _, _ in
    gVetoableValueInsideCallback = kk_vetoable_get_value(gVetoableHandle)
    return 1
}

final class RuntimeDelegateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        gLazyCallCount = 0
        gObservableCapturedOld = -1
        gObservableCapturedNew = -1
        gObservableHandle = 0
        gObservableValueInsideCallback = -1
        gVetoableHandle = 0
        gVetoableValueInsideCallback = -1
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
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

        let v1 = kk_lazy_get_value(handle)
        XCTAssertEqual(v1, 99)
        XCTAssertEqual(gLazyCallCount, 1)

        let v2 = kk_lazy_get_value(handle)
        XCTAssertEqual(v2, 99)
        XCTAssertEqual(gLazyCallCount, 1, "Initializer should only be called once")
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
        XCTAssertEqual(gObservableCapturedOld, 10)
        XCTAssertEqual(gObservableCapturedNew, 20)

        let current = kk_observable_get_value(handle)
        XCTAssertEqual(current, 20)
    }

    func testObservableCallbackOrderMatchesKotlinc() {
        // In kotlinc, observable callback fires AFTER the value is already changed.
        let cbPtr = unsafeBitCast(observableOrderCallback, to: Int.self)
        gObservableHandle = kk_observable_create(5, cbPtr)

        _ = kk_observable_set_value(gObservableHandle, 15)
        XCTAssertEqual(gObservableValueInsideCallback, 15,
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
        gVetoableHandle = kk_vetoable_create(50, cbPtr)

        _ = kk_vetoable_set_value(gVetoableHandle, 60)
        XCTAssertEqual(gVetoableValueInsideCallback, 50,
                       "Value should NOT be updated before vetoable callback")
    }

    func testVetoableGetValueWithInvalidHandleReturnsZero() {
        let value = kk_vetoable_get_value(0)
        XCTAssertEqual(value, 0)
    }
}
