import Dispatch
import Foundation

// MARK: - Kotlin/Native specific APIs (STDLIB-NATIVE-168)

// MARK: - CPointer / COpaquePointer

/// Runtime backing for `kotlinx.cinterop.CPointer<T>`.
///
/// Holds a raw C pointer value. In the KSwiftK ABI, pointer types are
/// represented as boxed `Int` values that carry the machine-word address.
final class RuntimeCPointerBox: @unchecked Sendable {
    let address: UInt
    init(address: UInt) {
        self.address = address
    }
}

/// Runtime backing for `kotlinx.cinterop.COpaquePointer`.
///
/// An untyped C pointer, semantically equivalent to `void *`.
final class RuntimeCOpaquePointerBox: @unchecked Sendable {
    let address: UInt
    init(address: UInt) {
        self.address = address
    }
}

@_cdecl("kk_cpointer_new")
public func kk_cpointer_new(_ address: Int) -> Int {
    registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: address)))
}

@_cdecl("kk_cpointer_address")
public func kk_cpointer_address(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    guard let box = tryCast(ptr, to: RuntimeCPointerBox.self) else {
        return 0
    }
    return Int(bitPattern: box.address)
}

@_cdecl("kk_copaque_pointer_new")
public func kk_copaque_pointer_new(_ address: Int) -> Int {
    registerRuntimeObject(RuntimeCOpaquePointerBox(address: UInt(bitPattern: address)))
}

@_cdecl("kk_copaque_pointer_address")
public func kk_copaque_pointer_address(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    guard let box = tryCast(ptr, to: RuntimeCOpaquePointerBox.self) else {
        return 0
    }
    return Int(bitPattern: box.address)
}

// MARK: - nativeHeap / nativeMemory allocation

/// Tracks allocations made through `nativeHeap.alloc` / `nativeMemory`.
final class RuntimeNativeHeapAllocationBox: @unchecked Sendable {
    let rawPointer: UnsafeMutableRawPointer
    let byteCount: Int

    init(byteCount: Int) {
        precondition(byteCount > 0, "nativeHeap allocation size must be positive")
        self.byteCount = byteCount
        self.rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        self.rawPointer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    }

    deinit {
        rawPointer.deallocate()
    }
}

@_cdecl("kk_native_heap_alloc")
public func kk_native_heap_alloc(_ byteCount: Int) -> Int {
    guard byteCount > 0 else {
        return 0
    }
    return registerRuntimeObject(RuntimeNativeHeapAllocationBox(byteCount: byteCount))
}

@_cdecl("kk_native_heap_free")
public func kk_native_heap_free(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    // Release the box; its deinit frees the underlying C memory.
    Unmanaged<RuntimeNativeHeapAllocationBox>.fromOpaque(ptr).release()
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    return 0
}

@_cdecl("kk_native_alloc_bytes")
public func kk_native_alloc_bytes(_ byteCount: Int) -> Int {
    kk_native_heap_alloc(byteCount)
}

// MARK: - memScoped { } block

/// Tracks allocations tied to a `memScoped` lifetime region.
///
/// On scope exit (`kk_mem_scope_exit`) all allocations registered within
/// the scope are released together.
final class RuntimeMemScopeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var allocations: [UInt] = []

    func register(raw: Int) {
        guard raw != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        allocations.append(UInt(bitPattern: raw))
    }

    func freeAll() {
        lock.lock()
        let keys = allocations
        allocations.removeAll(keepingCapacity: false)
        lock.unlock()

        runtimeStorage.withLock { state in
            for key in keys {
                guard state.objectPointers.remove(key) != nil,
                      let ptr = UnsafeMutableRawPointer(bitPattern: key)
                else {
                    continue
                }
                Unmanaged<RuntimeNativeHeapAllocationBox>.fromOpaque(ptr).release()
            }
        }
    }
}

@_cdecl("kk_mem_scope_enter")
public func kk_mem_scope_enter() -> Int {
    registerRuntimeObject(RuntimeMemScopeBox())
}

@_cdecl("kk_mem_scope_alloc")
public func kk_mem_scope_alloc(_ scopeHandle: Int, _ byteCount: Int) -> Int {
    guard byteCount > 0 else {
        return 0
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mem_scope_alloc received invalid scope handle")
    }
    let box = Unmanaged<RuntimeMemScopeBox>.fromOpaque(ptr).takeUnretainedValue()
    let allocation = RuntimeNativeHeapAllocationBox(byteCount: byteCount)
    let raw = registerRuntimeObject(allocation)
    box.register(raw: raw)
    return raw
}

@_cdecl("kk_mem_scope_exit")
public func kk_mem_scope_exit(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let unmanaged = Unmanaged<RuntimeMemScopeBox>.fromOpaque(ptr)
    let box = unmanaged.takeUnretainedValue()
    box.freeAll()
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    unmanaged.release()
    return 0
}

// MARK: - Pinned<T>

