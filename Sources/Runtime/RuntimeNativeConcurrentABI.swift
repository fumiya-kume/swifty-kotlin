import Dispatch
import Foundation

// MARK: - Native Concurrent ABI (STDLIB-NATIVE-CONCURRENT-ABI-001..006)
//
// Implements the six runtime entry-points required by the Kotlin/Native
// concurrent standard library:
//
//   ABI-001  Worker.id              — kk_worker_id
//   ABI-002  Future<T>              — kk_future_new / kk_future_complete /
//                                     kk_future_result / kk_future_consume /
//                                     kk_future_is_ready
//   ABI-003  TransferMode           — kk_transfer_object  (SAFE freezes; UNSAFE is pass-through)
//   ABI-004  FreezableAtomicReference<T> — kk_freezable_atomic_ref_create / _load / _store / _is_frozen
//   ABI-005  @SharedImmutable       — kk_shared_immutable_init
//   ABI-006  Worker.executeAfter    — kk_worker_execute_after
//
// Deferred / known limitations
// ----------------------------
//   • TransferMode SAFE: full cycle-detection DFS over the managed object graph
//     is not yet implemented.  The current implementation freezes the root
//     object (consistent with Kotlin/Native semantics) but does not recursively
//     walk reachable references.  A future pass can add that once the type-info
//     system exposes field offsets.
//   • Future<T> blocking result(): the current kk_future_result performs a
//     spin-wait with Thread.sleep to avoid importing Dispatch semaphores into
//     hot paths.  A later revision should use DispatchSemaphore for efficiency.

// ---------------------------------------------------------------------------
// MARK: - ABI-001  Worker.id
// ---------------------------------------------------------------------------

/// Global monotonic counter for Worker IDs.
private let workerIDCounter = WorkerIDCounter()

private final class WorkerIDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Int = 1

    func nextID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = next
        next += 1
        return id
    }
}

/// Per-worker ID registry.  Maps the raw pointer address of a `RuntimeWorkerBox`
/// to its assigned monotonic ID so that repeated calls return a stable value.
private let workerIDRegistry = WorkerIDRegistry()

private final class WorkerIDRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [UInt: Int] = [:]

    func id(for address: UInt) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = table[address] {
            return existing
        }
        let newID = workerIDCounter.nextID()
        table[address] = newID
        return newID
    }

}

/// Returns the monotonic integer ID for a Worker.
///
/// - Parameter workerHandle: opaque handle produced by `kk_worker_new`.
/// - Returns: A positive integer (≥ 1) that is stable across calls, or −1 for an invalid handle.
@_cdecl("kk_worker_id")
public func kk_worker_id(_ workerHandle: Int) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle)
    else {
        return -1
    }
    // Confirm the handle actually points to a RuntimeWorkerBox.
    guard tryCast(ptr, to: RuntimeWorkerBox.self) != nil else {
        return -1
    }
    return workerIDRegistry.id(for: UInt(bitPattern: ptr))
}

// ---------------------------------------------------------------------------
// MARK: - ABI-002  Future<T>
// ---------------------------------------------------------------------------

