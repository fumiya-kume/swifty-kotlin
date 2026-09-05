import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - kotlin.native.concurrent extended runtime ABI coverage (STDLIB-NATIVE-CONCURRENT-003)
//
// This file adds extended runtime coverage not addressed by
// RuntimeNativeConcurrentTests.swift, which covers Worker lifecycle,
// freeze/isFrozen, Worker.id, Future<T>, TransferMode, FreezableAtomicReference,
// @SharedImmutable, Worker.executeAfter, and basic AtomicInt/Long/Reference CAS.
//
// Implemented APIs tested here:
//   AtomicBoolean  : kk_atomic_bool_create / load / store / exchange /
//                    compareAndExchange
//   AtomicIntArray : kk_atomic_int_array_create / size / loadAt / storeAt /
//                    exchangeAt / compareAndSetAt / compareAndExchangeAt /
//                    fetchAndAddAt / addAndFetchAt / fetchAndIncrementAt /
//                    incrementAndFetchAt / fetchAndDecrementAt /
//                    decrementAndFetchAt
//   AtomicLongArray: kk_atomic_long_array_* (same shape as AtomicIntArray)
//   CPointer       : kk_cpointer_new / kk_cpointer_address
//   COpaquePointer : kk_copaque_pointer_new / kk_copaque_pointer_address
//   Pinned<T>      : kk_pin_object / kk_unpin_object / kk_pinned_get
//   @CName         : kk_cname_register / kk_cname_lookup
//
// Minimal native concurrent runtime ABI is implemented by RuntimeNativeAPI.swift,
// RuntimeNativeConcurrentABI.swift, RuntimeAtomic.swift, and RuntimeThreadLocal.swift.

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean
// ---------------------------------------------------------------------------

@Suite
struct RuntimeAtomicBooleanTests {

    @Test func createAndLoad() {
        let trueHandle = kk_atomic_bool_create(1)
        #expect(trueHandle != 0)
        #expect(__kk_atomic_bool_load(trueHandle) == 1)

        let falseHandle = kk_atomic_bool_create(0)
        #expect(falseHandle != 0)
        #expect(__kk_atomic_bool_load(falseHandle) == 0)
    }

    @Test func store() {
        let handle = kk_atomic_bool_create(0)
        _ = __kk_atomic_bool_store(handle, 1)
        #expect(__kk_atomic_bool_load(handle) == 1)
        _ = __kk_atomic_bool_store(handle, 0)
        #expect(__kk_atomic_bool_load(handle) == 0)
    }

    @Test func exchange() {
        let handle = kk_atomic_bool_create(1)
        let old = __kk_atomic_bool_exchange(handle, 0)
        #expect(old == 1, "exchange must return old value")
        #expect(__kk_atomic_bool_load(handle) == 0, "exchange must store new value")
    }

    @Test func compareAndExchangeSuccess() {
        let handle = kk_atomic_bool_create(1)
        let old = __kk_atomic_bool_compareAndExchange(handle, 1, 0)
        #expect(old == 1, "compareAndExchange must return old value on success")
        #expect(__kk_atomic_bool_load(handle) == 0)
    }

    @Test func compareAndExchangeFailure() {
        let handle = kk_atomic_bool_create(0)
        let old = __kk_atomic_bool_compareAndExchange(handle, 1, 1)
        #expect(old == 0, "compareAndExchange must return current value on failure")
        #expect(__kk_atomic_bool_load(handle) == 0, "Value must not change on failure")
    }

    @Test func invalidHandleReturnsZero() {
        #expect(__kk_atomic_bool_load(0) == 0)
        #expect(__kk_atomic_bool_store(0, 1) == 0)
        #expect(__kk_atomic_bool_exchange(0, 1) == 0)
        #expect(__kk_atomic_bool_compareAndExchange(0, 0, 1) == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicIntArray
// ---------------------------------------------------------------------------

@Suite
struct RuntimeAtomicIntArrayTests {

    @Test func createAndSize() {
        let handle = kk_atomic_int_array_create(5)
        #expect(handle != 0)
        #expect(kk_atomic_int_array_size(handle) == 5)
    }

    // KSP-672: the public `*At` boundary layer and bounds checks now live in
    // Kotlin (Stdlib/kotlin/concurrent/AtomicArrayMigration.kt). These runtime
    // tests exercise only the raw synchronized-core `__kk_*` bridges, which
    // assume a pre-validated in-range index.

    @Test func initialValuesAreZero() {
        let handle = kk_atomic_int_array_create(3)
        #expect(__kk_atomic_int_array_load(handle, 0) == 0)
        #expect(__kk_atomic_int_array_load(handle, 1) == 0)
        #expect(__kk_atomic_int_array_load(handle, 2) == 0)
    }

    @Test func storeAndLoad() {
        let handle = kk_atomic_int_array_create(4)
        _ = __kk_atomic_int_array_store(handle, 2, 42)
        #expect(__kk_atomic_int_array_load(handle, 2) == 42)
    }

    @Test func exchange() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 0, 10)
        let old = __kk_atomic_int_array_exchange(handle, 0, 99)
        #expect(old == 10, "exchange must return the old value")
        #expect(__kk_atomic_int_array_load(handle, 0) == 99)
    }

