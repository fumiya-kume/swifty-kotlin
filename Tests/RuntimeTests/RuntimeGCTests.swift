@testable import Runtime
import Testing

private struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

private struct ObjHeaderProbe {
    let typeInfo: UnsafePointer<KTypeInfo>?
    let flags: UInt32
    let size: UInt32
}

private func withTestTypeInfo(
    fieldOffsets: [UInt32],
    body: (UnsafePointer<KTypeInfo>) -> Void
) {
    let typeName = Array("Test.Type\0".utf8).map(CChar.init)
    let offsetStorage = fieldOffsets.isEmpty ? [UInt32(0)] : fieldOffsets
    var emptyVtableEntry = UnsafeRawPointer(bitPattern: 0x1)!

    typeName.withUnsafeBufferPointer { nameBuffer in
        offsetStorage.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &emptyVtableEntry) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: UInt32(fieldOffsets.count),
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 0,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo, body)
            }
        }
    }
}

private func withDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    withTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
        body(UnsafeRawPointer(typeInfoPtr))
    }
}

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeGCTests {
    @Test func testGCCollectsUnreachableAllocation() {
        withDummyTypeInfo { ti in
            _ = kk_alloc(16, ti)
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func testGlobalRootPreventsCollectionUntilCleared() {
        withDummyTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }

            kk_register_global_root(slot)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            slot.pointee = nil
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            kk_unregister_global_root(slot)
        }
    }

    @Test func testFrameMapRootsProtectActiveFramePointers() {
        var rootOffset: Int32 = 0
        withUnsafePointer(to: &rootOffset) { offsetPtr in
            var descriptor = FrameMapDescriptorC(rootCount: 1, rootOffsets: offsetPtr)
            _ = descriptor.rootCount
            _ = descriptor.rootOffsets
            withUnsafePointer(to: &descriptor) { descriptorPtr in
                kk_register_frame_map(77, UnsafeRawPointer(descriptorPtr))
            }
        }

        withDummyTypeInfo { ti in
            let frameRootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            frameRootSlot.initialize(to: kk_alloc(8, ti))
            defer {
                frameRootSlot.deinitialize(count: 1)
                frameRootSlot.deallocate()
            }

            kk_push_frame(77, UnsafeMutableRawPointer(frameRootSlot))
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            frameRootSlot.pointee = nil
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            kk_pop_frame()

            kk_register_frame_map(77, nil)
        }
    }

    @Test func testCoroutineRootRegistrationPreventsCollection() {
        withDummyTypeInfo { ti in
            let object = kk_alloc(12, ti)
            kk_register_coroutine_root(object)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            kk_unregister_coroutine_root(object)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func testAllocInitializesObjectHeader() {
        withTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
            let object = kk_alloc(32, UnsafeRawPointer(typeInfoPtr))
            let header = object.assumingMemoryBound(to: ObjHeaderProbe.self).pointee
            #expect(header.size == 32)
            #expect(
                UInt(bitPattern: header.typeInfo)
                    == UInt(bitPattern: typeInfoPtr)
            )
            #expect(header.flags == 0)
        }
    }

    @Test func testGCTracesChildReferenceThroughObjectHeaderTypeInfo() {
        let fieldOffset = UInt32(MemoryLayout<ObjHeaderProbe>.stride)
        let parentSize = UInt32(MemoryLayout<ObjHeaderProbe>.stride + MemoryLayout<UnsafeMutableRawPointer?>.stride)

        withTestTypeInfo(fieldOffsets: [fieldOffset]) { typeInfoPtr in
            let parent = kk_alloc(parentSize, UnsafeRawPointer(typeInfoPtr))
            withDummyTypeInfo { childTI in
                let child = kk_alloc(16, childTI)
                let slot = parent.advanced(by: Int(fieldOffset)).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                slot.pointee = child

                let rootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
                rootSlot.initialize(to: parent)
                defer {
                    rootSlot.deinitialize(count: 1)
                    rootSlot.deallocate()
                }

                kk_register_global_root(rootSlot)
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 2)

                rootSlot.pointee = nil
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 0)
                kk_unregister_global_root(rootSlot)
            }
        }
    }

    @Test func testGCRemovesPerObjectDispatchMetadataForSweptHeapObject() {
        withDummyTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: object)
            let objectKey = UInt(bitPattern: object)
            let itableKey = (UInt64(UInt32(2)) << 32) | UInt64(UInt32(3))

            runtimeRegisterObjectType(rawValue: objectRaw, classID: 42)
            _ = kk_object_register_itable_iface(objectRaw, 7, 2)
            _ = kk_object_register_itable_method(objectRaw, 2, 3, 0x1000)
            _ = kk_object_register_vtable_method(objectRaw, 4, 0x2000)
            _ = kk_object_register_equals_override(objectRaw, 0x3000)

            runtimeStorage.withMetadataLock { state in
                #expect(state.objectTypeByPointer[objectKey] == 42)
                #expect(state.objectInterfaceSlots[objectKey]?[7] == 2)
                #expect(state.objectItableMethods[objectKey]?[itableKey] == 0x1000)
                #expect(state.objectVtableMethods[objectKey]?[4] == 0x2000)
                #expect(state.objectEqualsOverrides[objectKey] == 0x3000)
            }

            kk_gc_collect()

            #expect(kk_runtime_heap_object_count() == 0)
            runtimeStorage.withMetadataLock { state in
                #expect(state.objectTypeByPointer[objectKey] == nil)
                #expect(state.objectInterfaceSlots[objectKey] == nil)
                #expect(state.objectItableMethods[objectKey] == nil)
                #expect(state.objectVtableMethods[objectKey] == nil)
                #expect(state.objectEqualsOverrides[objectKey] == nil)
            }
        }
    }
}
