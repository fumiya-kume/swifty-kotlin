import Foundation

struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
}

struct ActiveFrameRecord {
    let functionID: UInt32
    let frameBase: UnsafeMutableRawPointer?
}

struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

/// Cache key for `kk_kclass_create`.
/// `typeToken` uniquely identifies a `KClass<T>` at runtime, so caching by it
/// alone ensures stable hits across repeated evaluations.
struct KClassCacheKey: Hashable {
    let typeToken: Int
}

struct GCState {
    var heapObjects: [UInt: HeapObjectRecord] = [:]
    var objectPointers: Set<UInt> = []
    var globalRootSlots: Set<UInt> = []
    var frameMaps: [UInt32: [Int32]] = [:]
    var activeFrames: [ActiveFrameRecord] = []
    var coroutineRoots: Set<UInt> = []
    var pinnedObjects: Set<UInt> = []
}

struct MetadataState {
    var kClassBoxCache: [KClassCacheKey: Int] = [:]
    var objectTypeByPointer: [UInt: Int64] = [:]
    var typeParents: [Int64: Set<Int64>] = [:]
    var objectItableMethods: [UInt: [UInt64: Int]] = [:]
    var objectInterfaceSlots: [UInt: [Int64: Int]] = [:]
}

struct FlowState {
    var flowHandles: [UInt: AnyObject] = [:]
    var flowRetainCounts: [UInt: Int] = [:]
}

struct ThreadLocalState {
    var threadLocalBoxes: Set<UInt> = []
    var threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:]
}

struct DelegateState {
    var customDelegateBoxes: [UInt: RuntimeCustomDelegateBox] = [:]
    var callableRefMetadataByValue: [Int: RuntimeCallableRefMetadata] = [:]
}

final class RuntimeStorageBox: @unchecked Sendable {
    private let gcLock = NSLock()
    private let metadataLock = NSLock()
    private let flowLock = NSLock()
    private let threadLocalLock = NSLock()
    private let delegateLock = NSLock()

    private var gcState = GCState()
    private var metadataState = MetadataState()
    private var flowState = FlowState()
    private var threadLocalState = ThreadLocalState()
    private var delegateState = DelegateState()

    let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
    let flowStopSentinelBox = RuntimeStringBox("FLOW_STOP_SENTINEL")

    @discardableResult
    @inline(__always)
    func withGCLock<R>(_ body: (inout GCState) -> R) -> R {
        gcLock.lock()
        defer { gcLock.unlock() }
        return body(&gcState)
    }

    @discardableResult
    @inline(__always)
    func withMetadataLock<R>(_ body: (inout MetadataState) -> R) -> R {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        return body(&metadataState)
    }

    @discardableResult
    @inline(__always)
    func withFlowLock<R>(_ body: (inout FlowState) -> R) -> R {
        flowLock.lock()
        defer { flowLock.unlock() }
        return body(&flowState)
    }

    @discardableResult
    @inline(__always)
    func withThreadLocalLock<R>(_ body: (inout ThreadLocalState) -> R) -> R {
        threadLocalLock.lock()
        defer { threadLocalLock.unlock() }
        return body(&threadLocalState)
    }

    @discardableResult
    @inline(__always)
    func withDelegateLock<R>(_ body: (inout DelegateState) -> R) -> R {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        return body(&delegateState)
    }
}

let runtimeStorage = RuntimeStorageBox()

let kkObjMarkFlag: UInt32 = 1 << 0

private let runtimeGCDefaultTargetHeapBytes = 100 * 1024 * 1024

private final class RuntimeGCTuningState: @unchecked Sendable {
    private let lock = NSLock()
    private var targetHeapBytes = runtimeGCDefaultTargetHeapBytes
    private var targetHeapUtilization = 0.5
    private var maxHeapBytes = max(
        runtimeGCDefaultTargetHeapBytes,
        Int(clamping: ProcessInfo.processInfo.physicalMemory)
    )

    func currentTargetHeapBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return targetHeapBytes
    }

    func currentTargetHeapUtilization() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return targetHeapUtilization
    }

    func currentMaxHeapBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maxHeapBytes
    }
}

private let runtimeGCTuningState = RuntimeGCTuningState()

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
    runtimeStorage.withGCLock { state in
        state.heapObjects[UInt(bitPattern: ptr)] = HeapObjectRecord(
            pointer: ptr,
            byteCount: allocationSize
        )
    }
    return ptr
}

@_cdecl("kk_gc_collect")
public func kk_gc_collect() {
    let threadLocalRoots = runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues
    }
    runtimeStorage.withGCLock { state in
        performMarkAndSweepLocked(state: &state, threadLocalValues: threadLocalRoots)
    }
}

@_cdecl("kk_gc_schedule")
public func kk_gc_schedule() -> Int {
    kk_gc_collect()
    return 0
}

@_cdecl("kk_gc_target_heap_bytes")
public func kk_gc_target_heap_bytes() -> Int {
    runtimeGCTuningState.currentTargetHeapBytes()
}

@_cdecl("kk_gc_target_heap_utilization")
public func kk_gc_target_heap_utilization() -> Double {
    runtimeGCTuningState.currentTargetHeapUtilization()
}