/// Runtime backing for `kotlin.native.ref.Pinned<T>`.
///
/// Pinning prevents the GC from moving (or collecting) a heap object while
/// the pin is held.  In the KSwiftK stop-the-world mark-sweep GC objects
/// are never moved, so pinning is implemented as a simple reference hold.
///
/// ABI-005: `unpinned` guards against double-unpin UB.  Once `kk_unpin_object`
/// executes the release path, the flag is set to `true`; any subsequent call
/// with the same handle is a no-op.
final class RuntimePinnedBox: @unchecked Sendable {
    let objectRaw: Int
    private let lock = NSLock()
    private var _unpinned = false

    init(objectRaw: Int) {
        self.objectRaw = objectRaw
    }

    /// Atomically transitions the box from pinned → unpinned.
    /// Returns `true` on the first call (caller must do the release);
    /// returns `false` on any subsequent call (no-op).
    func tryUnpin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_unpinned else { return false }
        _unpinned = true
        return true
    }
}

@_cdecl("kk_pin_object")
public func kk_pin_object(_ objectRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    // Retain a reference so the GC cannot collect it.
    if let ptr = UnsafeMutableRawPointer(bitPattern: objectRaw) {
        let isManaged = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isManaged {
            _ = Unmanaged<AnyObject>.fromOpaque(ptr).retain()
        }
    }
    return registerRuntimeObject(RuntimePinnedBox(objectRaw: objectRaw))
}

@_cdecl("kk_unpin_object")
public func kk_unpin_object(_ pinnedHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pinnedHandle) else {
        return 0
    }
    // ABI-005: guard is not registered at all → silently no-op.
    let isKnown = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isKnown else {
        return 0
    }
    guard let box = tryCast(ptr, to: RuntimePinnedBox.self) else {
        return 0
    }
    // ABI-005: idempotency guard — second unpin on same handle is a no-op.
    guard box.tryUnpin() else {
        return box.objectRaw
    }
    let unmanaged = Unmanaged<RuntimePinnedBox>.fromOpaque(ptr)
    // Release the extra retain we added in kk_pin_object.
    if let objPtr = UnsafeMutableRawPointer(bitPattern: box.objectRaw) {
        let isManaged = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPtr))
        }
        if isManaged {
            Unmanaged<AnyObject>.fromOpaque(objPtr).release()
        }
    }
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    unmanaged.release()
    return box.objectRaw
}

@_cdecl("kk_pinned_get")
public func kk_pinned_get(_ pinnedHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pinnedHandle) else {
        return 0
    }
    guard let box = tryCast(ptr, to: RuntimePinnedBox.self) else {
        return 0
    }
    return box.objectRaw
}

// MARK: - freeze() / isFrozen (Kotlin/Native legacy immutability)

/// ABI-004: Protocol adopted by runtime boxes that store child object handles.
///
/// `kk_freeze_object` uses BFS over all reachable children so that freezing a
/// root object also freezes every transitively-reachable ref field.
/// Cycle detection is handled by the visited set maintained in the registry.
protocol RuntimeChildReferenceProviding {
    /// Return all `Int` handles that this box treats as direct child object refs.
    /// Only handles that are non-zero and registered in `objectPointers` are
    /// meaningful; `freeze` will skip all others.
    var childRefs: [Int] { get }
}

private let runtimeFrozenSet = RuntimeFrozenRegistry()

private final class RuntimeFrozenRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var frozen: Set<UInt> = []

    /// ABI-004: Freeze `root` and every transitively-reachable object.
    ///
    /// BFS traversal via `RuntimeChildReferenceProviding.childRefs`.
    /// A per-call visited set prevents infinite loops on cyclic graphs.
    func freezeRecursive(_ root: Int) {
        guard root != 0 else { return }
        var visited: Set<UInt> = []
        var queue: [Int] = [root]
        while !queue.isEmpty {
            let raw = queue.removeFirst()
            guard raw != 0 else { continue }
            let key = UInt(bitPattern: raw)
            guard visited.insert(key).inserted else { continue }
            lock.lock()
            frozen.insert(key)
            lock.unlock()
            // Collect children only for registered objectPointer boxes.
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { continue }
            let isRegistered = runtimeStorage.withLock { state in
                state.objectPointers.contains(UInt(bitPattern: ptr))
            }
            guard isRegistered else { continue }
            let anyObject = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
            if let provider = anyObject as? RuntimeChildReferenceProviding {
                for child in provider.childRefs where child != 0 {
                    let childKey = UInt(bitPattern: child)
                    if !visited.contains(childKey) {
                        queue.append(child)
                    }
                }
            }
        }
    }

    func isFrozen(_ raw: Int) -> Bool {
        guard raw != 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        return frozen.contains(UInt(bitPattern: raw))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        frozen.removeAll(keepingCapacity: false)
    }
}

@_cdecl("kk_freeze_object")
public func kk_freeze_object(_ objectRaw: Int) -> Int {
    // ABI-004: recursive freeze — traverses all reachable ref fields.
    runtimeFrozenSet.freezeRecursive(objectRaw)
    return objectRaw
}

@_cdecl("kk_is_frozen")
public func kk_is_frozen(_ objectRaw: Int) -> Int {
    runtimeFrozenSet.isFrozen(objectRaw) ? 1 : 0
}

