import Foundation
import Dispatch

public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?

    public init(
        fqName: UnsafePointer<CChar>,
        instanceSize: UInt32,
        fieldCount: UInt32,
        fieldOffsets: UnsafePointer<UInt32>,
        vtableSize: UInt32,
        vtable: UnsafePointer<UnsafeRawPointer>,
        itable: UnsafeRawPointer?,
        gcDescriptor: UnsafeRawPointer?
    ) {
        self.fqName = fqName
        self.instanceSize = instanceSize
        self.fieldCount = fieldCount
        self.fieldOffsets = fieldOffsets
        self.vtableSize = vtableSize
        self.vtable = vtable
        self.itable = itable
        self.gcDescriptor = gcDescriptor
    }
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

private final class RuntimeStringBox {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

private final class RuntimeThrowableBox {
    let message: String

    init(message: String) {
        self.message = message
    }
}

private final class RuntimeContinuationState {
    var functionID: Int64
    var label: Int64
    var completion: Int64
    var spillSlots: [Int64: Int64]

    init(functionID: Int64, label: Int64 = 0, completion: Int64 = 0, spillSlots: [Int64: Int64] = [:]) {
        self.functionID = functionID
        self.label = label
        self.completion = completion
        self.spillSlots = spillSlots
    }
}

private struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
    let typeInfo: UnsafePointer<KTypeInfo>?
    var marked: Bool
}

private struct ActiveFrameRecord {
    let functionID: UInt32
    let frameBase: UnsafeMutableRawPointer?
}

private struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

private enum RuntimeStorage {
    static let lock = NSLock()
    static var heapObjects: [UInt: HeapObjectRecord] = [:]
    static var objectPointers: Set<UInt> = []
    static var globalRootSlots: Set<UInt> = []
    static var frameMaps: [UInt32: [Int32]] = [:]
    static var activeFrames: [ActiveFrameRecord] = []
    static var coroutineRoots: Set<UInt> = []
    static let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
}

@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafeRawPointer?) -> UnsafeMutableRawPointer {
    let allocationSize = Int(max(size, 1))
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: MemoryLayout<UInt64>.alignment)
    ptr.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
    let typeInfoPtr = typeInfo?.assumingMemoryBound(to: KTypeInfo.self)
    RuntimeStorage.lock.lock()
    RuntimeStorage.heapObjects[UInt(bitPattern: ptr)] = HeapObjectRecord(
        pointer: ptr,
        byteCount: allocationSize,
        typeInfo: typeInfoPtr,
        marked: false
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

@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let throwable = RuntimeThrowableBox(message: text)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return ptr
}

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never {
    fatalError(runtimePanicMessage(fromCString: cstr))
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

func runtimePanicMessage(fromCString cstr: UnsafePointer<CChar>) -> String {
    let message = String(cString: cstr)
    return "KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(message)"
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = String(decoding: buffer, as: UTF8.self)
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return opaque
}

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let lhs = extractString(from: a) ?? ""
    let rhs = extractString(from: b) ?? ""
    let box = RuntimeStringBox(lhs + rhs)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return opaque
}

@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    guard let obj else {
        Swift.print("null")
        return
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: obj))
    RuntimeStorage.lock.unlock()
    if !isObjectPointer {
        Swift.print("<object \(obj)>")
        return
    }
    if let stringBox = tryCast(obj, to: RuntimeStringBox.self) {
        Swift.print(stringBox.value)
        return
    }
    if let throwable = tryCast(obj, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.message))")
        return
    }
    Swift.print("<object \(obj)>")
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(RuntimeStorage.coroutineSuspendedBox).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return ptr
}

@_cdecl("kk_coroutine_continuation_new")
public func kk_coroutine_continuation_new(_ functionID: Int) -> Int {
    let state = RuntimeContinuationState(functionID: Int64(functionID))
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(state).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: ptr)
}

@_cdecl("kk_coroutine_state_enter")
public func kk_coroutine_state_enter(_ continuation: Int, _ functionID: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return 0
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    let functionIDValue = Int64(functionID)
    if state.functionID != functionIDValue {
        state.functionID = functionIDValue
        state.label = 0
        state.completion = 0
        state.spillSlots.removeAll(keepingCapacity: false)
    }
    return Int(state.label)
}

