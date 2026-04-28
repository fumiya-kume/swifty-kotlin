@testable import Runtime
import XCTest

// MARK: - kotlin.native.ref / kotlin.native.runtime minimal ABI coverage (STDLIB-NATIVE-REF-003)
//
// Stability boundaries tested:
//   GC        - positive return values, repeated kk_gc_collect() idempotent on empty heap,
//               gc collect after alloc-and-root leaves pinned object alive
//   Memory    - kk_runtime_getRuntime() stable singleton, totalMemory/freeMemory/maxMemory positive
//   Pinned    - kk_pin_object returns non-zero handle, kk_pinned_get round-trips original raw value,
//               kk_unpin_object returns original object raw, pinned object survives GC while pinned,
//               repeated unpin on already-unpinned handle is safe (returns 0)
//   freeze    - kk_freeze_object returns same handle (positive return),
//               repeated freeze is idempotent, isFrozen is stable across multiple queries,
//               freeze propagation: freezing parent does NOT auto-freeze child (registry is flat),
//               child can be independently frozen; both parent and child frozen state independent
//   Debugging - kk_assertions_enabled returns 0 or 1, repeated enable/disable idempotent,
//               kk_assertions_reset restores to a valid boolean state

// ---------------------------------------------------------------------------
// MARK: - GC stability tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefGCStabilityTests: IsolatedRuntimeXCTestCase {

    func testGCCollectOnEmptyHeapIsIdempotent() {
        // After reset, heap is empty; multiple collects must not crash.
        kk_gc_collect()
        kk_gc_collect()
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }

    func testGCCollectReturnsAndHeapCountDropsToZero() {
        // Allocate an unrooted object; after collect the heap must be empty.
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(16, ti)
            XCTAssertEqual(kk_runtime_heap_object_count(), 1)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        }
    }

    func testGCCollectIsIdempotentAfterAlreadyEmpty() {
        // After the heap is emptied by one collect, a second collect must be a no-op.
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(8, ti)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        }
    }

    func testSystemGCIsEquivalentToGCCollect() {
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(8, ti)
            XCTAssertEqual(kk_runtime_heap_object_count(), 1)
            kk_system_gc()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        }
    }

    func testHeapObjectCountPositiveAfterAlloc() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_register_global_root(slot)
            XCTAssertEqual(kk_runtime_heap_object_count(), 1,
                           "Heap must report exactly one object after rooted alloc")
            kk_unregister_global_root(slot)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Memory positive-return / singleton tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefMemoryTests: XCTestCase {

    func testGetRuntimeReturnsPositiveHandle() {
        XCTAssertGreaterThan(kk_runtime_getRuntime(), 0,
                             "kk_runtime_getRuntime must return a non-zero singleton handle")
    }

    func testGetRuntimeIsSingleton() {
        XCTAssertEqual(kk_runtime_getRuntime(), kk_runtime_getRuntime(),
                       "kk_runtime_getRuntime must return the same value on repeated calls")
    }

    func testTotalMemoryIsPositive() {
        XCTAssertGreaterThan(kk_runtime_totalMemory(), 0)
    }

    func testFreeMemoryIsNonNegative() {
        XCTAssertGreaterThanOrEqual(kk_runtime_freeMemory(), 0)
    }

    func testMaxMemoryIsAtLeastTotalMemory() {
        XCTAssertGreaterThanOrEqual(kk_runtime_maxMemory(), kk_runtime_totalMemory())
    }

    func testMemoryMetricsStableAcrossRepeatedCalls() {
        // Max memory must be non-decreasing (same process, no dealloc between calls).
        let max1 = kk_runtime_maxMemory()
        let max2 = kk_runtime_maxMemory()
        XCTAssertEqual(max1, max2,
                       "Max memory must be stable across back-to-back queries")
    }
}

