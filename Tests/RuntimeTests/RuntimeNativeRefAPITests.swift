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
//
//   kotlin.native.runtime.GC (via kk_gc_collect):
//     - GC.collect()  -> kk_gc_collect()  [no Kotlin-level GC object, raw C entry]
//
//   kotlin.native.runtime.Debugging (via kk_assertions_* entry points):
//     - Debugging.areAssertionsEnabled    -> kk_assertions_enabled()
//     - Debugging.setAssertionsEnabled()  -> kk_assertions_set_enabled()
//
// MISSING (not implemented — no runtime entry point or compiler-side stub):
//   - kotlin.native.ref.WeakReference<T>  (no kk_weak_ref_* entry points)
//   - kotlin.native.ref.WeakReference.get()
//   - kotlin.native.ref.WeakReference.clear()
//   - createCleaner { } (no kk_cleaner_* entry points)
//   - kotlin.native.runtime.GC.targetHeapBytes (property, not exposed)
//   - kotlin.native.runtime.GC.targetHeapUtilization (property, not exposed)
//   - kotlin.native.runtime.GC.maxHeapBytes (property, not exposed)
//   - kotlin.native.runtime.GC.schedule() (separate from collect, not exposed)
//   - kotlin.native.runtime.Debugging.gcSuspendCount
//   - kotlin.native.runtime.Debugging.threadCount
//   - kotlin.native.runtime.Debugging.globalObjectCount

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