    @Test func compareAndExchangeSuccess() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 1, 7)
        let old = __kk_atomic_int_array_compareAndExchange(handle, 1, 7, 77)
        #expect(old == 7, "compareAndExchange returns the observed value")
        #expect(__kk_atomic_int_array_load(handle, 1) == 77)
    }

    @Test func compareAndExchangeFailure() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 0, 5)
        let old = __kk_atomic_int_array_compareAndExchange(handle, 0, 999, 50)
        #expect(old == 5, "compareAndExchange returns the current value on mismatch")
        #expect(__kk_atomic_int_array_load(handle, 0) == 5, "Value must not change on failed CAS")
    }

    @Test func fetchAndAdd() {
        let handle = kk_atomic_int_array_create(1)
        _ = __kk_atomic_int_array_store(handle, 0, 100)
        let old = __kk_atomic_int_array_fetchAndAdd(handle, 0, 5)
        #expect(old == 100)
        #expect(__kk_atomic_int_array_load(handle, 0) == 105)
    }

    @Test func addAndFetch() {
        let handle = kk_atomic_int_array_create(1)
        _ = __kk_atomic_int_array_store(handle, 0, 50)
        let new = __kk_atomic_int_array_addAndFetch(handle, 0, 10)
        #expect(new == 60)
    }

    @Test func zeroSizeArrayHasZeroSize() {
        let handle = kk_atomic_int_array_create(0)
        #expect(kk_atomic_int_array_size(handle) == 0)
    }

    @Test func invalidHandleReturnsZero() {
        #expect(kk_atomic_int_array_size(0) == 0)
        #expect(__kk_atomic_int_array_load(0, 0) == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLongArray
// ---------------------------------------------------------------------------

@Suite
struct RuntimeAtomicLongArrayTests {

    @Test func createAndSize() {
        let handle = kk_atomic_long_array_create(4)
        #expect(handle != 0)
        #expect(kk_atomic_long_array_size(handle) == 4)
    }

    // KSP-672: bounds checks and the public `*At` layer live in Kotlin; these
    // tests cover only the raw synchronized-core `__kk_*` bridges.

    @Test func storeAndLoad() {
        let handle = kk_atomic_long_array_create(2)
        _ = __kk_atomic_long_array_store(handle, 0, 1000)
        #expect(__kk_atomic_long_array_load(handle, 0) == 1000)
    }

    @Test func exchange() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 42)
        let old = __kk_atomic_long_array_exchange(handle, 0, 84)
        #expect(old == 42)
        #expect(__kk_atomic_long_array_load(handle, 0) == 84)
    }

    @Test func compareAndExchangeSuccess() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 99)
        #expect(__kk_atomic_long_array_compareAndExchange(handle, 0, 99, 199) == 99)
        #expect(__kk_atomic_long_array_load(handle, 0) == 199)
    }

    @Test func compareAndExchangeFailure() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 10)
        #expect(__kk_atomic_long_array_compareAndExchange(handle, 0, 999, 20) == 10)
        #expect(__kk_atomic_long_array_load(handle, 0) == 10)
    }

    @Test func fetchAndAdd() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 500)
        let old = __kk_atomic_long_array_fetchAndAdd(handle, 0, 100)
        #expect(old == 500)
        #expect(__kk_atomic_long_array_load(handle, 0) == 600)
    }

    @Test func addAndFetch() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 50)
        let new = __kk_atomic_long_array_addAndFetch(handle, 0, 10)
        #expect(new == 60)
    }
}

// ---------------------------------------------------------------------------
// MARK: - CPointer / COpaquePointer
// ---------------------------------------------------------------------------

@Suite
struct RuntimeCPointerTests {

    @Test func cPointerRoundTrip() {
        let address = 0xDEAD_BEEF
        let handle = kk_cpointer_new(address)
        #expect(handle != 0)
        let recovered = kk_cpointer_address(handle)
        #expect(recovered == address)
    }

    @Test func cPointerZeroAddress() {
        let handle = kk_cpointer_new(0)
        #expect(handle != 0)
        #expect(kk_cpointer_address(handle) == 0)
    }

    @Test func cPointerInvalidHandleReturnsZero() {
        #expect(kk_cpointer_address(0) == 0)
    }

    @Test func cOpaquePointerRoundTrip() {
        let address = 0x1234_5678
        let handle = kk_copaque_pointer_new(address)
        #expect(handle != 0)
        let recovered = kk_copaque_pointer_address(handle)
        #expect(recovered == address)
    }