// ---------------------------------------------------------------------------
// MARK: - WeakReference<T> runtime tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefWeakReferenceTests: IsolatedRuntimeXCTestCase {

    func testWeakReferenceCreateReturnsNonZeroHandle() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        XCTAssertNotEqual(weakRaw, 0)
    }

    func testWeakReferenceGetReturnsLiveRuntimeObject() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        XCTAssertEqual(kk_weak_ref_get(weakRaw), objectRaw)
    }

    func testWeakReferenceClearDropsReferent() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        XCTAssertEqual(kk_weak_ref_get(weakRaw), objectRaw)
        XCTAssertEqual(kk_weak_ref_clear(weakRaw), 0)
        XCTAssertEqual(kk_weak_ref_get(weakRaw), 0)
    }

    func testWeakReferenceToCollectedHeapObjectReturnsNull() {
        withDummyNativeRefTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: object)
            let weakRaw = kk_weak_ref_create(objectRaw)
            XCTAssertEqual(kk_weak_ref_get(weakRaw), objectRaw)

            kk_gc_collect()

            XCTAssertEqual(kk_weak_ref_get(weakRaw), 0)
        }
    }

    func testWeakReferenceInvalidHandleIsNullSafe() {
        XCTAssertEqual(kk_weak_ref_get(0), 0)
        XCTAssertEqual(kk_weak_ref_clear(0), 0)
        XCTAssertEqual(kk_weak_ref_get(12345), 0)
        XCTAssertEqual(kk_weak_ref_clear(12345), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - createCleaner runtime tests
// ---------------------------------------------------------------------------

nonisolated(unsafe) private var nativeRefCleanerCallCount = 0
nonisolated(unsafe) private var nativeRefCleanerLastValue = 0

private let nativeRefCleanerBlock: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { value, outThrown in
    outThrown?.pointee = 0
    nativeRefCleanerCallCount += 1
    nativeRefCleanerLastValue = value
    return 0
}

private let nativeRefCleanerThrowingBlock: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xC1EA
    return 0
}

final class RuntimeNativeRefCleanerTests: IsolatedRuntimeXCTestCase {

    override func resetIsolatedRuntimeTestState() {
        nativeRefCleanerCallCount = 0
        nativeRefCleanerLastValue = 0
    }

    func testCleanerCreateReturnsNonZeroHandle() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        XCTAssertNotEqual(kk_cleaner_create(valueRaw, blockRaw), 0)
    }

    func testCleanerCleanInvokesBlockOnceWithValue() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)

        XCTAssertEqual(kk_cleaner_clean(cleanerRaw, nil), 0)
        XCTAssertEqual(nativeRefCleanerCallCount, 1)
        XCTAssertEqual(nativeRefCleanerLastValue, valueRaw)

        XCTAssertEqual(kk_cleaner_clean(cleanerRaw, nil), 0)
        XCTAssertEqual(nativeRefCleanerCallCount, 1)
    }

    func testCleanerDisposeDropsWithoutInvokingBlock() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)

        XCTAssertEqual(kk_cleaner_dispose(cleanerRaw), 0)
        XCTAssertEqual(kk_cleaner_clean(cleanerRaw, nil), 0)
        XCTAssertEqual(nativeRefCleanerCallCount, 0)
    }

    func testCleanerCleanPropagatesThrownHandle() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerThrowingBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)
        var thrown = 0

        XCTAssertEqual(kk_cleaner_clean(cleanerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0xC1EA)
    }

    func testCleanerInvalidHandleIsNullSafe() {
        XCTAssertEqual(kk_cleaner_create(0, 0), 0)
        XCTAssertEqual(kk_cleaner_clean(0, nil), 0)
        XCTAssertEqual(kk_cleaner_dispose(0), 0)
        XCTAssertEqual(kk_cleaner_clean(12345, nil), 0)
        XCTAssertEqual(kk_cleaner_dispose(12345), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pinned<T> stability tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefPinnedTests: IsolatedRuntimeXCTestCase {

    func testPinObjectReturnsNonZeroHandle() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            let pinHandle = kk_pin_object(objectRaw)
            XCTAssertNotEqual(pinHandle, 0,
                              "kk_pin_object must return a non-zero Pinned handle")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testPinnedGetRoundTripsOriginalRaw() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            let pinHandle = kk_pin_object(objectRaw)
            XCTAssertEqual(kk_pinned_get(pinHandle), objectRaw,
                           "kk_pinned_get must return the same raw value passed to kk_pin_object")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testUnpinObjectReturnsOriginalRaw() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            let pinHandle = kk_pin_object(objectRaw)
            let returned = kk_unpin_object(pinHandle)
            XCTAssertEqual(returned, objectRaw,
                           "kk_unpin_object must return the original object raw value")
        }
    }

    func testPinObjectZeroHandleIsNoOp() {
        // Pinning a null reference must not crash and must return 0.
        let pinHandle = kk_pin_object(0)
        XCTAssertEqual(pinHandle, 0)
    }

    func testPinnedGetOnZeroHandleReturnsZero() {
        XCTAssertEqual(kk_pinned_get(0), 0)
    }

    func testUnpinOnZeroHandleReturnsZero() {
        XCTAssertEqual(kk_unpin_object(0), 0)
    }

    func testPinnedObjectSurvivesGCWhilePinned() {
        withDummyNativeRefTypeInfo { ti in
            let obj = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: obj)
            // Pin the object; it must survive a GC collect even without a global root.
            let pinHandle = kk_pin_object(objectRaw)
            XCTAssertNotEqual(pinHandle, 0)
            kk_gc_collect()
            // Object must still be reachable via the pin handle after GC.
            XCTAssertEqual(kk_pinned_get(pinHandle), objectRaw,
                           "Pinned object must survive GC while the pin is held")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testMultiplePinsOnSameObjectAreIndependent() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            let pinA = kk_pin_object(objectRaw)
            let pinB = kk_pin_object(objectRaw)
            XCTAssertNotEqual(pinA, pinB,
                              "Two separate pin calls must yield distinct handles")
            XCTAssertEqual(kk_pinned_get(pinA), objectRaw)
            XCTAssertEqual(kk_pinned_get(pinB), objectRaw)
            _ = kk_unpin_object(pinA)
            _ = kk_unpin_object(pinB)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - freeze() stability & propagation tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefFreezeTests: IsolatedRuntimeXCTestCase {

    func testFreezeObjectReturnsPositiveHandleForNonZeroInput() {
        let handle = makeNativeRefFreezeHandle()
        let returned = kk_freeze_object(handle)
        XCTAssertGreaterThan(returned, 0,
                             "kk_freeze_object must return a positive (non-zero) value")
    }

    func testFreezeObjectReturnsOriginalHandle() {
        let handle = makeNativeRefFreezeHandle()
        XCTAssertEqual(kk_freeze_object(handle), handle)
    }

    func testIsFrozenStableAcrossRepeatedQueries() {
        let handle = makeNativeRefFreezeHandle()
        kk_freeze_object(handle)
        // Query three times; each must return 1.
        XCTAssertEqual(kk_is_frozen(handle), 1)
        XCTAssertEqual(kk_is_frozen(handle), 1)
        XCTAssertEqual(kk_is_frozen(handle), 1)
    }

    func testRepeatedFreezeIsIdempotent() {
        let handle = makeNativeRefFreezeHandle()
        kk_freeze_object(handle)
        kk_freeze_object(handle)
        kk_freeze_object(handle)
        XCTAssertEqual(kk_is_frozen(handle), 1,
                       "Repeated freeze calls must leave the object frozen (idempotent)")
    }

    func testFreezingParentDoesNotAutoFreezeChildReference() {
        // The freeze registry is flat (per-object address); freezing the parent
        // handle does NOT automatically propagate frozen state to the child handle.
        let parent = makeNativeRefFreezeHandle()
        let child = makeNativeRefFreezeHandle()
        kk_freeze_object(parent)
        XCTAssertEqual(kk_is_frozen(parent), 1)
        XCTAssertEqual(kk_is_frozen(child), 0,
                       "Freezing parent must NOT auto-freeze the child (flat registry)")
    }

    func testFreezeChildAfterParentFreezeIsIndependent() {
        let parent = makeNativeRefFreezeHandle()
        let child = makeNativeRefFreezeHandle()
        kk_freeze_object(parent)
        kk_freeze_object(child)
        XCTAssertEqual(kk_is_frozen(parent), 1)
        XCTAssertEqual(kk_is_frozen(child), 1,
                       "Child can be independently frozen after parent is frozen")
    }

    func testFreezeNullIsNoOpAndReturnsZero() {
        XCTAssertEqual(kk_freeze_object(0), 0)
        XCTAssertEqual(kk_is_frozen(0), 0)
    }

    func testFreezeAndPinInteractionPreservesFreeze() {
        // Pinning a frozen object must not change its frozen state.
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            kk_freeze_object(objectRaw)
            let pinHandle = kk_pin_object(objectRaw)
            XCTAssertEqual(kk_is_frozen(objectRaw), 1,
                           "Pinning a frozen object must not change its frozen state")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testFreezeAfterPinPreservesFreezeAndPin() {
        // Freezing a pinned object must not invalidate the pin.
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            kk_register_global_root(slot)
            defer {
                kk_unregister_global_root(slot)
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            let objectRaw = Int(bitPattern: slot.pointee)
            let pinHandle = kk_pin_object(objectRaw)
            kk_freeze_object(objectRaw)
            XCTAssertEqual(kk_is_frozen(objectRaw), 1)
            XCTAssertEqual(kk_pinned_get(pinHandle), objectRaw,
                           "Freezing a pinned object must not invalidate the pin handle")
            _ = kk_unpin_object(pinHandle)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Debugging / assertions ABI tests
// ---------------------------------------------------------------------------

final class RuntimeNativeRefDebuggingTests: XCTestCase {

    func testAssertionsEnabledReturnsBooleanValue() {
        let result = kk_assertions_enabled()
        XCTAssertTrue(result == 0 || result == 1,
                      "kk_assertions_enabled must return 0 or 1")
    }

    func testDisableEnableAssertionsIdempotent() {
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0,
                       "Disabling already-disabled assertions must be idempotent")
    }

    func testEnableAssertionsIdempotent() {
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1,
                       "Enabling already-enabled assertions must be idempotent")
    }

    func testToggleAssertionsRoundTrip() {
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)
        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)
        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)
    }

    func testAssertionsResetRestoresValidBooleanState() {
        _ = kk_assertions_set_enabled(0)
        _ = kk_assertions_reset()
        let result = kk_assertions_enabled()
        XCTAssertTrue(result == 0 || result == 1,
                      "kk_assertions_reset must leave assertions in a valid boolean state")
    }

    func testRepeatedAssertionsResetIsIdempotent() {
        _ = kk_assertions_reset()
        let first = kk_assertions_enabled()
        _ = kk_assertions_reset()
        let second = kk_assertions_enabled()
        XCTAssertEqual(first, second,
                       "Repeated kk_assertions_reset must yield consistent state")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Private test helpers
// ---------------------------------------------------------------------------

private struct NativeRefObjHeaderProbe {
    let typeInfo: UnsafePointer<KTypeInfo>?
    let flags: UInt32
    let size: UInt32
}

private func withDummyNativeRefTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    let typeName = Array("Test.NativeRef\0".utf8).map(CChar.init)
    let offsetStorage = [UInt32(0)]
    var emptyVtableEntry = UnsafeRawPointer(bitPattern: 0x1)!
    typeName.withUnsafeBufferPointer { nameBuffer in
        offsetStorage.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &emptyVtableEntry) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: 0,
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 0,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo) { typeInfoPtr in
                    body(UnsafeRawPointer(typeInfoPtr))
                }
            }
        }
    }
}

/// Returns a non-zero managed handle suitable for freeze/isFrozen tests.
private func makeNativeRefFreezeHandle() -> Int {
    kk_atomic_int_create(0)
}
