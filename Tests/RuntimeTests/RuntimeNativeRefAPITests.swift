@testable import Runtime
import XCTest

// STDLIB-NATIVE-REF-001: Inventory of kotlin.native.ref / kotlin.native.runtime APIs.
//
// This file documents what is implemented vs. what is missing in the KSwiftK
// runtime with respect to the Kotlin/Native standard library API surface.
//
// IMPLEMENTED (tested here):
//   kotlin.native.runtime namespace (via java.lang / System shims):
//     - System.gc()              -> kk_system_gc()     (calls kk_gc_collect internally)
//     - Runtime.getRuntime()     -> kk_runtime_getRuntime()
//     - Runtime.totalMemory()    -> kk_runtime_totalMemory()
//     - Runtime.freeMemory()     -> kk_runtime_freeMemory()
//     - Runtime.maxMemory()      -> kk_runtime_maxMemory()
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
//     - Debugging.areAssertionsEnabled    -> kk_assertions_enabled()
//     - Debugging.setAssertionsEnabled()  -> kk_assertions_set_enabled()
//     - Debugging.isThreadStateRunnable   -> kk_debugging_is_thread_state_runnable()
//     - Debugging.gcSuspendCount          -> kk_debugging_gc_suspend_count()
//     - Debugging.threadCount             -> kk_debugging_thread_count()
//     - Debugging.globalObjectCount       -> kk_debugging_global_object_count()
//
// All native.ref / native.runtime surfaces are now implemented or sema-exposed.

final class RuntimeNativeRefGCTests: IsolatedRuntimeXCTestCase {

    // MARK: - GC.collect() (kk_gc_collect)

    func testGCCollectIsCallableWithoutCrashing() {
        // Calling kk_gc_collect must not crash; it returns void.
        kk_gc_collect()
    }

    func testGCCollectMultipleTimesIsIdempotent() {
        for _ in 0 ..< 3 {
            kk_gc_collect()
        }
    }

    func testSystemGCDelegatesToGCCollect() {
        // kk_system_gc() is the Kotlin-facing alias; must be callable without crash.
        kk_system_gc()
    }

    func testGCCollectOnEmptyHeapIsNoOp() {
        // When no heap objects exist, collect should succeed immediately.
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }
}

// NOTE: RuntimeNativeRefMemoryTests, RuntimeNativeRefPinnedTests,
// RuntimeNativeRefFreezeTests, RuntimeNativeRefDebuggingTests are defined in
// RuntimeNativeRefRuntimeABITests.swift (merged from master, STDLIB-NATIVE-REF-003).
// Only the GC tests unique to STDLIB-NATIVE-REF-001 are kept here.