/// Runtime backing for `kotlin.native.concurrent.Future<T>`.
///
/// A Future is a single-assignment promise: one producer calls `complete`,
/// after which any number of consumers may call `result` (blocking until ready)
/// or `consume` (one-shot retrieval that nulls out the stored value).
final class RuntimeFutureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _resultRaw: Int = 0
    private var _ready: Bool = false
    private var _consumed: Bool = false

    // Spin-wait with sleep to block callers of result() until a value arrives.
    // The sleep interval is intentionally short (1 ms) so tests remain fast.
    func blockUntilReady(timeoutNs: Int = 5_000_000_000) {
        let deadline = DispatchTime.now() + .nanoseconds(timeoutNs)
        while true {
            lock.lock()
            if _ready {
                lock.unlock()
                return
            }
            lock.unlock()
            if DispatchTime.now() > deadline {
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func complete(valueRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !_ready else { return } // single-assignment
        _resultRaw = valueRaw
        _ready = true
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _ready
    }

    /// Non-consuming read.  Blocks until a value is available.
    func result() -> Int {
        blockUntilReady()
        lock.lock()
        defer { lock.unlock() }
        return _ready ? _resultRaw : 0
    }

    /// One-shot retrieval.  Returns the value and zeroes the stored reference.
    func consume() -> Int {
        blockUntilReady()
        lock.lock()
        defer { lock.unlock() }
        guard _ready, !_consumed else { return 0 }
        _consumed = true
        let v = _resultRaw
        _resultRaw = 0
        return v
    }
}

/// Allocate a new, unresolved Future.
@_cdecl("kk_future_new")
public func kk_future_new() -> Int {
    return registerRuntimeObject(RuntimeFutureBox())
}

/// Resolve the Future with `valueRaw`.  Must be called exactly once.
@_cdecl("kk_future_complete")
public func kk_future_complete(_ futureHandle: Int, _ valueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    box.complete(valueRaw: valueRaw)
    return 0
}

/// Returns 1 if the Future has been resolved, 0 otherwise.
@_cdecl("kk_future_is_ready")
public func kk_future_is_ready(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.isReady ? 1 : 0
}

/// Blocking, non-consuming read of the resolved value.
@_cdecl("kk_future_result")
public func kk_future_result(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.result()
}

/// Blocking, one-shot consume.  Second call returns 0.
@_cdecl("kk_future_consume")
public func kk_future_consume(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.consume()
}

// ---------------------------------------------------------------------------
// MARK: - ABI-003  TransferMode
// ---------------------------------------------------------------------------

// TransferMode raw values (mirrors Kotlin/Native enum ordinal):
//   SAFE   = 0  — freeze the object before transfer; enforce immutability
//   UNSAFE = 1  — skip freeze; caller takes responsibility for thread safety

/// Transfer `objectRaw` to another thread under the specified `TransferMode`.
///
/// SAFE mode: freezes the object so it becomes safely shareable.
/// UNSAFE mode: passes the handle through without modification.
///
/// - Returns: the original `objectRaw` handle, or 0 for a null handle.
@_cdecl("kk_transfer_object")
public func kk_transfer_object(_ objectRaw: Int, _ modeRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    if modeRaw == 0 {
        // SAFE: freeze before handing off.
        kk_freeze_object(objectRaw)
    }
    // UNSAFE: pass through — caller is responsible for safety.
    return objectRaw
}

// ---------------------------------------------------------------------------
// MARK: - ABI-004  FreezableAtomicReference<T>
// ---------------------------------------------------------------------------

/// Runtime backing for `kotlin.native.concurrent.FreezableAtomicReference<T>`.
///
/// A reference cell that may be written at most once after which it is
/// permanently frozen.  Subsequent stores with a *different* value are
/// rejected (return 0); stores with the same value are idempotent (return 1).
final class RuntimeFreezableAtomicRefBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _valueRaw: Int
    private var _frozen: Bool = false

    init(initial: Int) {
        _valueRaw = initial
    }

    var valueRaw: Int {
        lock.lock()
        defer { lock.unlock() }
        return _valueRaw
    }

    var isFrozen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _frozen
    }

    /// Store a new value.
    /// - Returns: 1 on success, 0 if the cell is frozen with a different value.
    func store(_ newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if _frozen {
            // Idempotent if same value; reject otherwise.
            return _valueRaw == newValue ? 1 : 0
        }
        _valueRaw = newValue
        _frozen = true
        return 1
    }

    func compareAndSet(expected: Int, newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard _valueRaw == expected else { return 0 }
        if _frozen && _valueRaw != newValue {
            return 0
        }
        _valueRaw = newValue
        _frozen = true
        return 1
    }

    func compareAndSwap(expected: Int, newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let oldValue = _valueRaw
        if oldValue == expected && (!_frozen || oldValue == newValue) {
            _valueRaw = newValue
            _frozen = true
        }
        return oldValue
    }
}

@_cdecl("kk_freezable_atomic_ref_create")
public func kk_freezable_atomic_ref_create(_ initialRaw: Int) -> Int {
    return registerRuntimeObject(RuntimeFreezableAtomicRefBox(initial: initialRaw))
}

