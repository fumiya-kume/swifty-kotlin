@testable import Runtime
import Testing

// MARK: - kotlin.native.ref / kotlin.native.runtime minimal ABI coverage (STDLIB-NATIVE-REF-003)
//
// Stability boundaries tested:
//   GC        - positive return values, repeated kk_gc_collect() idempotent on empty heap,
//               gc collect after alloc-and-root leaves pinned object alive
//   Memory    - __kk_runtime_getRuntime() stable singleton, totalMemory/freeMemory/maxMemory positive
//   Pinned    - kk_pin_object returns non-zero handle, kk_pinned_get round-trips original raw value,
//               kk_unpin_object returns original object raw, pinned object survives GC while pinned,
//               repeated unpin on already-unpinned handle is safe (returns 0)
//   freeze    - kk_freeze_object returns same handle (positive return),
//               repeated freeze is idempotent, isFrozen is stable across multiple queries,
//               freeze propagation: freezing parent does NOT auto-freeze child (registry is flat),
//               child can be independently frozen; both parent and child frozen state independent
//   Debugging - __kk_assertions_enabled returns 0 or 1, repeated enable/disable idempotent,
//               kk_assertions_reset restores to a valid boolean state

// ---------------------------------------------------------------------------
// MARK: - GC stability tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefGCStabilityTests {
    @Test func gcCollectOnEmptyHeapIsIdempotent() {
        // After reset, heap is empty; multiple collects must not crash.
        kk_gc_collect()
        kk_gc_collect()
        kk_gc_collect()
        #expect(kk_runtime_heap_object_count() == 0)
    }

    @Test func gcCollectReturnsAndHeapCountDropsToZero() {
        // Allocate an unrooted object; after collect the heap must be empty.
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(16, ti)
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func gcCollectIsIdempotentAfterAlreadyEmpty() {
        // After the heap is emptied by one collect, a second collect must be a no-op.
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(8, ti)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func systemGCIsEquivalentToGCCollect() {
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(8, ti)
            #expect(kk_runtime_heap_object_count() == 1)
            __kk_system_gc()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func gcScheduleTriggersCollection() {
        withDummyNativeRefTypeInfo { ti in
            _ = kk_alloc(8, ti)
            #expect(kk_runtime_heap_object_count() == 1)
            #expect(kk_gc_schedule() == 0)
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func gcTargetHeapBytesIsPositive() {
        #expect(kk_gc_target_heap_bytes() > 0)
    }

    @Test func gcTargetHeapUtilizationIsWithinValidRange() {
        let utilization = kk_gc_target_heap_utilization()
        #expect(utilization > 0)
        #expect(utilization <= 1)
    }

    @Test func gcMaxHeapBytesIsAtLeastTargetHeapBytes() {
        #expect(kk_gc_max_heap_bytes() >= kk_gc_target_heap_bytes())
    }

    @Test func heapObjectCountPositiveAfterAlloc() {
        withDummyNativeRefTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_register_global_root(slot)
            #expect(kk_runtime_heap_object_count() == 1,
                    "Heap must report exactly one object after rooted alloc")
            kk_unregister_global_root(slot)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Memory positive-return / singleton tests
// ---------------------------------------------------------------------------

@Suite
struct RuntimeNativeRefMemoryTests {
    @Test func getRuntimeReturnsPositiveHandle() {
        #expect(__kk_runtime_getRuntime() > 0,
                "__kk_runtime_getRuntime must return a non-zero singleton handle")
    }

    @Test func getRuntimeIsSingleton() {
        #expect(__kk_runtime_getRuntime() == __kk_runtime_getRuntime(),
                "__kk_runtime_getRuntime must return the same value on repeated calls")
    }

    @Test func totalMemoryIsPositive() {
        #expect(__kk_runtime_totalMemory() > 0)
    }

    @Test func freeMemoryIsNonNegative() {
        #expect(__kk_runtime_freeMemory() >= 0)
    }

    @Test func maxMemoryIsAtLeastTotalMemory() {
        #expect(__kk_runtime_maxMemory() >= __kk_runtime_totalMemory())
    }

    @Test func memoryMetricsStableAcrossRepeatedCalls() {
        // Max memory must be non-decreasing (same process, no dealloc between calls).
        let max1 = __kk_runtime_maxMemory()
        let max2 = __kk_runtime_maxMemory()
        #expect(max1 == max2,
                "Max memory must be stable across back-to-back queries")
    }
}

// ---------------------------------------------------------------------------
// MARK: - WeakReference<T> runtime tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefWeakReferenceTests {
    @Test func weakReferenceCreateReturnsNonZeroHandle() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        #expect(weakRaw != 0)
    }

    @Test func weakReferenceGetReturnsLiveRuntimeObject() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        #expect(kk_weak_ref_get(weakRaw) == objectRaw)
    }

    @Test func weakReferenceClearDropsReferent() {
        let objectRaw = registerRuntimeObject(RuntimeStringBox("weak"))
        let weakRaw = kk_weak_ref_create(objectRaw)
        #expect(kk_weak_ref_get(weakRaw) == objectRaw)
        #expect(kk_weak_ref_clear(weakRaw) == 0)
        #expect(kk_weak_ref_get(weakRaw) == 0)
    }

    @Test func weakReferenceToCollectedHeapObjectReturnsNull() {
        withDummyNativeRefTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: object)
            let weakRaw = kk_weak_ref_create(objectRaw)
            #expect(kk_weak_ref_get(weakRaw) == objectRaw)

            kk_gc_collect()

            #expect(kk_weak_ref_get(weakRaw) == 0)
        }
    }

    @Test func weakReferenceInvalidHandleIsNullSafe() {
        #expect(kk_weak_ref_get(0) == 0)
        #expect(kk_weak_ref_clear(0) == 0)
        #expect(kk_weak_ref_get(12345) == 0)
        #expect(kk_weak_ref_clear(12345) == 0)
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

private func resetRuntimeNativeRefCleanerTestState() {
    nativeRefCleanerCallCount = 0
    nativeRefCleanerLastValue = 0
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeNativeRefCleanerTestState))
struct RuntimeNativeRefCleanerTests {
    @Test func cleanerCreateReturnsNonZeroHandle() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        #expect(kk_cleaner_create(valueRaw, blockRaw) != 0)
    }

    @Test func cleanerCleanInvokesBlockOnceWithValue() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)

        #expect(kk_cleaner_clean(cleanerRaw, nil) == 0)
        #expect(nativeRefCleanerCallCount == 1)
        #expect(nativeRefCleanerLastValue == valueRaw)

        #expect(kk_cleaner_clean(cleanerRaw, nil) == 0)
        #expect(nativeRefCleanerCallCount == 1)
    }

    @Test func cleanerDisposeDropsWithoutInvokingBlock() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)

        #expect(kk_cleaner_dispose(cleanerRaw) == 0)
        #expect(kk_cleaner_clean(cleanerRaw, nil) == 0)
        #expect(nativeRefCleanerCallCount == 0)
    }

    @Test func cleanerCleanPropagatesThrownHandle() {
        let valueRaw = registerRuntimeObject(RuntimeStringBox("clean"))
        let blockRaw = unsafeBitCast(nativeRefCleanerThrowingBlock, to: Int.self)
        let cleanerRaw = kk_cleaner_create(valueRaw, blockRaw)
        var thrown = 0

        #expect(kk_cleaner_clean(cleanerRaw, &thrown) == 0)
        #expect(thrown == 0xC1EA)
    }

    @Test func cleanerInvalidHandleIsNullSafe() {
        #expect(kk_cleaner_create(0, 0) == 0)
        #expect(kk_cleaner_clean(0, nil) == 0)
        #expect(kk_cleaner_dispose(0) == 0)
        #expect(kk_cleaner_clean(12345, nil) == 0)
        #expect(kk_cleaner_dispose(12345) == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pinned<T> stability tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefPinnedTests {
    @Test func pinObjectReturnsNonZeroHandle() {
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
            #expect(pinHandle != 0,
                    "kk_pin_object must return a non-zero Pinned handle")
            _ = kk_unpin_object(pinHandle)
        }
    }

    @Test func pinnedGetRoundTripsOriginalRaw() {
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
            #expect(kk_pinned_get(pinHandle) == objectRaw,
                    "kk_pinned_get must return the same raw value passed to kk_pin_object")
            _ = kk_unpin_object(pinHandle)
        }
    }

    @Test func unpinObjectReturnsOriginalRaw() {
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
            #expect(returned == objectRaw,
                    "kk_unpin_object must return the original object raw value")
        }
    }

    @Test func pinObjectZeroHandleIsNoOp() {
        // Pinning a null reference must not crash and must return 0.
        let pinHandle = kk_pin_object(0)
        #expect(pinHandle == 0)
    }

    @Test func pinnedGetOnZeroHandleReturnsZero() {
        #expect(kk_pinned_get(0) == 0)
    }

    @Test func unpinOnZeroHandleReturnsZero() {
        #expect(kk_unpin_object(0) == 0)
    }

    @Test func pinnedObjectSurvivesGCWhilePinned() {
        withDummyNativeRefTypeInfo { ti in
            let obj = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: obj)
            // Pin the object; it must survive a GC collect even without a global root.
            let pinHandle = kk_pin_object(objectRaw)
            #expect(pinHandle != 0)
            kk_gc_collect()
            // Object must still be reachable via the pin handle after GC.
            #expect(kk_pinned_get(pinHandle) == objectRaw,
                    "Pinned object must survive GC while the pin is held")
            _ = kk_unpin_object(pinHandle)
        }
    }

    @Test func multiplePinsOnSameObjectAreIndependent() {
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
            #expect(pinA != pinB,
                    "Two separate pin calls must yield distinct handles")
            #expect(kk_pinned_get(pinA) == objectRaw)
            #expect(kk_pinned_get(pinB) == objectRaw)
            _ = kk_unpin_object(pinA)
            _ = kk_unpin_object(pinB)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - freeze() stability & propagation tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefFreezeTests {
    @Test func freezeObjectReturnsPositiveHandleForNonZeroInput() {
        let handle = makeNativeRefFreezeHandle()
        let returned = kk_freeze_object(handle)
        #expect(returned > 0,
                "kk_freeze_object must return a positive (non-zero) value")
    }

    @Test func freezeObjectReturnsOriginalHandle() {
        let handle = makeNativeRefFreezeHandle()
        #expect(kk_freeze_object(handle) == handle)
    }

    @Test func isFrozenStableAcrossRepeatedQueries() {
        let handle = makeNativeRefFreezeHandle()
        kk_freeze_object(handle)
        // Query three times; each must return 1.
        #expect(kk_is_frozen(handle) == 1)
        #expect(kk_is_frozen(handle) == 1)
        #expect(kk_is_frozen(handle) == 1)
    }

    @Test func repeatedFreezeIsIdempotent() {
        let handle = makeNativeRefFreezeHandle()
        kk_freeze_object(handle)
        kk_freeze_object(handle)
        kk_freeze_object(handle)
        #expect(kk_is_frozen(handle) == 1,
                "Repeated freeze calls must leave the object frozen (idempotent)")
    }

    @Test func freezingParentDoesNotAutoFreezeChildReference() {
        // The freeze registry is flat (per-object address); freezing the parent
        // handle does NOT automatically propagate frozen state to the child handle.
        let parent = makeNativeRefFreezeHandle()
        let child = makeNativeRefFreezeHandle()
        kk_freeze_object(parent)
        #expect(kk_is_frozen(parent) == 1)
        #expect(kk_is_frozen(child) == 0,
                "Freezing parent must NOT auto-freeze the child (flat registry)")
    }

    @Test func freezeChildAfterParentFreezeIsIndependent() {
        let parent = makeNativeRefFreezeHandle()
        let child = makeNativeRefFreezeHandle()
        kk_freeze_object(parent)
        kk_freeze_object(child)
        #expect(kk_is_frozen(parent) == 1)
        #expect(kk_is_frozen(child) == 1,
                "Child can be independently frozen after parent is frozen")
    }

    @Test func freezeNullIsNoOpAndReturnsZero() {
        #expect(kk_freeze_object(0) == 0)
        #expect(kk_is_frozen(0) == 0)
    }

    @Test func freezeAndPinInteractionPreservesFreeze() {
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
            #expect(kk_is_frozen(objectRaw) == 1,
                    "Pinning a frozen object must not change its frozen state")
            _ = kk_unpin_object(pinHandle)
        }
    }

    @Test func freezeAfterPinPreservesFreezeAndPin() {
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
            #expect(kk_is_frozen(objectRaw) == 1)
            #expect(kk_pinned_get(pinHandle) == objectRaw,
                    "Freezing a pinned object must not invalidate the pin handle")
            _ = kk_unpin_object(pinHandle)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Debugging / assertions ABI tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefDebuggingTests {
    @Test func assertionsEnabledReturnsBooleanValue() {
        let result = __kk_assertions_enabled()
        #expect(result == 0 || result == 1,
                "__kk_assertions_enabled must return 0 or 1")
    }

    @Test func disableEnableAssertionsIdempotent() {
        _ = kk_assertions_set_enabled(0)
        #expect(__kk_assertions_enabled() == 0)
        _ = kk_assertions_set_enabled(0)
        #expect(__kk_assertions_enabled() == 0,
                "Disabling already-disabled assertions must be idempotent")
    }

    @Test func enableAssertionsIdempotent() {
        _ = kk_assertions_set_enabled(1)
        #expect(__kk_assertions_enabled() == 1)
        _ = kk_assertions_set_enabled(1)
        #expect(__kk_assertions_enabled() == 1,
                "Enabling already-enabled assertions must be idempotent")
    }

    @Test func toggleAssertionsRoundTrip() {
        _ = kk_assertions_set_enabled(1)
        #expect(__kk_assertions_enabled() == 1)
        _ = kk_assertions_set_enabled(0)
        #expect(__kk_assertions_enabled() == 0)
        _ = kk_assertions_set_enabled(1)
        #expect(__kk_assertions_enabled() == 1)
    }

    @Test func assertionsResetRestoresValidBooleanState() {
        _ = kk_assertions_set_enabled(0)
        _ = kk_assertions_reset()
        let result = __kk_assertions_enabled()
        #expect(result == 0 || result == 1,
                "kk_assertions_reset must leave assertions in a valid boolean state")
    }

    @Test func repeatedAssertionsResetIsIdempotent() {
        _ = kk_assertions_reset()
        let first = __kk_assertions_enabled()
        _ = kk_assertions_reset()
        let second = __kk_assertions_enabled()
        #expect(first == second,
                "Repeated kk_assertions_reset must yield consistent state")
    }

    @Test func debuggingIsThreadStateRunnableReturnsBoolean() {
        let result = kk_debugging_is_thread_state_runnable()
        #expect(result == 0 || result == 1)
    }

    @Test func debuggingTrackingCountsAreNonNegative() {
        #expect(kk_debugging_gc_suspend_count() >= 0)
        #expect(kk_debugging_thread_count() >= 1)
        #expect(kk_debugging_global_object_count() >= 0)
    }

    @Test func debuggingGlobalObjectCountTracksRuntimeObjects() {
        let before = kk_debugging_global_object_count()
        _ = registerRuntimeObject(RuntimeStringBox("debug"))
        #expect(kk_debugging_global_object_count() == before + 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Private test helpers
// ---------------------------------------------------------------------------


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
