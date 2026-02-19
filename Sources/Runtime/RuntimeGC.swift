import Foundation

internal struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
}

internal struct ActiveFrameRecord {
    let functionID: UInt32
    let frameBase: UnsafeMutableRawPointer?
}

internal struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

internal enum RuntimeStorage {
    static let lock = NSLock()
    static var heapObjects: [UInt: HeapObjectRecord] = [:]
    static var objectPointers: Set<UInt> = []
    static var globalRootSlots: Set<UInt> = []
    static var frameMaps: [UInt32: [Int32]] = [:]
    static var activeFrames: [ActiveFrameRecord] = []
    static var coroutineRoots: Set<UInt> = []
    static let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
}

internal let kkObjMarkFlag: UInt32 = 1 << 0

@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafeRawPointer) -> UnsafeMutableRawPointer {
    let headerSize = MemoryLayout<KKObjHeader>.stride
    let alignment = max(MemoryLayout<KKObjHeader>.alignment, MemoryLayout<UInt64>.alignment)
    let allocationSize = max(Int(size), headerSize)
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: alignment)
    ptr.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
    let typedInfo = typeInfo.assumingMemoryBound(to: KTypeInfo.self)
    ptr.assumingMemoryBound(to: KKObjHeader.self).pointee = KKObjHeader(
        typeInfo: typedInfo,
        flags: 0,
        size: UInt32(allocationSize)
    )
    RuntimeStorage.lock.lock()
    RuntimeStorage.heapObjects[UInt(bitPattern: ptr)] = HeapObjectRecord(
        pointer: ptr,
        byteCount: allocationSize
    )
    RuntimeStorage.lock.unlock()
    return ptr
}