@_cdecl("kk_gc_max_heap_bytes")
public func kk_gc_max_heap_bytes() -> Int {
    runtimeGCTuningState.currentMaxHeapBytes()
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
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.insert(UInt(bitPattern: slot))
    }
}

@_cdecl("kk_unregister_global_root")
public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.remove(UInt(bitPattern: slot))
    }
}

@_cdecl("kk_register_frame_map")
public func kk_register_frame_map(_ functionID: UInt32, _ mapPtr: UnsafeRawPointer?) {
    runtimeStorage.withGCLock { state in
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
    runtimeStorage.withGCLock { state in
        state.activeFrames.append(ActiveFrameRecord(functionID: functionID, frameBase: frameBase))
    }
}

@_cdecl("kk_pop_frame")
public func kk_pop_frame() {
    runtimeStorage.withGCLock { state in
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
    runtimeStorage.withGCLock { state in
        state.coroutineRoots.insert(UInt(bitPattern: value))
    }
}

@_cdecl("kk_unregister_coroutine_root")
public func kk_unregister_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.coroutineRoots.remove(UInt(bitPattern: value))
    }
}

@_cdecl("kk_runtime_heap_object_count")
public func kk_runtime_heap_object_count() -> UInt32 {
    runtimeStorage.withGCLock { state in
        UInt32(state.heapObjects.count)
    }
}

@_cdecl("kk_runtime_force_reset")
public func kk_runtime_force_reset() {
    kk_runtime_reset_gc()
    kk_runtime_reset_metadata()
    kk_runtime_reset_flow()
    kk_runtime_reset_thread_local()
    kk_runtime_reset_delegate()
    runtimeResetDebugState()
}

func kk_runtime_reset_gc() {
    runtimeStorage.withGCLock { state in
        for (_, object) in state.heapObjects {
            object.pointer.deallocate()
        }
        state.heapObjects.removeAll(keepingCapacity: false)
        state.objectPointers.removeAll(keepingCapacity: false)
        state.globalRootSlots.removeAll(keepingCapacity: false)
        state.frameMaps.removeAll(keepingCapacity: false)
        state.activeFrames.removeAll(keepingCapacity: false)
        state.coroutineRoots.removeAll(keepingCapacity: false)
        state.pinnedObjects.removeAll(keepingCapacity: false)
    }
}

func kk_runtime_reset_metadata() {
    runtimeStorage.withMetadataLock { state in
        for (_, kclassRaw) in state.kClassBoxCache {
            if let ptr = UnsafeMutableRawPointer(bitPattern: kclassRaw) {
                Unmanaged<RuntimeKClassBox>.fromOpaque(ptr).release()
            }
        }
        state.kClassBoxCache.removeAll(keepingCapacity: false)
        state.objectTypeByPointer.removeAll(keepingCapacity: false)
        state.typeParents.removeAll(keepingCapacity: false)
        state.objectItableMethods.removeAll(keepingCapacity: false)
        state.objectInterfaceSlots.removeAll(keepingCapacity: false)
    }
    runtimeKClassMetadataRegistry.reset()
    runtimeKConstructorRegistry.reset()
    runtimeKMemberRegistry.reset()
}

func kk_runtime_reset_flow() {
    runtimeStorage.withFlowLock { state in
        state.flowHandles.removeAll(keepingCapacity: false)
        state.flowRetainCounts.removeAll(keepingCapacity: false)
    }
}

func kk_runtime_reset_thread_local() {
    runtimeStorage.withThreadLocalLock { state in
        for threadLocalRaw in state.threadLocalBoxes {
            if let ptr = UnsafeMutableRawPointer(bitPattern: threadLocalRaw) {
                Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
        state.threadLocalBoxes.removeAll(keepingCapacity: false)
        state.threadLocalValues.removeAll(keepingCapacity: false)
    }
}

func kk_runtime_reset_delegate() {
    runtimeStorage.withDelegateLock { state in
        state.customDelegateBoxes.removeAll(keepingCapacity: false)
        state.callableRefMetadataByValue.removeAll(keepingCapacity: false)
    }
}

func performMarkAndSweepLocked(state: inout GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:]) {
    guard !state.heapObjects.isEmpty else {
        return
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(state.heapObjects.count)
    collectRootPointersLocked(state: state, threadLocalValues: threadLocalValues, into: &worklist)

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

func collectRootPointersLocked(state: GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]], into worklist: inout [UnsafeMutableRawPointer]) {
    for slotAddress in state.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee
        else {
            continue
        }
        worklist.append(value)
    }

    for frame in state.activeFrames {
        guard let frameBase = frame.frameBase,
              let offsets = state.frameMaps[frame.functionID]
        else {
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

    for pinned in state.pinnedObjects {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pinned) else {
            continue
        }
        worklist.append(ptr)
    }

    for threadValues in threadLocalValues.values {
        for raw in threadValues.values {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
                continue
            }
            worklist.append(ptr)
        }
    }
}

func appendObjectChildrenLocked(of object: HeapObjectRecord, into worklist: inout [UnsafeMutableRawPointer]) {
    let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self).pointee
    guard let typeInfo = header.typeInfo else {
        return
    }
    let descriptor = typeInfo.pointee
    let fieldCount = Int(descriptor.fieldCount)
    guard fieldCount > 0 else {
        return
    }

    for index in 0 ..< fieldCount {
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


