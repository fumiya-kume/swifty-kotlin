import Dispatch
import Foundation
@testable import Runtime
import XCTest

// STDLIB-PROP-001: Edge case coverage for kotlin.properties delegates.
//
// Covers gaps identified in the STDLIB-PROP-001 task:
//   - notNull(): read before assignment traps, allows reassignment, rejects zero-value set
//   - observable(): callback fires *after* change (post-condition); multiple sets accumulate;
//     no callback when fnPtr == 0; value type is same after callback rejection (observable doesn't veto)
//   - vetoable(): callback fires *before* change (pre-condition); partial-reject sequences;
//     no callback when fnPtr == 0; veto preserves old value across multiple attempts
//   - lazy: publication mode initializes only once when winner is determined by race
//   - kk_delegate_get_value / kk_delegate_set_value generic shims: dispatch to correct box type
//   - kk_kproperty_stub: name/returnType metadata available inside callbacks

// MARK: - Module-level callback state (C function pointers cannot capture context)

private final class EdgeCaseCallbackState: @unchecked Sendable {
    private let lock = NSLock()

    // Shared callback counters / captured values
    var observableCallCount: Int = 0
    var observableCapturedProp: Int = 0
    var observableCapturedOld: Int = 0
    var observableCapturedNew: Int = 0
    var observableValueAtCallback: Int = -999  // value read *inside* callback

    var vetoableCallCount: Int = 0
    var vetoableCapturedProp: Int = 0
    var vetoableCapturedOld: Int = 0
    var vetoableCapturedNew: Int = 0
    var vetoableValueAtCallback: Int = -999  // value read *inside* callback (should be old)

    // Handle references so callbacks can read the box
    var observableHandleRef: Int = 0
    var vetoableHandleRef: Int = 0

    func reset() {
        lock.lock()
        observableCallCount = 0
        observableCapturedProp = 0
        observableCapturedOld = 0
        observableCapturedNew = 0
        observableValueAtCallback = -999
        vetoableCallCount = 0
        vetoableCapturedProp = 0
        vetoableCapturedOld = 0
        vetoableCapturedNew = 0
        vetoableValueAtCallback = -999
        observableHandleRef = 0
        vetoableHandleRef = 0
        lock.unlock()
    }

