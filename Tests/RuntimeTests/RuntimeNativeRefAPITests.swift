// STDLIB-NATIVE-REF-001 v2: kotlin.native.ref / kotlin.native.runtime API inventory
//
// Covered APIs:
//   kotlin.native.ref.WeakReference<T>  — .get() member
//   kotlin.native.ref.createCleaner     — top-level factory (returns Cleaner)
//   kotlin.native.runtime.GC            — .collect() / .schedule()
//   kotlin.native.runtime.Debugging     — .isThreadStateRunnable / .gcSuspendCount
//
// Gaps are recorded with XCTSkip and a gap ID for tracking.
//
// Gap table:
//   GAP-NREF-001  WeakReference<T> constructor (kk_weak_reference_new) — not yet emitted
//   GAP-NREF-002  WeakReference<T>.get()   (kk_weak_reference_get)     — not yet emitted
//   GAP-NREF-003  createCleaner            (kk_create_cleaner)          — not yet emitted
//   GAP-NREF-004  Cleaner type handle                                    — not yet emitted
//   GAP-NREF-005  GC.schedule()            (kk_gc_schedule)             — not yet emitted
//   GAP-NREF-006  Debugging.isThreadStateRunnable — not yet emitted
//   GAP-NREF-007  Debugging.gcSuspendCount        — not yet emitted

@testable import Runtime
import XCTest

// MARK: - Helpers

private struct ObjHeaderProbe {
    let typeInfo: UnsafePointer<KTypeInfo>?
    let flags: UInt32
    let size: UInt32
}

private func withDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    let typeName = Array("Test.NativeRef\0".utf8).map(CChar.init)
    let offsetStorage: [UInt32] = [UInt32(0)]
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
                withUnsafePointer(to: &typeInfo) { body(UnsafeRawPointer($0)) }
            }
        }
    }
}

// MARK: - Test class

final class RuntimeNativeRefAPITests: IsolatedRuntimeXCTestCase {

    // MARK: kotlin.native.runtime.GC

