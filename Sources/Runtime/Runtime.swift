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

private struct KKObjHeader {
    var typeInfo: UnsafePointer<KTypeInfo>?
    var flags: UInt32
    var size: UInt32
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

private typealias KKSuspendEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

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

private final class RuntimeArrayBox {
    var elements: [Int]

    init(length: Int) {
        self.elements = Array(repeating: 0, count: max(0, length))
    }
}

private final class RuntimeIntBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private final class RuntimeBoolBox {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

private final class RuntimeContinuationState {
    var functionID: Int64
    var label: Int64
    var completion: Int64
    var spillSlots: [Int64: Int64]
    private let stateLock = NSLock()
    private let resumeSemaphore = DispatchSemaphore(value: 0)
    private var delayTimers: [ObjectIdentifier: DispatchSourceTimer]

    init(
        functionID: Int64,
        label: Int64 = 0,
        completion: Int64 = 0,
        spillSlots: [Int64: Int64] = [:],
        delayTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
    ) {
        self.functionID = functionID
        self.label = label
        self.completion = completion
        self.spillSlots = spillSlots
        self.delayTimers = delayTimers
    }

    deinit {
        let timers = releaseAllDelayTimers()
        for timer in timers {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    func scheduleDelay(milliseconds: Int) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        let timerID = ObjectIdentifier(timer as AnyObject)
        stateLock.lock()
        delayTimers[timerID] = timer
        stateLock.unlock()

        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler { [weak self] in
            self?.completeDelayTimer(timerID: timerID)
        }
        timer.resume()
    }

    func waitForResumeSignal() {
        resumeSemaphore.wait()
    }

    private func completeDelayTimer(timerID: ObjectIdentifier) {
        stateLock.lock()
        delayTimers.removeValue(forKey: timerID)
        stateLock.unlock()
        resumeSemaphore.signal()
    }

    private func releaseAllDelayTimers() -> [DispatchSourceTimer] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let timers = Array(delayTimers.values)
        delayTimers.removeAll(keepingCapacity: false)
        return timers
    }
}

private final class RuntimeAsyncTask {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var isCompleted = false
    private var result: Int = 0

    func complete(with result: Int) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        self.result = result
        isCompleted = true
        lock.unlock()
        ready.signal()
    }

    func awaitResult() -> Int {
        lock.lock()
        if isCompleted {
            let value = result
            lock.unlock()
            return value
        }
        lock.unlock()
        ready.wait()
        lock.lock()
        let value = result
        lock.unlock()
        return value
    }
}

private struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
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

private let kkObjMarkFlag: UInt32 = 1 << 0

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

@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let throwableInt = runtimeAllocateThrowable(message: text)
    return UnsafeMutableRawPointer(bitPattern: throwableInt) ?? UnsafeMutableRawPointer(bitPattern: 0x1)!
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
    let lhs = extractString(from: normalizeNullableRuntimePointer(a)) ?? ""
    let rhs = extractString(from: normalizeNullableRuntimePointer(b)) ?? ""
    let box = RuntimeStringBox(lhs + rhs)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return opaque
}

@_cdecl("kk_array_new")
public func kk_array_new(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

@_cdecl("kk_array_get")
public func kk_array_get(_ arrayRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    return array.elements[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    array.elements[index] = value
    return value
}

@_cdecl("kk_vararg_spread_concat")
public func kk_vararg_spread_concat(_ pairs: UnsafePointer<Int>, _ pairCount: Int) -> Int {
    var elements: [Int] = []
    var i = 0
    while i < pairCount * 2 {
        let marker = pairs[i]
        let value = pairs[i + 1]
        if marker == -1 {
            if let array = runtimeArrayBox(from: value) {
                elements.append(contentsOf: array.elements)
            }
        } else {
            elements.append(value)
        }
        i += 2
    }
    let result = kk_array_new(elements.count)
    if let box = runtimeArrayBox(from: result) {
        for (idx, elem) in elements.enumerated() {
            box.elements[idx] = elem
        }
    }
    return result
}

@_cdecl("kk_box_int")
public func kk_box_int(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    let box = RuntimeIntBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

@_cdecl("kk_box_bool")
public func kk_box_bool(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    let box = RuntimeBoolBox(value != 0)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

@_cdecl("kk_unbox_int")
public func kk_unbox_int(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: objPointer))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return obj
    }
    if let intBox = tryCast(objPointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    return obj
}

@_cdecl("kk_unbox_bool")
public func kk_unbox_bool(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj != 0 ? 1 : 0
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: objPointer))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return obj != 0 ? 1 : 0
    }
    if let boolBox = tryCast(objPointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return obj != 0 ? 1 : 0
}

@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    let intValue: Int
    if let ptr = obj {
        intValue = Int(bitPattern: ptr)
    } else {
        intValue = 0
    }
    if intValue == runtimeNullSentinelInt {
        Swift.print("null")
        return
    }
    guard let raw = obj else {
        Swift.print(intValue)
        return
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: raw))
    RuntimeStorage.lock.unlock()
    if !isObjectPointer {
        Swift.print(intValue)
        return
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        Swift.print(boolBox.value ? "true" : "false")
        return
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        Swift.print(intBox.value)
        return
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        Swift.print(stringBox.value)
        return
    }
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.message))")
        return
    }
    Swift.print("<object \(raw)>")
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

@_cdecl("kk_kxmini_run_blocking")
public func kk_kxmini_run_blocking(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
}

@_cdecl("kk_kxmini_launch")
public func kk_kxmini_launch(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    KxMiniRuntime.launch {
        _ = runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
    }
    return 0
}

@_cdecl("kk_kxmini_async")
public func kk_kxmini_async(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let task = RuntimeAsyncTask()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())
    KxMiniRuntime.launch {
        let result = runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_kxmini_async_await")
public func kk_kxmini_async_await(_ handle: Int) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()
    return task.awaitResult()
}

@_cdecl("kk_kxmini_delay")
public func kk_kxmini_delay(_ milliseconds: Int, _ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}

private func runtimeContinuationState(from continuation: Int) -> RuntimeContinuationState? {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return nil
    }
    return Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
}

private func suspendEntryPoint(from rawValue: Int) -> KKSuspendEntryPoint? {
    guard rawValue != 0 else {
        return nil
    }
    return unsafeBitCast(rawValue, to: KKSuspendEntryPoint.self)
}

private func runtimeArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeArrayBox.self)
}

private func runtimeAllocateThrowable(message: String) -> Int {
    let throwable = RuntimeThrowableBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: ptr)
}

private func runSuspendEntryLoop(entryPointRaw: Int, functionID: Int) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        return 0
    }

    let continuation = kk_coroutine_continuation_new(functionID)
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var outThrown: Int = 0

    while true {
        outThrown = 0
        let result = entryPoint(continuation, &outThrown)
        if outThrown != 0 {
            _ = kk_coroutine_state_exit(continuation, 0)
            return 0
        }
        if result != suspendedToken {
            return result
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            return 0
        }
        state.waitForResumeSignal()
    }
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
    guard let ptr = normalizeNullableRuntimePointer(ptr) else {
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

private let runtimeNullSentinelInt64 = Int64.min
private let runtimeNullSentinelInt = Int(truncatingIfNeeded: runtimeNullSentinelInt64)

private func normalizeNullableRuntimePointer(_ ptr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let ptr else {
        return nil
    }
    if UInt(bitPattern: ptr) == UInt(bitPattern: runtimeNullSentinelInt) {
        return nil
    }
    return ptr
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
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler {
            continuation.resumeWith(nil)
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
        timer.resume()
    }
}