@_cdecl("kk_gc_collect")
public func kk_gc_collect() {
    RuntimeStorage.lock.lock()
    performMarkAndSweepLocked()
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_write_barrier")
public func kk_write_barrier(_ owner: UnsafeMutableRawPointer, _ fieldAddr: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    // Non-moving mark-sweep does not require a write barrier for correctness.
    _ = owner
    _ = fieldAddr
}

@_cdecl("kk_register_global_root")
public func kk_register_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    RuntimeStorage.lock.lock()
    RuntimeStorage.globalRootSlots.insert(UInt(bitPattern: slot))
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_unregister_global_root")
public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    RuntimeStorage.lock.lock()
    RuntimeStorage.globalRootSlots.remove(UInt(bitPattern: slot))
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_register_frame_map")
public func kk_register_frame_map(_ functionID: UInt32, _ mapPtr: UnsafeRawPointer?) {
    RuntimeStorage.lock.lock()
    defer { RuntimeStorage.lock.unlock() }

    guard let mapPtr else {
        RuntimeStorage.frameMaps.removeValue(forKey: functionID)
        return
    }
    let descriptor = mapPtr.assumingMemoryBound(to: FrameMapDescriptorC.self).pointee
    let count = Int(descriptor.rootCount)
    guard count > 0, let offsetsPtr = descriptor.rootOffsets else {
        RuntimeStorage.frameMaps[functionID] = []
        return
    }
    let offsets = Array(UnsafeBufferPointer(start: offsetsPtr, count: count))
    RuntimeStorage.frameMaps[functionID] = offsets
}

@_cdecl("kk_push_frame")
public func kk_push_frame(_ functionID: UInt32, _ frameBase: UnsafeMutableRawPointer?) {
    RuntimeStorage.lock.lock()
    RuntimeStorage.activeFrames.append(ActiveFrameRecord(functionID: functionID, frameBase: frameBase))
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_pop_frame")
public func kk_pop_frame() {
    RuntimeStorage.lock.lock()
    if !RuntimeStorage.activeFrames.isEmpty {
        _ = RuntimeStorage.activeFrames.removeLast()
    }
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_register_coroutine_root")
public func kk_register_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    RuntimeStorage.lock.lock()
    RuntimeStorage.coroutineRoots.insert(UInt(bitPattern: value))
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_unregister_coroutine_root")
public func kk_unregister_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    RuntimeStorage.lock.lock()
    RuntimeStorage.coroutineRoots.remove(UInt(bitPattern: value))
    RuntimeStorage.lock.unlock()
}

@_cdecl("kk_runtime_heap_object_count")
public func kk_runtime_heap_object_count() -> UInt32 {
    RuntimeStorage.lock.lock()
    defer { RuntimeStorage.lock.unlock() }
    return UInt32(RuntimeStorage.heapObjects.count)
}

@_cdecl("kk_runtime_force_reset")
public func kk_runtime_force_reset() {
    RuntimeStorage.lock.lock()
    resetRuntimeLocked()
    RuntimeStorage.lock.unlock()
}

internal func performMarkAndSweepLocked() {
    guard !RuntimeStorage.heapObjects.isEmpty else {
        return
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(RuntimeStorage.heapObjects.count)
    collectRootPointersLocked(into: &worklist)

    while let current = worklist.popLast() {
        let key = UInt(bitPattern: current)
        guard let object = RuntimeStorage.heapObjects[key] else {
            continue
        }
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            continue
        }
        header.pointee.flags |= kkObjMarkFlag
        appendObjectChildrenLocked(of: object, into: &worklist)
    }

    var survivors: [UInt: HeapObjectRecord] = [:]
    survivors.reserveCapacity(RuntimeStorage.heapObjects.count)
    for (key, object) in RuntimeStorage.heapObjects {
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            header.pointee.flags &= ~kkObjMarkFlag
            survivors[key] = object
        } else {
            object.pointer.deallocate()
        }
    }
    RuntimeStorage.heapObjects = survivors
}

internal func collectRootPointersLocked(into worklist: inout [UnsafeMutableRawPointer]) {
    for slotAddress in RuntimeStorage.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee else {
            continue
        }
        worklist.append(value)
    }

    for frame in RuntimeStorage.activeFrames {
        guard let frameBase = frame.frameBase,
              let offsets = RuntimeStorage.frameMaps[frame.functionID] else {
            continue
        }
        for offset in offsets {
            let slot = frameBase.advanced(by: Int(offset)).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            if let value = slot.pointee {
                worklist.append(value)
            }
        }
    }

    for root in RuntimeStorage.coroutineRoots {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: root) else {
            continue
        }
        worklist.append(ptr)
    }
}

internal func appendObjectChildrenLocked(of object: HeapObjectRecord, into worklist: inout [UnsafeMutableRawPointer]) {
    let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self).pointee
    guard let typeInfo = header.typeInfo else {
        return
    }
    let descriptor = typeInfo.pointee
    let fieldCount = Int(descriptor.fieldCount)
    guard fieldCount > 0 else {
        return
    }

    for index in 0..<fieldCount {
        let offset = Int(descriptor.fieldOffsets[index])
        if offset + MemoryLayout<UnsafeMutableRawPointer?>.size > object.byteCount {
            continue
        }
        let fieldSlot = object.pointer.advanced(by: offset).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        if let child = fieldSlot.pointee {
            worklist.append(child)
        }
    }
}

internal func resetRuntimeLocked() {
    for (_, object) in RuntimeStorage.heapObjects {
        object.pointer.deallocate()
    }
    RuntimeStorage.heapObjects.removeAll(keepingCapacity: false)
    RuntimeStorage.objectPointers.removeAll(keepingCapacity: false)
    RuntimeStorage.globalRootSlots.removeAll(keepingCapacity: false)
    RuntimeStorage.frameMaps.removeAll(keepingCapacity: false)
    RuntimeStorage.activeFrames.removeAll(keepingCapacity: false)
    RuntimeStorage.coroutineRoots.removeAll(keepingCapacity: false)
}