    /// GC.collect() — kk_gc_collect is implemented; verify that unreachable
    /// heap objects are freed after a collection cycle.
    func testGCCollectFreesUnreachableObjects() {
        withDummyTypeInfo { ti in
            _ = kk_alloc(16, ti)
            XCTAssertEqual(kk_runtime_heap_object_count(), 1, "one object should be on the heap before collect")
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0, "GC.collect() must reclaim unreachable objects")
        }
    }

    /// GC.collect() — rooted objects survive a collection cycle.
    func testGCCollectPreservesRootedObjects() {
        withDummyTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_register_global_root(slot)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 1, "rooted object must survive GC.collect()")
            slot.pointee = nil
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0, "released root must allow collection")
            kk_unregister_global_root(slot)
        }
    }

    /// GC.collect() — multiple unreachable objects are all freed.
    func testGCCollectFreesMultipleUnreachableObjects() {
        withDummyTypeInfo { ti in
            for _ in 0..<5 {
                _ = kk_alloc(8, ti)
            }
            XCTAssertEqual(kk_runtime_heap_object_count(), 5)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0, "all unreachable objects must be freed")
        }
    }

    /// GC.collect() is idempotent — calling it on an empty heap is safe.
    func testGCCollectOnEmptyHeapIsNoop() {
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }

    /// GC.schedule() — kk_gc_schedule is sema-stubbed but not yet emitted.
    /// GAP-NREF-005
    func testGCScheduleGap() throws {
        throw XCTSkip("[GAP-NREF-005] GC.schedule() (kk_gc_schedule) is declared in sema stubs but has no runtime implementation yet")
    }

    // MARK: kotlin.native.ref.WeakReference<T>

    /// WeakReference<T> constructor — kk_weak_reference_new is not emitted.
    /// GAP-NREF-001
    func testWeakReferenceConstructorGap() throws {
        throw XCTSkip("[GAP-NREF-001] WeakReference<T> constructor (kk_weak_reference_new) is not yet implemented in the runtime")
    }

    /// WeakReference<T>.get() — kk_weak_reference_get is not emitted.
    /// GAP-NREF-002
    func testWeakReferenceGetGap() throws {
        throw XCTSkip("[GAP-NREF-002] WeakReference<T>.get() (kk_weak_reference_get) is not yet implemented in the runtime")
    }

    // MARK: kotlin.native.ref.createCleaner / Cleaner

    /// createCleaner — kk_create_cleaner is not emitted.
    /// GAP-NREF-003
    func testCreateCleanerGap() throws {
        throw XCTSkip("[GAP-NREF-003] createCleaner (kk_create_cleaner) is not yet implemented in the runtime")
    }

    /// Cleaner type handle — no Cleaner runtime type exists yet.
    /// GAP-NREF-004
    func testCleanerTypeHandleGap() throws {
        throw XCTSkip("[GAP-NREF-004] Cleaner type/handle is not yet implemented in the runtime")
    }

    // MARK: kotlin.native.runtime.Debugging

    /// Debugging.isThreadStateRunnable — no runtime backing.
    /// GAP-NREF-006
    func testDebuggingIsThreadStateRunnableGap() throws {
        throw XCTSkip("[GAP-NREF-006] Debugging.isThreadStateRunnable is not yet implemented in the runtime")
    }

    /// Debugging.gcSuspendCount — no runtime backing.
    /// GAP-NREF-007
    func testDebuggingGCSuspendCountGap() throws {
        throw XCTSkip("[GAP-NREF-007] Debugging.gcSuspendCount is not yet implemented in the runtime")
    }

    // MARK: Pinned<T> — kotlin.native.ref.Pinned<T> is implemented

    /// kk_pin_object / kk_pinned_get / kk_unpin_object — object handle
    /// round-trips through pin/get/unpin correctly.
    func testPinnedGetReturnsOriginalObjectHandle() {
        withDummyTypeInfo { ti in
            let obj = kk_alloc(24, ti)
            let rawObj = Int(bitPattern: obj)
            let pinnedHandle = kk_pin_object(rawObj)
            XCTAssertNotEqual(pinnedHandle, 0, "kk_pin_object must return a non-zero handle")
            let retrievedRaw = kk_pinned_get(pinnedHandle)
            XCTAssertEqual(retrievedRaw, rawObj, "kk_pinned_get must return the original object handle")
            let unpinnedRaw = kk_unpin_object(pinnedHandle)
            XCTAssertEqual(unpinnedRaw, rawObj, "kk_unpin_object must return the original object handle")
        }
    }

    /// Pinning an object prevents the GC from collecting it.
    func testPinnedObjectSurvivesGCCollect() {
        withDummyTypeInfo { ti in
            let obj = kk_alloc(16, ti)
            let rawObj = Int(bitPattern: obj)
            let pinnedHandle = kk_pin_object(rawObj)
            kk_gc_collect()
            XCTAssertGreaterThanOrEqual(
                kk_runtime_heap_object_count(), 1,
                "pinned object must not be collected by GC.collect()"
            )
            _ = kk_unpin_object(pinnedHandle)
            kk_gc_collect()
            XCTAssertEqual(kk_runtime_heap_object_count(), 0, "unpinned object must be collectible")
        }
    }

    // MARK: freeze() / isFrozen — kotlin.native.ref legacy immutability

    /// kk_freeze_object / kk_is_frozen — legacy Kotlin/Native immutability API.
    func testFreezeAndIsFrozen() {
        let sentinel = 0xDEADBEEF
        XCTAssertEqual(kk_is_frozen(sentinel), 0, "object must not be frozen before freeze()")
        _ = kk_freeze_object(sentinel)
        XCTAssertEqual(kk_is_frozen(sentinel), 1, "object must be frozen after freeze()")
    }

    /// kk_is_frozen returns 0 for the zero handle.
    func testIsFrozenZeroHandleReturnsFalse() {
        XCTAssertEqual(kk_is_frozen(0), 0)
    }
}
