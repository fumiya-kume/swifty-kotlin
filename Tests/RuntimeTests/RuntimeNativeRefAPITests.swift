@testable import Runtime
import Testing

// STDLIB-NATIVE-REF-001: Inventory of kotlin.native.ref / kotlin.native.runtime APIs.
//
// This file documents what is implemented vs. what is missing in the KSwiftK
// runtime with respect to the Kotlin/Native standard library API surface.
//
// RUNTIME IMPLEMENTED (tested here and in RuntimeNativeRefRuntimeABITests):
//   kotlin.native.runtime namespace (via java.lang / System shims):
//     - System.gc()              -> __kk_system_gc()     (calls kk_gc_collect internally)
//     - Runtime.getRuntime()     -> __kk_runtime_getRuntime()
//     - Runtime.totalMemory()    -> __kk_runtime_totalMemory()
//     - Runtime.freeMemory()     -> __kk_runtime_freeMemory()
//     - Runtime.maxMemory()      -> __kk_runtime_maxMemory()
//
//   kotlin.native.ref shim (via kk_pin / kk_freeze):
//     - Pinned<T> (pin / unpin / get) -> kk_pin_object / kk_unpin_object / kk_pinned_get
//     - freeze() / isFrozen            -> kk_freeze_object / kk_is_frozen
//     - WeakReference<T>               -> kk_weak_ref_create / kk_weak_ref_get / kk_weak_ref_clear
//     - createCleaner(value, block)    -> kk_cleaner_create / kk_cleaner_clean / kk_cleaner_dispose
//
//   kotlin.native.runtime.GC:
//     - GC.collect()               -> kk_gc_collect()
//     - GC.schedule()              -> kk_gc_schedule()
//     - GC.targetHeapBytes         -> kk_gc_target_heap_bytes()
//     - GC.targetHeapUtilization   -> kk_gc_target_heap_utilization()
//     - GC.maxHeapBytes            -> kk_gc_max_heap_bytes()
//
//   kotlin.native.runtime.Debugging (via kk_assertions_* entry points):
//     - Debugging.areAssertionsEnabled    -> __kk_assertions_enabled()
//     - Debugging.setAssertionsEnabled()  -> kk_assertions_set_enabled()
//     - Debugging.isThreadStateRunnable   -> kk_debugging_is_thread_state_runnable()
//     - Debugging.gcSuspendCount          -> kk_debugging_gc_suspend_count()
//     - Debugging.threadCount             -> kk_debugging_thread_count()
//     - Debugging.globalObjectCount       -> kk_debugging_global_object_count()
//
// SEMA EXPOSED (compile-time stubs, covered by NativeRefRuntimeSemaTests):
//   - kotlin.native.ref.WeakReference<T>
//   - kotlin.native.ref.WeakReference.get()
//   - kotlin.native.ref.WeakReference.clear()
//   - kotlin.native.ref.createCleaner(value, block)
//   - kotlin.native.runtime.GC.collect()
//   - kotlin.native.runtime.GC.schedule()
//   - kotlin.native.runtime.GC.targetHeapBytes
//   - kotlin.native.runtime.GC.targetHeapUtilization
//   - kotlin.native.runtime.GC.maxHeapBytes
//   - kotlin.native.runtime.GCInfo
//   - kotlin.native.runtime.GCInfo.* timing / summary properties
//   - kotlin.native.runtime.MemoryUsage
//   - kotlin.native.runtime.MemoryUsage.totalObjectsSizeBytes
//   - kotlin.native.runtime.RootSetStatistics
//   - kotlin.native.runtime.RootSetStatistics.* root count properties
//   - kotlin.native.runtime.SweepStatistics
//   - kotlin.native.runtime.SweepStatistics.sweptCount / keptCount
//   - kotlin.native.runtime.NativeRuntimeApi
//   - kotlin.native.runtime.Debugging.isThreadStateRunnable
//   - kotlin.native.runtime.Debugging.gcSuspendCount
//   - kotlin.native.runtime.Debugging.threadCount
//   - kotlin.native.runtime.Debugging.globalObjectCount

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeRefGCTests {
    // MARK: - GC.collect() (kk_gc_collect)

    @Test func gcCollectIsCallableWithoutCrashing() {
        // Calling kk_gc_collect must not crash; it returns void.
        kk_gc_collect()
    }

    @Test func gcCollectMultipleTimesIsIdempotent() {
        // Repeated collects must leave the heap in the same state each time.
        let before = kk_runtime_heap_object_count()
        for _ in 0 ..< 3 {
            kk_gc_collect()
        }
        #expect(
            kk_runtime_heap_object_count() == before,
            "heap object count should be unchanged after repeated collects on an empty heap"
        )
    }

    @Test func systemGCIsCallableWithoutCrashing() {
        // __kk_system_gc() is the Kotlin-facing bridge; it must be callable without crash.
        __kk_system_gc()
    }

    @Test func gcCollectOnEmptyHeapIsNoOp() {
        // When no heap objects exist, collect should succeed immediately.
        #expect(kk_runtime_heap_object_count() == 0)
        kk_gc_collect()
        #expect(kk_runtime_heap_object_count() == 0)
    }
}

// NOTE: RuntimeNativeRefMemoryTests, RuntimeNativeRefPinnedTests,
// RuntimeNativeRefFreezeTests, RuntimeNativeRefDebuggingTests are defined in
// RuntimeNativeRefRuntimeABITests.swift (merged from master, STDLIB-NATIVE-REF-003).
// Only the GC tests unique to STDLIB-NATIVE-REF-001 are kept here.
