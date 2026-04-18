import Dispatch
import Foundation
@testable import Runtime
import XCTest

// MARK: - kotlin.native.concurrent minimal runtime ABI coverage (STDLIB-NATIVE-CONCURRENT-003)
//
// This file adds coverage for runtime ABI gaps not addressed by
// RuntimeNativeConcurrentTests.swift (which covers Workers, freeze/isFrozen,
// and basic AtomicInt/Long/Reference CAS).
//
// Implemented APIs tested here:
//   AtomicBoolean  : kk_atomic_bool_create / load / store / exchange /
//                    compareAndSet / compareAndExchange / getAndUpdate / updateAndGet
//   AtomicIntArray : kk_atomic_int_array_create / size / loadAt / storeAt /
//                    exchangeAt / compareAndSetAt / compareAndExchangeAt /
//                    fetchAndAddAt / addAndFetchAt / incrementAndFetchAt /
//                    decrementAndFetchAt
//   AtomicLongArray: kk_atomic_long_array_* (same shape as AtomicIntArray)
//   AtomicInt      : getAndUpdate / updateAndGet (higher-order variants)
//   AtomicLong     : getAndUpdate / updateAndGet (higher-order variants)
//   AtomicReference: getAndUpdate / updateAndGet (higher-order variants)
//   CPointer       : kk_cpointer_new / kk_cpointer_address
//   COpaquePointer : kk_copaque_pointer_new / kk_copaque_pointer_address
//   Pinned<T>      : kk_pin_object / kk_unpin_object / kk_pinned_get
//   @CName         : kk_cname_register / kk_cname_lookup
//
// Missing / not yet implemented (runtime gaps documented):
//   - Worker.id (stable integer identifier per Worker instance)
//   - Future<T>   (kk_future_new / kk_future_result / kk_future_consume)
//   - TransferMode enum enforcement on Worker.execute
//   - FreezableAtomicReference<T>
//   - Worker.executeAfter (delayed scheduling)
//   - @SharedImmutable top-level val freeze-on-init enforcement

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean
// ---------------------------------------------------------------------------

final class RuntimeAtomicBooleanTests: XCTestCase {

    func testCreateAndLoad() {
        let trueHandle = kk_atomic_bool_create(1)
        XCTAssertNotEqual(trueHandle, 0)
        XCTAssertEqual(kk_atomic_bool_load(trueHandle), 1)

        let falseHandle = kk_atomic_bool_create(0)
        XCTAssertNotEqual(falseHandle, 0)
        XCTAssertEqual(kk_atomic_bool_load(falseHandle), 0)
    }

    func testStore() {
        let handle = kk_atomic_bool_create(0)
        _ = kk_atomic_bool_store(handle, 1)
        XCTAssertEqual(kk_atomic_bool_load(handle), 1)
        _ = kk_atomic_bool_store(handle, 0)
        XCTAssertEqual(kk_atomic_bool_load(handle), 0)
    }