    @Test func cOpaquePointerInvalidHandleReturnsZero() {
        #expect(kk_copaque_pointer_address(0) == 0)
    }

    @Test func cPointerAndCOpaquePointerAreDistinct() {
        let address = 0xABCD
        let cptrHandle = kk_cpointer_new(address)
        let copaqueHandle = kk_copaque_pointer_new(address)
        // Each allocation produces a distinct handle.
        #expect(cptrHandle != copaqueHandle)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pinned<T>
// ---------------------------------------------------------------------------

@Suite
struct RuntimePinnedTests {

    @Test func pinObjectReturnsNonZeroHandle() {
        let obj = kk_atomic_int_create(1)
        let pinHandle = kk_pin_object(obj)
        #expect(pinHandle != 0)
    }

    @Test func pinnedGetReturnsOriginalObject() {
        let obj = kk_atomic_int_create(2)
        let pinHandle = kk_pin_object(obj)
        #expect(kk_pinned_get(pinHandle) == obj)
    }

    @Test func unpinReturnsOriginalObject() {
        let obj = kk_atomic_int_create(3)
        let pinHandle = kk_pin_object(obj)
        let recovered = kk_unpin_object(pinHandle)
        #expect(recovered == obj)
    }

    @Test func pinZeroHandleReturnsZero() {
        #expect(kk_pin_object(0) == 0)
    }

    @Test func pinnedGetOnZeroHandleReturnsZero() {
        #expect(kk_pinned_get(0) == 0)
    }

    @Test func unpinZeroHandleReturnsZero() {
        #expect(kk_unpin_object(0) == 0)
    }

    @Test func pinDoesNotAlterOriginalAtomicValue() {
        let handle = kk_atomic_int_create(42)
        let pinHandle = kk_pin_object(handle)
        // The AtomicInt backing value must be unaffected by pinning.
        #expect(__kk_atomic_int_load(handle) == 42)
        _ = kk_unpin_object(pinHandle)
        #expect(__kk_atomic_int_load(handle) == 42)
    }
}

// ---------------------------------------------------------------------------
// MARK: - @CName registry
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeCNameRegistryTests {

    @Test func registerAndLookupRoundTrip() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let fakePtr = 0x1_0000
        _ = kk_cname_register(nameHandle, fakePtr)

        let lookupNameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let found = kk_cname_lookup(lookupNameHandle)
        #expect(found == fakePtr)
    }

    @Test func lookupMissingNameReturnsZero() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("doesNotExist"))
        #expect(kk_cname_lookup(nameHandle) == 0)
    }

    @Test func registerOverwritesExistingEntry() {
        let nameHandle1 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle1, 0xAAAA)

        let nameHandle2 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle2, 0xBBBB)

        let lookupHandle = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        #expect(kk_cname_lookup(lookupHandle) == 0xBBBB)
    }

    @Test func registerWithInvalidNameHandleIsNoOp() {
        // Passing 0 as name handle must not crash and must not register anything.
        _ = kk_cname_register(0, 0x1234)
        #expect(kk_cname_lookup(0) == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt thread-safety smoke test
// ---------------------------------------------------------------------------

@Suite
struct RuntimeAtomicIntConcurrencyTests {

    @Test func concurrentIncrementWithFetchAndAdd() {
        let handle = kk_atomic_int_create(0)
        let iterations = 1000
        let queueCount = 4
        let group = DispatchGroup()

        for _ in 0..<queueCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<iterations {
                    _ = __kk_atomic_int_fetchAndAdd(handle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        #expect(waitResult == .success, "Concurrent increment timed out")
        #expect(__kk_atomic_int_load(handle) == queueCount * iterations,
                "Each increment must be atomic — no lost updates")
    }

    @Test func concurrentCompareAndSetExactlyOneSucceeds() {
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
                    _ = __kk_atomic_int_fetchAndAdd(winCountHandle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        #expect(waitResult == .success)
        #expect(__kk_atomic_int_load(winCountHandle) == 1,
                "Exactly one CAS must win when racing from 0 -> 1")
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean concurrency smoke test
// ---------------------------------------------------------------------------

@Suite
struct RuntimeAtomicBoolConcurrencyTests {

    @Test func concurrentStoreAndLoadNeverCrashes() {
        let handle = kk_atomic_bool_create(0)
        let group = DispatchGroup()
        for i in 0..<4 {
            let val = i % 2
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<500 {
                    _ = __kk_atomic_bool_store(handle, val)
                    _ = __kk_atomic_bool_load(handle)
                }
                group.leave()
            }
        }
        let waitResult = group.wait(timeout: .now() + .seconds(10))
        #expect(waitResult == .success, "Concurrent bool store/load timed out or crashed")
    }
}
