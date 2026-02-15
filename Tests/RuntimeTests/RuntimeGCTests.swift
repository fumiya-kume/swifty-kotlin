import XCTest
@testable import Runtime

private struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

final class RuntimeGCTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testGCCollectsUnreachableAllocation() {
        _ = kk_alloc(16, nil)
        XCTAssertEqual(kk_runtime_heap_object_count(), 1)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }

    func testGlobalRootPreventsCollectionUntilCleared() {
        let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
        slot.initialize(to: kk_alloc(16, nil))
        defer {
            slot.deinitialize(count: 1)
            slot.deallocate()
        }

        kk_register_global_root(slot)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 1)

        slot.pointee = nil
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        kk_unregister_global_root(slot)
    }

    func testFrameMapRootsProtectActiveFramePointers() {
        var rootOffset: Int32 = 0
        withUnsafePointer(to: &rootOffset) { offsetPtr in
            var descriptor = FrameMapDescriptorC(rootCount: 1, rootOffsets: offsetPtr)
            withUnsafePointer(to: &descriptor) { descriptorPtr in
                kk_register_frame_map(77, UnsafeRawPointer(descriptorPtr))
            }
        }

        let frameRootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
        frameRootSlot.initialize(to: kk_alloc(8, nil))
        defer {
            frameRootSlot.deinitialize(count: 1)
            frameRootSlot.deallocate()
        }

        kk_push_frame(77, UnsafeMutableRawPointer(frameRootSlot))
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 1)

        frameRootSlot.pointee = nil
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        kk_pop_frame()

        kk_register_frame_map(77, nil)
    }

    func testCoroutineRootRegistrationPreventsCollection() {
        let object = kk_alloc(12, nil)
        kk_register_coroutine_root(object)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 1)

        kk_unregister_coroutine_root(object)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }
}