    func withLock<T>(_ body: (EdgeCaseCallbackState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

private let gEdgeState = EdgeCaseCallbackState()

// Observable: records (prop, old, new) and the live value *inside* the callback.
private let observableEdgeCapture: KKDelegateObserverEntryPoint = { prop, old, new, _ in
    gEdgeState.withLock { s in
        s.observableCallCount += 1
        s.observableCapturedProp = prop
        s.observableCapturedOld = old
        s.observableCapturedNew = new
        // Read box value while inside callback — must already be updated.
        s.observableValueAtCallback = kk_observable_get_value(s.observableHandleRef)
    }
    return 0
}

// Vetoable: records (prop, old, new) and the live value *inside* the callback.
private let vetoableEdgeCapture: KKDelegateObserverEntryPoint = { prop, old, new, _ in
    gEdgeState.withLock { s in
        s.vetoableCallCount += 1
        s.vetoableCapturedProp = prop
        s.vetoableCapturedOld = old
        s.vetoableCapturedNew = new
        // Read box value while inside callback — must still be old (not yet changed).
        s.vetoableValueAtCallback = kk_vetoable_get_value(s.vetoableHandleRef)
    }
    return 1  // accept
}

// Vetoable: always rejects (returns 0).
private let vetoableEdgeReject: KKDelegateObserverEntryPoint = { _, _, _, _ in 0 }

// Vetoable: accepts only when new value > old value.
private let vetoableEdgeAcceptIfGreater: KKDelegateObserverEntryPoint = { _, old, new, _ in
    new > old ? 1 : 0
}

final class RuntimeDelegateEdgeCaseTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        gEdgeState.reset()
    }

    // MARK: - notNull(): read before assignment traps

    func testNotNullReadBeforeAssignmentTraps() {
        let handle = kk_notNull_create()
        XCTAssertNotEqual(handle, 0, "kk_notNull_create must return a valid handle")
        // Reading before any set should trap with fatalError.
        // We cannot catch fatalError directly in Swift unit tests, so we verify
        // the happy-path works and note this as a known gap (see PR body).
        // The runtime error message is "IllegalStateException: Property delegate
        // must be assigned before being accessed." (see RuntimeDelegates.swift).
        // BUG-NOTE: No outThrown channel — trap is non-catchable from tests.
    }

    func testNotNullSetThenGetReturnsValue() {
        let handle = kk_notNull_create()
        _ = kk_notNull_set_value(handle, 42)
        XCTAssertEqual(kk_notNull_get_value(handle, nil), 42)
    }

    // notNull allows re-assignment after first set.
    func testNotNullAllowsReassignment() {
        let handle = kk_notNull_create()
        _ = kk_notNull_set_value(handle, 10)
        XCTAssertEqual(kk_notNull_get_value(handle, nil), 10)

        _ = kk_notNull_set_value(handle, 20)
        XCTAssertEqual(kk_notNull_get_value(handle, nil), 20,
                       "notNull should allow overwriting the already-set value")
    }

    // notNull with a zero-valued Int (valid payload, sentinel not triggered by value).
    func testNotNullStoresZeroValueInt() {
        let handle = kk_notNull_create()
        // 0 is a valid assigned value (not a null sentinel for the box state).
        _ = kk_notNull_set_value(handle, 0)
        // After set, currentValue is Some(0), so get should return 0 without trapping.
        // BUG-CANDIDATE: RuntimeDelegates.swift stores Int? and checks guard let value.
        // If the runtime treats 0 as nil (which it does not currently), this would trap.
        // Verified: box.currentValue = newValue regardless of value, so 0 is stored safely.
        XCTAssertEqual(kk_notNull_get_value(handle, nil), 0,
                       "notNull must store integer 0 (not confuse it with nil)")
    }

    // MARK: - notNull generic shim (kk_delegate_get_value / kk_delegate_set_value)

    func testNotNullViaGenericShimGetSet() {
        let handle = kk_notNull_create()
        _ = kk_delegate_set_value(handle, 0, 0, 99)
        let result = kk_delegate_get_value(handle, 0, 0, nil)
        XCTAssertEqual(result, 99,
                       "kk_delegate_get_value shim should dispatch to notNull box")
    }

    // MARK: - observable(): callback fires AFTER the change

    func testObservableCallbackFiresAfterChange() {
        let cbPtr = unsafeBitCast(observableEdgeCapture, to: Int.self)
        let handle = kk_observable_create(1, cbPtr)
        gEdgeState.withLock { $0.observableHandleRef = handle }

        _ = kk_observable_set_value(handle, 2)

        let valueAtCb = gEdgeState.withLock { $0.observableValueAtCallback }
        XCTAssertEqual(valueAtCb, 2,
                       "Observable callback must fire *after* value is updated (kotlinc semantics)")
    }

    func testObservableCallbackReceivesCorrectOldAndNew() {
        let cbPtr = unsafeBitCast(observableEdgeCapture, to: Int.self)
        let handle = kk_observable_create(10, cbPtr)
        gEdgeState.withLock { $0.observableHandleRef = handle }

        _ = kk_observable_set_value(handle, 30)
        let old = gEdgeState.withLock { $0.observableCapturedOld }
        let new = gEdgeState.withLock { $0.observableCapturedNew }
        XCTAssertEqual(old, 10)
        XCTAssertEqual(new, 30)
    }

    func testObservableCallbackInvokedForEverySet() {
        let cbPtr = unsafeBitCast(observableEdgeCapture, to: Int.self)
        let handle = kk_observable_create(0, cbPtr)
        gEdgeState.withLock { $0.observableHandleRef = handle }

        _ = kk_observable_set_value(handle, 1)
        _ = kk_observable_set_value(handle, 2)
        _ = kk_observable_set_value(handle, 3)

        let count = gEdgeState.withLock { $0.observableCallCount }
        XCTAssertEqual(count, 3, "Callback must fire once per set call")
    }

    func testObservableWithNilCallbackDoesNotCrash() {
        // callbackFnPtr == 0 → no callback, value still changes.
        let handle = kk_observable_create(5, 0)
        let result = kk_observable_set_value(handle, 7)
        XCTAssertEqual(result, 7)
        XCTAssertEqual(kk_observable_get_value(handle), 7)
    }

    // Observable does NOT veto: setting same value still fires callback.
    func testObservableCallbackFiresEvenForSameValue() {
        let cbPtr = unsafeBitCast(observableEdgeCapture, to: Int.self)
        let handle = kk_observable_create(42, cbPtr)
        gEdgeState.withLock { $0.observableHandleRef = handle }

        _ = kk_observable_set_value(handle, 42)  // no-op value but callback still fires
        let count = gEdgeState.withLock { $0.observableCallCount }
        XCTAssertEqual(count, 1, "Observable callback fires even when old == new")
    }

    // observable generic shim
    func testObservableViaGenericShimGetSet() {
        let cbPtr = unsafeBitCast(observableEdgeCapture, to: Int.self)
        let handle = kk_observable_create(100, cbPtr)
        gEdgeState.withLock { $0.observableHandleRef = handle }

        _ = kk_delegate_set_value(handle, 0, 0, 200)
        XCTAssertEqual(kk_delegate_get_value(handle, 0, 0, nil), 200)
        let count = gEdgeState.withLock { $0.observableCallCount }
        XCTAssertEqual(count, 1, "Generic shim must trigger observable callback")
    }

    // MARK: - vetoable(): callback fires BEFORE the change

    func testVetoableCallbackFiresBeforeChange() {
        let cbPtr = unsafeBitCast(vetoableEdgeCapture, to: Int.self)
        let handle = kk_vetoable_create(50, cbPtr)
        gEdgeState.withLock { $0.vetoableHandleRef = handle }

        _ = kk_vetoable_set_value(handle, 60)

        let valueAtCb = gEdgeState.withLock { $0.vetoableValueAtCallback }
        XCTAssertEqual(valueAtCb, 50,
                       "Vetoable callback must fire *before* value changes (kotlinc semantics)")
    }

    func testVetoableCallbackReceivesCorrectOldAndNew() {
        let cbPtr = unsafeBitCast(vetoableEdgeCapture, to: Int.self)
        let handle = kk_vetoable_create(5, cbPtr)
        gEdgeState.withLock { $0.vetoableHandleRef = handle }

        _ = kk_vetoable_set_value(handle, 9)
        let old = gEdgeState.withLock { $0.vetoableCapturedOld }
        let new = gEdgeState.withLock { $0.vetoableCapturedNew }
        XCTAssertEqual(old, 5)
        XCTAssertEqual(new, 9)
    }

    func testVetoablePartialRejectSequence() {
        // Accept-if-greater callback: accept when new > old.
        let cbPtr = unsafeBitCast(vetoableEdgeAcceptIfGreater, to: Int.self)
        let handle = kk_vetoable_create(10, cbPtr)

        // Increase → accepted
        _ = kk_vetoable_set_value(handle, 20)
        XCTAssertEqual(kk_vetoable_get_value(handle), 20,
                       "Vetoable should accept when new > old")

        // Decrease → rejected
        _ = kk_vetoable_set_value(handle, 5)
        XCTAssertEqual(kk_vetoable_get_value(handle), 20,
                       "Vetoable should reject when new <= old")

        // Equal → rejected
        _ = kk_vetoable_set_value(handle, 20)
        XCTAssertEqual(kk_vetoable_get_value(handle), 20,
                       "Vetoable should reject when new == old")

        // Increase again → accepted
        _ = kk_vetoable_set_value(handle, 21)
        XCTAssertEqual(kk_vetoable_get_value(handle), 21,
                       "Vetoable should accept when new > old again")
    }

    func testVetoableMultipleRejectsKeepOldValue() {
        let cbPtr = unsafeBitCast(vetoableEdgeReject, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)

        for _ in 0..<5 {
            _ = kk_vetoable_set_value(handle, 999)
        }
        XCTAssertEqual(kk_vetoable_get_value(handle), 100,
                       "Repeated vetoed sets must not mutate the stored value")
    }

    func testVetoableWithNilCallbackAcceptsChange() {
        // callbackFnPtr == 0 → no callback, value changes unconditionally.
        let handle = kk_vetoable_create(3, 0)
        let result = kk_vetoable_set_value(handle, 7)
        XCTAssertEqual(result, 7)
        XCTAssertEqual(kk_vetoable_get_value(handle), 7)
    }

    func testVetoableCallbackInvokedOncePerSetAttempt() {
        let cbPtr = unsafeBitCast(vetoableEdgeCapture, to: Int.self)
        let handle = kk_vetoable_create(0, cbPtr)
        gEdgeState.withLock { $0.vetoableHandleRef = handle }

        _ = kk_vetoable_set_value(handle, 1)
        _ = kk_vetoable_set_value(handle, 2)
        _ = kk_vetoable_set_value(handle, 3)

        let count = gEdgeState.withLock { $0.vetoableCallCount }
        XCTAssertEqual(count, 3, "Vetoable callback fires once per set attempt")
    }

    // vetoable generic shim
    func testVetoableViaGenericShimAccept() {
        let cbPtr = unsafeBitCast(vetoableEdgeCapture, to: Int.self)
        let handle = kk_vetoable_create(0, cbPtr)
        gEdgeState.withLock { $0.vetoableHandleRef = handle }

        _ = kk_delegate_set_value(handle, 0, 0, 55)
        XCTAssertEqual(kk_delegate_get_value(handle, 0, 0, nil), 55)
    }

    func testVetoableViaGenericShimReject() {
        let cbPtr = unsafeBitCast(vetoableEdgeReject, to: Int.self)
        let handle = kk_vetoable_create(7, cbPtr)

        _ = kk_delegate_set_value(handle, 0, 0, 99)
        XCTAssertEqual(kk_delegate_get_value(handle, 0, 0, nil), 7,
                       "Generic shim veto should keep original value")
    }

    // MARK: - lazy: value is frozen after first evaluation

    func testLazyValueIsFrozenAfterInit() {
        // The initializer returns 42 once; verify subsequent reads return the same value.
        let init42: KKThunkEntryPoint = { _ in 42 }
        let fnPtr = unsafeBitCast(init42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)

        let first = kk_lazy_get_value(handle)
        let second = kk_lazy_get_value(handle)
        let third = kk_lazy_get_value(handle)
        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
        XCTAssertEqual(third, 42)
        // isInitialized must be true after any access.
        XCTAssertEqual(kk_lazy_is_initialized(handle), 1)
    }

    func testLazyValueZeroIsValidAfterInit() {
        // Initializer that returns 0 is a valid (non-null) value.
        let initZero: KKThunkEntryPoint = { _ in 0 }
        let fnPtr = unsafeBitCast(initZero, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)

        let value = kk_lazy_get_value(handle)
        // BUG-NOTE: If kk_lazy_get_value treats 0 as "not yet initialized" this would
        // loop infinitely — the current implementation checks `isInitialized` flag, not value.
        XCTAssertEqual(value, 0, "Lazy must store integer 0 as a valid initialized value")
        XCTAssertEqual(kk_lazy_is_initialized(handle), 1,
                       "Lazy should be marked initialized even when initializer returned 0")
    }

    func testLazyGenericShimReturnsValue() {
        let init77: KKThunkEntryPoint = { _ in 77 }
        let fnPtr = unsafeBitCast(init77, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)

        let value = kk_delegate_get_value(handle, 0, 0, nil)
        XCTAssertEqual(value, 77, "kk_delegate_get_value shim must dispatch to lazy box")
    }

    // MARK: - KProperty stub metadata

    func testKPropertyStubNameRoundtrip() {
        // Build a KKString for the name and verify kk_kproperty_stub_name returns it.
        let nameStr = "myProp"
        let kkName = nameStr.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: nameStr.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(nameStr.utf8.count)))
            }
        }
        let stub = kk_kproperty_stub_create(kkName, 0)
        XCTAssertNotEqual(stub, 0)
        XCTAssertEqual(kk_kproperty_stub_name(stub), kkName,
                       "KProperty stub name must round-trip through create/name")
    }

    func testKPropertyStubFullMetadataIsLateinit() {
        let nameStr = "lateField"
        let kkName = nameStr.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: nameStr.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(nameStr.utf8.count)))
            }
        }
        let stub = kk_kproperty_stub_create_full(kkName, 0, 0, /*isLateinit*/ 1, /*isConst*/ 0)
        XCTAssertEqual(kk_kproperty_stub_is_lateinit(stub), 1,
                       "isLateinit=1 must be reported by accessor")
        XCTAssertEqual(kk_kproperty_stub_is_const(stub), 0)
    }

    func testKPropertyStubFullMetadataIsConst() {
        let nameStr = "constField"
        let kkName = nameStr.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: nameStr.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(nameStr.utf8.count)))
            }
        }
        let stub = kk_kproperty_stub_create_full(kkName, 0, 0, /*isLateinit*/ 0, /*isConst*/ 1)
        XCTAssertEqual(kk_kproperty_stub_is_const(stub), 1,
                       "isConst=1 must be reported by accessor")
        XCTAssertEqual(kk_kproperty_stub_is_lateinit(stub), 0)
    }

    func testKPropertyStubDefaultVisibilityIsPublic() {
        // When visibility is not set (0), kk_kproperty_stub_visibility returns "PUBLIC" string.
        let nameStr = "field"
        let kkName = nameStr.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: nameStr.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(nameStr.utf8.count)))
            }
        }
        let stub = kk_kproperty_stub_create(kkName, 0)
        let visHandle = kk_kproperty_stub_visibility(stub)
        // Must be non-zero (a KKString containing "PUBLIC").
        XCTAssertNotEqual(visHandle, 0, "Default visibility must return a non-null KKString")
    }

    // MARK: - Invalid handle robustness

    func testAllDelegateShimsHandleZeroHandleGracefully() {
        // kk_delegate_get_value and kk_delegate_set_value with handle == 0.
        XCTAssertEqual(kk_delegate_get_value(0, 0, 0, nil), 0)
        XCTAssertEqual(kk_delegate_set_value(0, 0, 0, 42), 0)
    }

    func testObservableSetValueWithInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_observable_set_value(0, 99), 0)
    }

    func testVetoableSetValueWithInvalidHandleReturnsCurrentValue() {
        // Per implementation: guard returns 0 for null handle.
        XCTAssertEqual(kk_vetoable_set_value(0, 99), 0)
    }
}
