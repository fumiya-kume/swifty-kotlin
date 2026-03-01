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

internal struct RuntimeStorageState {
    var heapObjects: [UInt: HeapObjectRecord] = [:]
    var objectPointers: Set<UInt> = []
    var globalRootSlots: Set<UInt> = []
    var frameMaps: [UInt32: [Int32]] = [:]
    var activeFrames: [ActiveFrameRecord] = []
    var coroutineRoots: Set<UInt> = []
}

internal final class RuntimeStorageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state = RuntimeStorageState()
    let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")

    @discardableResult
    @inline(__always)
    func withLock<R>(_ body: (inout RuntimeStorageState) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

internal let runtimeStorage = RuntimeStorageBox()

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
    runtimeStorage.withLock { state in
        state.heapObjects[UInt(bitPattern: ptr)] = HeapObjectRecord(
            pointer: ptr,
            byteCount: allocationSize
        )
    }
    return ptr
}

@_cdecl("kk_gc_collect")
public func kk_gc_collect() {
    runtimeStorage.withLock { state in
        performMarkAndSweepLocked(state: &state)
    }
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
    runtimeStorage.withLock { state in
        state.globalRootSlots.insert(UInt(bitPattern: slot))
    }
}

@_cdecl("kk_unregister_global_root")
public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withLock { state in
        state.globalRootSlots.remove(UInt(bitPattern: slot))
    }
}

@_cdecl("kk_register_frame_map")
public func kk_register_frame_map(_ functionID: UInt32, _ mapPtr: UnsafeRawPointer?) {
    runtimeStorage.withLock { state in
        guard let mapPtr else {
            state.frameMaps.removeValue(forKey: functionID)
            return
        }
        let descriptor = mapPtr.assumingMemoryBound(to: FrameMapDescriptorC.self).pointee
        let count = Int(descriptor.rootCount)
        guard count > 0, let offsetsPtr = descriptor.rootOffsets else {
            state.frameMaps[functionID] = []
            return
        }
        let offsets = Array(UnsafeBufferPointer(start: offsetsPtr, count: count))
        state.frameMaps[functionID] = offsets
    }
}

@_cdecl("kk_push_frame")
public func kk_push_frame(_ functionID: UInt32, _ frameBase: UnsafeMutableRawPointer?) {
    runtimeStorage.withLock { state in
        state.activeFrames.append(ActiveFrameRecord(functionID: functionID, frameBase: frameBase))
    }
}

@_cdecl("kk_pop_frame")
public func kk_pop_frame() {
    runtimeStorage.withLock { state in
        if !state.activeFrames.isEmpty {
            _ = state.activeFrames.removeLast()
        }
    }
}

@_cdecl("kk_register_coroutine_root")
public func kk_register_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    runtimeStorage.withLock { state in
        state.coroutineRoots.insert(UInt(bitPattern: value))
    }
}

@_cdecl("kk_unregister_coroutine_root")
public func kk_unregister_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    runtimeStorage.withLock { state in
        state.coroutineRoots.remove(UInt(bitPattern: value))
    }
}

@_cdecl("kk_runtime_heap_object_count")
public func kk_runtime_heap_object_count() -> UInt32 {
    runtimeStorage.withLock { state in
        UInt32(state.heapObjects.count)
    }
}

@_cdecl("kk_runtime_force_reset")
public func kk_runtime_force_reset() {
    runtimeStorage.withLock { state in
        resetRuntimeLocked(state: &state)
    }
}

internal func performMarkAndSweepLocked(state: inout RuntimeStorageState) {
    guard !state.heapObjects.isEmpty else {
        return
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(state.heapObjects.count)
    collectRootPointersLocked(state: state, into: &worklist)

    while let current = worklist.popLast() {
        let key = UInt(bitPattern: current)
        guard let object = state.heapObjects[key] else {
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
    survivors.reserveCapacity(state.heapObjects.count)
    for (key, object) in state.heapObjects {
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            header.pointee.flags &= ~kkObjMarkFlag
            survivors[key] = object
        } else {
            object.pointer.deallocate()
        }
    }
    state.heapObjects = survivors
}

internal func collectRootPointersLocked(state: RuntimeStorageState, into worklist: inout [UnsafeMutableRawPointer]) {
    for slotAddress in state.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee else {
            continue
        }
        worklist.append(value)
    }

    for frame in state.activeFrames {
        guard let frameBase = frame.frameBase,
              let offsets = state.frameMaps[frame.functionID] else {
            continue
        }
        for offset in offsets {
            let slot = frameBase.advanced(by: Int(offset)).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            if let value = slot.pointee {
                worklist.append(value)
            }
        }
    }

    for root in state.coroutineRoots {
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

internal func resetRuntimeLocked(state: inout RuntimeStorageState) {
    for (_, object) in state.heapObjects {
        object.pointer.deallocate()
    }
    state.heapObjects.removeAll(keepingCapacity: false)
    state.objectPointers.removeAll(keepingCapacity: false)
    state.globalRootSlots.removeAll(keepingCapacity: false)
    state.frameMaps.removeAll(keepingCapacity: false)
    state.activeFrames.removeAll(keepingCapacity: false)
    state.coroutineRoots.removeAll(keepingCapacity: false)
}