@_cdecl("kk_freezable_atomic_ref_load")
public func kk_freezable_atomic_ref_load(_ refHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: refHandle),
          let box = tryCast(ptr, to: RuntimeFreezableAtomicRefBox.self)
    else {
        return 0
    }
    return box.valueRaw
}

/// Store a value into the freezable reference.
/// - Returns: 1 on success, 0 if the cell is already frozen with a different value.
@_cdecl("kk_freezable_atomic_ref_store")
public func kk_freezable_atomic_ref_store(_ refHandle: Int, _ valueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: refHandle),
          let box = tryCast(ptr, to: RuntimeFreezableAtomicRefBox.self)
    else {
        return 0
    }
    return box.store(valueRaw)
}

@_cdecl("kk_freezable_atomic_ref_compareAndSet")
public func kk_freezable_atomic_ref_compareAndSet(_ refHandle: Int, _ expectedRaw: Int, _ newRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: refHandle),
          let box = tryCast(ptr, to: RuntimeFreezableAtomicRefBox.self)
    else {
        return 0
    }
    return box.compareAndSet(expected: expectedRaw, newValue: newRaw)
}

@_cdecl("kk_freezable_atomic_ref_compareAndSwap")
public func kk_freezable_atomic_ref_compareAndSwap(_ refHandle: Int, _ expectedRaw: Int, _ newRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: refHandle),
          let box = tryCast(ptr, to: RuntimeFreezableAtomicRefBox.self)
    else {
        return 0
    }
    return box.compareAndSwap(expected: expectedRaw, newValue: newRaw)
}

/// Returns 1 if the reference has been frozen (i.e. a value has been published), 0 otherwise.
@_cdecl("kk_freezable_atomic_ref_is_frozen")
public func kk_freezable_atomic_ref_is_frozen(_ refHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: refHandle),
          let box = tryCast(ptr, to: RuntimeFreezableAtomicRefBox.self)
    else {
        return 0
    }
    return box.isFrozen ? 1 : 0
}

// ---------------------------------------------------------------------------
// MARK: - ABI-005  @SharedImmutable
// ---------------------------------------------------------------------------

/// Initializer lowering hook for `@SharedImmutable` annotated globals.
///
/// Called immediately after the initializer of a `@SharedImmutable` property
/// completes.  Freezes the object so that all subsequent cross-thread reads
/// observe immutable data.
///
/// - Returns: the same `objectRaw` handle (pass-through).
@_cdecl("kk_shared_immutable_init")
public func kk_shared_immutable_init(_ objectRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    kk_freeze_object(objectRaw)
    return objectRaw
}

// ---------------------------------------------------------------------------
// MARK: - ABI-006  Worker.executeAfter(delayNs, op)
// ---------------------------------------------------------------------------

/// Schedule a closure to run on a Worker after `delayNs` nanoseconds.
///
/// Uses `DispatchQueue.asyncAfter` on the Worker's underlying serial queue.
/// The closure is represented by the same `(fnPtr, closureRaw)` ABI used by
/// `kk_worker_execute`.
///
/// - Parameters:
///   - workerHandle: handle produced by `kk_worker_new`.
///   - delayNs:      delay in nanoseconds (0 means "as soon as possible").
///   - fnPtr:        C function pointer `(Int) -> Int` for the closure body.
///   - closureRaw:   opaque closure capture handle passed to `fnPtr`.
/// - Returns: 1 if scheduled, 0 if the worker is terminated or `fnPtr` is null.
@_cdecl("kk_worker_execute_after")
public func kk_worker_execute_after(
    _ workerHandle: Int,
    _ delayNs: Int,
    _ fnPtr: Int,
    _ closureRaw: Int
) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    guard !worker.isTerminated else {
        return 0
    }
    guard fnPtr != 0 else {
        return 0
    }
    typealias WorkFn = @convention(c) (Int) -> Int
    let fn = unsafeBitCast(UnsafeRawPointer(bitPattern: fnPtr)!, to: WorkFn.self)
    let captured = closureRaw
    let deadline: DispatchTime = delayNs > 0
        ? DispatchTime.now() + .nanoseconds(delayNs)
        : .now()
    let submitted = worker.executeAfter(deadline: deadline) {
        _ = fn(captured)
    }
    return submitted ? 1 : 0
}