// MARK: - Worker API

/// Runtime backing for `kotlin.native.concurrent.Worker`.
///
/// Each Worker owns a dedicated serial `DispatchQueue`.  Jobs submitted via
/// `execute` are run in FIFO order on that queue.  `requestTermination` drains
/// the queue and prevents new work from being submitted.
final class RuntimeWorkerBox: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    let name: String
    private var terminated = false
    private var pendingJobs: Int = 0

    init(name: String) {
        self.name = name
        self.queue = DispatchQueue(label: "kswiftk.worker.\(name)", qos: .userInitiated)
    }

    /// Submit a closure to the worker. Returns false if the worker has been terminated.
    @discardableResult
    func execute(_ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return false
        }
        pendingJobs += 1
        lock.unlock()

        queue.async { [weak self] in
            work()
            self?.lock.lock()
            self?.pendingJobs -= 1
            self?.lock.unlock()
        }
        return true
    }

    /// Request termination of the worker.  If `processScheduled` is true, drain
    /// remaining jobs before terminating; otherwise abandon pending jobs.
    func requestTermination(processScheduled: Bool) {
        lock.lock()
        terminated = true
        lock.unlock()

        if processScheduled {
            // Drain by submitting a barrier work item and waiting for it.
            let group = DispatchGroup()
            group.enter()
            queue.async {
                group.leave()
            }
            group.wait()
        }
    }

    var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    /// Schedule a closure on the worker's serial queue at the given deadline.
    /// Returns false if the worker is already terminated.
    @discardableResult
    func executeAfter(deadline: DispatchTime, _ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return false
        }
        pendingJobs += 1
        lock.unlock()

        queue.asyncAfter(deadline: deadline) { [weak self] in
            work()
            self?.lock.lock()
            self?.pendingJobs -= 1
            self?.lock.unlock()
        }
        return true
    }
}

@_cdecl("kk_worker_new")
public func kk_worker_new(_ nameRaw: Int) -> Int {
    let name: String
    if let nameStr = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) {
        name = nameStr
    } else {
        name = "worker-\(UInt32.random(in: 0...UInt32.max))"
    }
    return registerRuntimeObject(RuntimeWorkerBox(name: name))
}

@_cdecl("kk_worker_execute")
public func kk_worker_execute(_ workerHandle: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_worker_execute received invalid worker handle")
    }
    let worker = Unmanaged<RuntimeWorkerBox>.fromOpaque(ptr).takeUnretainedValue()
    guard fnPtr != 0 else {
        return 0
    }
    typealias WorkFn = @convention(c) (Int) -> Int
    let fn = unsafeBitCast(UnsafeRawPointer(bitPattern: fnPtr)!, to: WorkFn.self)
    let capturedClosureRaw = closureRaw
    let submitted = worker.execute {
        _ = fn(capturedClosureRaw)
    }
    return submitted ? 1 : 0
}

@_cdecl("kk_worker_request_termination")
public func kk_worker_request_termination(_ workerHandle: Int, _ processScheduledRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        return 0
    }
    let worker = Unmanaged<RuntimeWorkerBox>.fromOpaque(ptr).takeUnretainedValue()
    worker.requestTermination(processScheduled: processScheduledRaw != 0)
    return 0
}

@_cdecl("kk_worker_is_terminated")
public func kk_worker_is_terminated(_ workerHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        return 1
    }
    guard let worker = tryCast(ptr, to: RuntimeWorkerBox.self) else {
        return 1
    }
    return worker.isTerminated ? 1 : 0
}

@_cdecl("kk_worker_name")
public func kk_worker_name(_ workerHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        return 0
    }
    guard let worker = tryCast(ptr, to: RuntimeWorkerBox.self) else {
        return 0
    }
    return registerRuntimeObject(RuntimeStringBox(worker.name))
}

// MARK: - @CName annotation (C interop export name)

/// Registry for functions exported under a C-compatible external name via `@CName`.
private final class RuntimeCNameRegistry: @unchecked Sendable {
    private let lock = NSLock()
    // Maps externName -> function pointer (as Int)
    private var entries: [String: Int] = [:]

    func register(externName: String, fnPtr: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[externName] = fnPtr
    }

    func lookup(externName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[externName] ?? 0
    }

    func allNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.keys)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: false)
    }
}

private let runtimeCNameRegistry = RuntimeCNameRegistry()

@_cdecl("kk_cname_register")
public func kk_cname_register(_ externNameRaw: Int, _ fnPtr: Int) -> Int {
    guard let namePtr = UnsafeMutableRawPointer(bitPattern: externNameRaw),
          let name = extractString(from: namePtr)
    else {
        return 0
    }
    runtimeCNameRegistry.register(externName: name, fnPtr: fnPtr)
    return 0
}

@_cdecl("kk_cname_lookup")
public func kk_cname_lookup(_ externNameRaw: Int) -> Int {
    guard let namePtr = UnsafeMutableRawPointer(bitPattern: externNameRaw),
          let name = extractString(from: namePtr)
    else {
        return 0
    }
    return runtimeCNameRegistry.lookup(externName: name)
}