    func testExchange() {
        let handle = kk_atomic_bool_create(1)
        let old = kk_atomic_bool_exchange(handle, 0)
        XCTAssertEqual(old, 1, "exchange must return old value")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "exchange must store new value")
    }

    func testCompareAndSetSuccess() {
        let handle = kk_atomic_bool_create(0)
        let result = kk_atomic_bool_compareAndSet(handle, 0, 1)
        XCTAssertEqual(result, 1, "CAS must succeed (return 1) when expect matches")
        XCTAssertEqual(kk_atomic_bool_load(handle), 1)
    }

    func testCompareAndSetFailure() {
        let handle = kk_atomic_bool_create(0)
        let result = kk_atomic_bool_compareAndSet(handle, 1, 1)
        XCTAssertEqual(result, 0, "CAS must fail (return 0) when expect does not match")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "Value must not change on failed CAS")
    }

    func testCompareAndExchangeSuccess() {
        let handle = kk_atomic_bool_create(1)
        let old = kk_atomic_bool_compareAndExchange(handle, 1, 0)
        XCTAssertEqual(old, 1, "compareAndExchange must return old value on success")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0)
    }

    func testCompareAndExchangeFailure() {
        let handle = kk_atomic_bool_create(0)
        let old = kk_atomic_bool_compareAndExchange(handle, 1, 1)
        XCTAssertEqual(old, 0, "compareAndExchange must return current value on failure")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "Value must not change on failure")
    }

    func testInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_atomic_bool_load(0), 0)
        XCTAssertEqual(kk_atomic_bool_store(0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_exchange(0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_compareAndSet(0, 0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_compareAndExchange(0, 0, 1), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt higher-order variants (getAndUpdate / updateAndGet)
// ---------------------------------------------------------------------------

/// A C-callable doubling function for use in getAndUpdate / updateAndGet tests.
private let doubleIntThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { value, _ in
    value * 2
}
private let doubleIntThunkPtr = unsafeBitCast(doubleIntThunk, to: Int.self)

private let negateIntThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { value, _ in
    -value
}
private let negateIntThunkPtr = unsafeBitCast(negateIntThunk, to: Int.self)

final class RuntimeAtomicIntHigherOrderTests: XCTestCase {

    func testGetAndUpdateReturnsOldValue() {
        let handle = kk_atomic_int_create(3)
        let old = kk_atomic_int_getAndUpdate(handle, doubleIntThunkPtr, nil)
        XCTAssertEqual(old, 3, "getAndUpdate must return the old value")
        XCTAssertEqual(kk_atomic_int_load(handle), 6, "getAndUpdate must store the transformed value")
    }

    func testUpdateAndGetReturnsNewValue() {
        let handle = kk_atomic_int_create(5)
        let new = kk_atomic_int_updateAndGet(handle, doubleIntThunkPtr, nil)
        XCTAssertEqual(new, 10, "updateAndGet must return the new (transformed) value")
        XCTAssertEqual(kk_atomic_int_load(handle), 10)
    }

    func testGetAndUpdateWithNegation() {
        let handle = kk_atomic_int_create(7)
        let old = kk_atomic_int_getAndUpdate(handle, negateIntThunkPtr, nil)
        XCTAssertEqual(old, 7)
        XCTAssertEqual(kk_atomic_int_load(handle), -7)
    }

    func testUpdateAndGetWithNegation() {
        let handle = kk_atomic_int_create(-4)
        let new = kk_atomic_int_updateAndGet(handle, negateIntThunkPtr, nil)
        XCTAssertEqual(new, 4)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLong higher-order variants
// ---------------------------------------------------------------------------

final class RuntimeAtomicLongHigherOrderTests: XCTestCase {

    func testGetAndUpdateReturnsOldValue() {
        let handle = kk_atomic_long_create(10)
        let old = kk_atomic_long_getAndUpdate(handle, doubleIntThunkPtr, nil)
        XCTAssertEqual(old, 10)
        XCTAssertEqual(kk_atomic_long_load(handle), 20)
    }

    func testUpdateAndGetReturnsNewValue() {
        let handle = kk_atomic_long_create(8)
        let new = kk_atomic_long_updateAndGet(handle, doubleIntThunkPtr, nil)
        XCTAssertEqual(new, 16)
        XCTAssertEqual(kk_atomic_long_load(handle), 16)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicReference higher-order variants
// ---------------------------------------------------------------------------

// C-callable thunks that return fixed sentinel values used as stand-in references.
// These must be non-capturing so they can be formed as @convention(c) pointers.
private let refHighOrderThunkReturn42: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 42 }
private let refHighOrderThunkReturn99: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 99 }
private let refHighOrderThunkReturn42Ptr = unsafeBitCast(refHighOrderThunkReturn42, to: Int.self)
private let refHighOrderThunkReturn99Ptr = unsafeBitCast(refHighOrderThunkReturn99, to: Int.self)

final class RuntimeAtomicReferenceHigherOrderTests: XCTestCase {

    func testGetAndUpdateReturnsOldReference() {
        // Store an initial value of 10 (arbitrary sentinel) and use the
        // thunk to transform it to 42.  getAndUpdate returns the old value.
        let atomicRef = kk_atomic_ref_create(10)
        let old = kk_atomic_ref_getAndUpdate(atomicRef, refHighOrderThunkReturn42Ptr, nil)
        XCTAssertEqual(old, 10, "getAndUpdate must return the old reference")
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), 42)
    }

    func testUpdateAndGetReturnsNewReference() {
        let atomicRef = kk_atomic_ref_create(10)
        let new = kk_atomic_ref_updateAndGet(atomicRef, refHighOrderThunkReturn99Ptr, nil)
        XCTAssertEqual(new, 99, "updateAndGet must return the new reference")
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), 99)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicIntArray
// ---------------------------------------------------------------------------

final class RuntimeAtomicIntArrayTests: XCTestCase {

    func testCreateAndSize() {
        let handle = kk_atomic_int_array_create(5)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_atomic_int_array_size(handle), 5)
    }

    func testInitialValuesAreZero() {
        let handle = kk_atomic_int_array_create(3)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 0, nil), 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 1, nil), 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 2, nil), 0)
    }

    func testStoreAndLoad() {
        let handle = kk_atomic_int_array_create(4)
        _ = kk_atomic_int_array_storeAt(handle, 2, 42, nil)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 2, nil), 42)
    }

    func testExchangeAt() {
        let handle = kk_atomic_int_array_create(2)
        _ = kk_atomic_int_array_storeAt(handle, 0, 10, nil)
        let old = kk_atomic_int_array_exchangeAt(handle, 0, 99, nil)
        XCTAssertEqual(old, 10, "exchangeAt must return the old value")
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 0, nil), 99)
    }

    func testCompareAndSetAtSuccess() {
        let handle = kk_atomic_int_array_create(2)
        _ = kk_atomic_int_array_storeAt(handle, 1, 7, nil)
        let result = kk_atomic_int_array_compareAndSetAt(handle, 1, 7, 77, nil)
        XCTAssertEqual(result, 1, "CAS must succeed when expected value matches")
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 1, nil), 77)
    }

    func testCompareAndSetAtFailure() {
        let handle = kk_atomic_int_array_create(2)
        _ = kk_atomic_int_array_storeAt(handle, 0, 5, nil)
        let result = kk_atomic_int_array_compareAndSetAt(handle, 0, 999, 50, nil)
        XCTAssertEqual(result, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 0, nil), 5, "Value must not change on failed CAS")
    }

    func testCompareAndExchangeAt() {
        let handle = kk_atomic_int_array_create(3)
        _ = kk_atomic_int_array_storeAt(handle, 2, 20, nil)
        let old = kk_atomic_int_array_compareAndExchangeAt(handle, 2, 20, 200, nil)
        XCTAssertEqual(old, 20)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 2, nil), 200)
    }

    func testFetchAndAddAt() {
        let handle = kk_atomic_int_array_create(1)
        _ = kk_atomic_int_array_storeAt(handle, 0, 100, nil)
        let old = kk_atomic_int_array_fetchAndAddAt(handle, 0, 5, nil)
        XCTAssertEqual(old, 100)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 0, nil), 105)
    }

    func testAddAndFetchAt() {
        let handle = kk_atomic_int_array_create(1)
        _ = kk_atomic_int_array_storeAt(handle, 0, 50, nil)
        let new = kk_atomic_int_array_addAndFetchAt(handle, 0, 10, nil)
        XCTAssertEqual(new, 60)
    }

    func testIncrementAndDecrementAt() {
        let handle = kk_atomic_int_array_create(1)
        _ = kk_atomic_int_array_storeAt(handle, 0, 0, nil)
        let afterInc = kk_atomic_int_array_incrementAndFetchAt(handle, 0, nil)
        XCTAssertEqual(afterInc, 1)
        let afterDec = kk_atomic_int_array_decrementAndFetchAt(handle, 0, nil)
        XCTAssertEqual(afterDec, 0)
    }

    func testOutOfBoundsIndexReturnsZero() {
        let handle = kk_atomic_int_array_create(2)
        XCTAssertEqual(kk_atomic_int_array_loadAt(handle, 99, nil), 0)
        XCTAssertEqual(kk_atomic_int_array_compareAndSetAt(handle, 99, 0, 1, nil), 0)
        XCTAssertEqual(kk_atomic_int_array_fetchAndAddAt(handle, 99, 1, nil), 0)
    }

    func testZeroSizeArrayHasZeroSize() {
        let handle = kk_atomic_int_array_create(0)
        XCTAssertEqual(kk_atomic_int_array_size(handle), 0)
    }

    func testInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_atomic_int_array_size(0), 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(0, 0, nil), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLongArray
// ---------------------------------------------------------------------------

final class RuntimeAtomicLongArrayTests: XCTestCase {

    func testCreateAndSize() {
        let handle = kk_atomic_long_array_create(4)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_atomic_long_array_size(handle), 4)
    }

    func testStoreAndLoad() {
        let handle = kk_atomic_long_array_create(2)
        _ = kk_atomic_long_array_storeAt(handle, 0, 1000, nil)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 1000)
    }

    func testExchangeAt() {
        let handle = kk_atomic_long_array_create(1)
        _ = kk_atomic_long_array_storeAt(handle, 0, 42, nil)
        let old = kk_atomic_long_array_exchangeAt(handle, 0, 84, nil)
        XCTAssertEqual(old, 42)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 84)
    }

    func testCompareAndSetAtSuccess() {
        let handle = kk_atomic_long_array_create(1)
        _ = kk_atomic_long_array_storeAt(handle, 0, 99, nil)
        XCTAssertEqual(kk_atomic_long_array_compareAndSetAt(handle, 0, 99, 199, nil), 1)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 199)
    }

    func testCompareAndSetAtFailure() {
        let handle = kk_atomic_long_array_create(1)
        _ = kk_atomic_long_array_storeAt(handle, 0, 10, nil)
        XCTAssertEqual(kk_atomic_long_array_compareAndSetAt(handle, 0, 999, 20, nil), 0)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 10)
    }

    func testFetchAndAddAt() {
        let handle = kk_atomic_long_array_create(1)
        _ = kk_atomic_long_array_storeAt(handle, 0, 500, nil)
        let old = kk_atomic_long_array_fetchAndAddAt(handle, 0, 100, nil)
        XCTAssertEqual(old, 500)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 600)
    }

    func testIncrementAndDecrementAt() {
        let handle = kk_atomic_long_array_create(1)
        _ = kk_atomic_long_array_storeAt(handle, 0, 0, nil)
        _ = kk_atomic_long_array_incrementAndFetchAt(handle, 0, nil)
        _ = kk_atomic_long_array_incrementAndFetchAt(handle, 0, nil)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 2)
        _ = kk_atomic_long_array_decrementAndFetchAt(handle, 0, nil)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 0, nil), 1)
    }

    func testOutOfBoundsIndexReturnsZero() {
        let handle = kk_atomic_long_array_create(2)
        XCTAssertEqual(kk_atomic_long_array_loadAt(handle, 50, nil), 0)
        XCTAssertEqual(kk_atomic_long_array_compareAndSetAt(handle, 50, 0, 1, nil), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - CPointer / COpaquePointer
// ---------------------------------------------------------------------------

final class RuntimeCPointerTests: XCTestCase {

    func testCPointerRoundTrip() {
        let address = 0xDEAD_BEEF
        let handle = kk_cpointer_new(address)
        XCTAssertNotEqual(handle, 0)
        let recovered = kk_cpointer_address(handle)
        XCTAssertEqual(recovered, address)
    }

    func testCPointerZeroAddress() {
        let handle = kk_cpointer_new(0)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_cpointer_address(handle), 0)
    }

    func testCPointerInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_cpointer_address(0), 0)
    }

    func testCOpaquePointerRoundTrip() {
        let address = 0x1234_5678
        let handle = kk_copaque_pointer_new(address)
        XCTAssertNotEqual(handle, 0)
        let recovered = kk_copaque_pointer_address(handle)
        XCTAssertEqual(recovered, address)
    }

    func testCOpaquePointerInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_copaque_pointer_address(0), 0)
    }

    func testCPointerAndCOpaquePointerAreDistinct() {
        let address = 0xABCD
        let cptrHandle = kk_cpointer_new(address)
        let copaqueHandle = kk_copaque_pointer_new(address)
        // Each allocation produces a distinct handle.
        XCTAssertNotEqual(cptrHandle, copaqueHandle)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pinned<T>
// ---------------------------------------------------------------------------

final class RuntimePinnedTests: XCTestCase {

    func testPinObjectReturnsNonZeroHandle() {
        let obj = kk_atomic_int_create(1)
        let pinHandle = kk_pin_object(obj)
        XCTAssertNotEqual(pinHandle, 0)
    }

    func testPinnedGetReturnsOriginalObject() {
        let obj = kk_atomic_int_create(2)
        let pinHandle = kk_pin_object(obj)
        XCTAssertEqual(kk_pinned_get(pinHandle), obj)
    }

    func testUnpinReturnsOriginalObject() {
        let obj = kk_atomic_int_create(3)
        let pinHandle = kk_pin_object(obj)
        let recovered = kk_unpin_object(pinHandle)
        XCTAssertEqual(recovered, obj)
    }

    func testPinZeroHandleReturnsZero() {
        XCTAssertEqual(kk_pin_object(0), 0)
    }

    func testPinnedGetOnZeroHandleReturnsZero() {
        XCTAssertEqual(kk_pinned_get(0), 0)
    }

    func testUnpinZeroHandleReturnsZero() {
        XCTAssertEqual(kk_unpin_object(0), 0)
    }

    func testPinDoesNotAlterOriginalAtomicValue() {
        let handle = kk_atomic_int_create(42)
        let pinHandle = kk_pin_object(handle)
        // The AtomicInt backing value must be unaffected by pinning.
        XCTAssertEqual(kk_atomic_int_load(handle), 42)
        _ = kk_unpin_object(pinHandle)
        XCTAssertEqual(kk_atomic_int_load(handle), 42)
    }
}

// ---------------------------------------------------------------------------
// MARK: - @CName registry
// ---------------------------------------------------------------------------

final class RuntimeCNameRegistryTests: IsolatedRuntimeXCTestCase {

    func testRegisterAndLookupRoundTrip() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let fakePtr = 0x1_0000
        _ = kk_cname_register(nameHandle, fakePtr)

        let lookupNameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let found = kk_cname_lookup(lookupNameHandle)
        XCTAssertEqual(found, fakePtr)
    }

    func testLookupMissingNameReturnsZero() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("doesNotExist"))
        XCTAssertEqual(kk_cname_lookup(nameHandle), 0)
    }

    func testRegisterOverwritesExistingEntry() {
        let nameHandle1 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle1, 0xAAAA)

        let nameHandle2 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle2, 0xBBBB)

        let lookupHandle = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        XCTAssertEqual(kk_cname_lookup(lookupHandle), 0xBBBB)
    }

    func testRegisterWithInvalidNameHandleIsNoOp() {
        // Passing 0 as name handle must not crash and must not register anything.
        _ = kk_cname_register(0, 0x1234)
        XCTAssertEqual(kk_cname_lookup(0), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt thread-safety smoke test
// ---------------------------------------------------------------------------

final class RuntimeAtomicIntConcurrencyTests: XCTestCase {

    func testConcurrentIncrementWithFetchAndAdd() {
        let handle = kk_atomic_int_create(0)
        let iterations = 1000
        let queueCount = 4
        let group = DispatchGroup()

        for _ in 0..<queueCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<iterations {
                    _ = kk_atomic_int_fetchAndAdd(handle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success, "Concurrent increment timed out")
        XCTAssertEqual(kk_atomic_int_load(handle), queueCount * iterations,
                       "Each increment must be atomic — no lost updates")
    }

    func testConcurrentCompareAndSetExactlyOneSucceeds() {
        // Many threads race to CAS from 0 -> 1; exactly one should win.
        // Use a separate AtomicInt runtime handle as win counter so we
        // avoid Sendable issues with AtomicIntBox directly.
        let handle = kk_atomic_int_create(0)
        let winCountHandle = kk_atomic_int_create(0)

        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = kk_atomic_int_compareAndSet(handle, 0, 1)
                if result == 1 {
                    _ = kk_atomic_int_fetchAndAdd(winCountHandle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success)
        XCTAssertEqual(kk_atomic_int_load(winCountHandle), 1,
                       "Exactly one CAS must win when racing from 0 -> 1")
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean concurrency smoke test
// ---------------------------------------------------------------------------

final class RuntimeAtomicBoolConcurrencyTests: XCTestCase {

    func testConcurrentStoreAndLoadNeverCrashes() {
        let handle = kk_atomic_bool_create(0)
        let group = DispatchGroup()
        for i in 0..<4 {
            let val = i % 2
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<500 {
                    _ = kk_atomic_bool_store(handle, val)
                    _ = kk_atomic_bool_load(handle)
                }
                group.leave()
            }
        }
        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success, "Concurrent bool store/load timed out or crashed")
    }
}