@_cdecl("kk_coroutine_state_set_label")
public func kk_coroutine_state_set_label(_ continuation: Int, _ label: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return label
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.label = Int64(label)
    return label
}

@_cdecl("kk_coroutine_state_exit")
public func kk_coroutine_state_exit(_ continuation: Int, _ value: Int) -> Int {
    if let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) {
        RuntimeStorage.lock.lock()
        RuntimeStorage.objectPointers.remove(UInt(bitPattern: continuationPtr))
        RuntimeStorage.lock.unlock()
        Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).release()
    }
    return value
}

@_cdecl("kk_coroutine_state_set_spill")
public func kk_coroutine_state_set_spill(_ continuation: Int, _ slot: Int, _ value: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return value
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.spillSlots[Int64(slot)] = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return 0
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    return Int(state.spillSlots[Int64(slot)] ?? 0)
}

@_cdecl("kk_coroutine_state_set_completion")
public func kk_coroutine_state_set_completion(_ continuation: Int, _ value: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return value
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.completion = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_completion")
public func kk_coroutine_state_get_completion(_ continuation: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return 0
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    return Int(state.completion)
}

private func performMarkAndSweepLocked() {
    guard !RuntimeStorage.heapObjects.isEmpty else {
        return
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(RuntimeStorage.heapObjects.count)
    collectRootPointersLocked(into: &worklist)

    while let current = worklist.popLast() {
        let key = UInt(bitPattern: current)
        guard var object = RuntimeStorage.heapObjects[key], !object.marked else {
            continue
        }
        object.marked = true
        RuntimeStorage.heapObjects[key] = object
        appendObjectChildrenLocked(of: object, into: &worklist)
    }

    var survivors: [UInt: HeapObjectRecord] = [:]
    survivors.reserveCapacity(RuntimeStorage.heapObjects.count)
    for (key, var object) in RuntimeStorage.heapObjects {
        if object.marked {
            object.marked = false
            survivors[key] = object
        } else {
            object.pointer.deallocate()
        }
    }
    RuntimeStorage.heapObjects = survivors
}

private func collectRootPointersLocked(into worklist: inout [UnsafeMutableRawPointer]) {
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

private func appendObjectChildrenLocked(of object: HeapObjectRecord, into worklist: inout [UnsafeMutableRawPointer]) {
    guard let typeInfo = object.typeInfo else {
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

private func resetRuntimeLocked() {
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

private func tryCast<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, to type: T.Type) -> T? {
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let anyObject = unmanaged.takeUnretainedValue()
    return anyObject as? T
}

private func extractString(from ptr: UnsafeMutableRawPointer?) -> String? {
    guard let ptr else {
        return nil
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return nil
    }
    guard let box = tryCast(ptr, to: RuntimeStringBox.self) else {
        return nil
    }
    return box.value
}

public final class KKDispatchContinuation: KKContinuation {
    public let context: UnsafeMutableRawPointer?
    private let callback: (UnsafeMutableRawPointer?) -> Void

    public init(context: UnsafeMutableRawPointer?, callback: @escaping (UnsafeMutableRawPointer?) -> Void) {
        self.context = context
        self.callback = callback
    }

    public func resumeWith(_ result: UnsafeMutableRawPointer?) {
        callback(result)
    }
}

public enum KxMiniRuntime {
    public static func runBlocking(_ block: (@escaping (UnsafeMutableRawPointer?) -> Void) -> Void) {
        let group = DispatchGroup()
        group.enter()
        block { _ in group.leave() }
        group.wait()
    }

    public static func launch(_ block: @escaping () -> Void) {
        DispatchQueue.global().async(execute: block)
    }

    public static func `async`(_ block: @escaping () -> UnsafeMutableRawPointer?) -> KKContinuation {
        KKDispatchContinuation(context: nil) { _ in
            _ = block()
        }
    }

    public static func delay(milliseconds: Int, continuation: KKContinuation) {
        let deadline = DispatchTime.now() + .milliseconds(max(0, milliseconds))
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            continuation.resumeWith(nil)
        }
    }
}
