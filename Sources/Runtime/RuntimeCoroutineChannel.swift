import Dispatch
import Foundation

// Channel runtime (CORO-001) and Channel iterator (CORO-075).
//
// Split out from `RuntimeCoroutine.swift`.

// MARK: - Channel Runtime (CORO-001)

/// Out-of-band status codes returned by channel operations.
/// The actual payload (when present) is written to an `outValue` pointer on receive,
/// matching the status+out-pointer pattern used by `kk_coroutine_check_cancellation`.
enum ChannelOperationStatus: Int {
    case success = 0
    case closed = 1
    case cancelled = 2
    case failed = 3
}

let kChannelResultSuccess: Int = ChannelOperationStatus.success.rawValue
let kChannelResultClosed: Int = ChannelOperationStatus.closed.rawValue
let kChannelResultCancelled: Int = ChannelOperationStatus.cancelled.rawValue
let kChannelResultFailed: Int = ChannelOperationStatus.failed.rawValue

/// Buffer overflow strategies for Channel send operations (CORO-001)
enum ChannelBufferOverflow {
    /// Suspend the sender when buffer is full (default Kotlin behavior)
    case suspend
    /// Drop the oldest element in buffer to make room
    case dropOldest
    /// Drop the element being sent
    case dropLatest
}

/// Mutable box for a suspended sender so receivers can mark delivery before
/// resuming the continuation.  Using a class (reference type) ensures the
/// `delivered` flag set under the channel lock is visible to the sender
/// after it re-acquires the lock post-wakeup.
final class SuspendedSender: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    let value: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?

    /// Set to `true` (under the channel lock) when the sender's value is
    /// delivered to a receiver. The sender checks this after waking to distinguish a
    /// successful delivery from a close-induced wakeup.
    var delivered: Bool = false
    /// Set to `true` (under the channel lock) when the sender is woken due to
    /// coroutine cancellation. Distinct from close-induced wakeup.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int, value: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
        self.value = value
    }
}

/// Mutable box for a suspended receiver so senders / close can mark the
/// wakeup reason before resuming the continuation. Mirrors `SuspendedSender`.
final class SuspendedReceiver: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?
    /// The value deposited by a sender. `nil` means woken by close or cancel.
    var result: Int?
    /// Set to `true` when woken due to coroutine cancellation.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
    }
}

/// Channel with proper Kotlin suspend semantics:
///   - **Rendezvous** (`capacity == 0`): every `send` suspends until a matching
///     `receive` and vice-versa.
///   - **Buffered** (`capacity > 0`): `send` suspends (backpressure) when the
///     buffer is full; `receive` suspends when the buffer is empty.
///   - **`close()`**: marks the channel as closed.  Pending senders are woken
///     and return the closed-send sentinel.  Pending receivers drain the
///     remaining buffer, then return the closed sentinel.  Returns `true` the
///     first time (Kotlin semantics), `false` if already closed.
///   - **Cancellation**: `send` and `receive` check the caller's continuation
///     for cancellation before suspending, and suspended waiters can be removed
///     via `cancelAllWaiters()` (cooperatively from the coroutine runtime).
final class RuntimeChannelHandle: @unchecked Sendable {
    private let lock = NSLock()
    // NOTE: `buffer`, `senderQueue`, and `receiverQueue` use `Array` with
    // `removeFirst()` which is O(n) due to element shifting.  For the current
    // use (moderate queue depths), this is acceptable.  If channels become a
    // hot-path bottleneck, replace these with a circular buffer / Deque for
    // O(1) dequeue.  (See also: Swift Collections `Deque` type.)
    private var buffer: [Int] = []
    let capacity: Int
    private(set) var closed = false
    private let bufferOverflow: ChannelBufferOverflow

    // Waiting-sender queue: each suspended sender is a `SuspendedSender`
    // reference.  Receivers set `delivered = true` before signaling the
    // semaphore so that senders can distinguish successful delivery from a
    // close-induced wakeup.
    private var senderQueue: [SuspendedSender] = []

    // Waiting-receiver queue: each suspended receiver is a `SuspendedReceiver`
    // reference.  Senders deposit a value before signaling the semaphore.
    private var receiverQueue: [SuspendedReceiver] = []

    init(capacity: Int, bufferOverflow: ChannelBufferOverflow = .suspend) {
        self.capacity = max(0, capacity)
        self.bufferOverflow = bufferOverflow
    }

    /// Send a value into the channel, suspending (blocking) the caller when
    /// backpressure is needed.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending and the sentinel
    /// is returned if the coroutine has been cancelled (matching Kotlin's behavior
    /// of throwing `CancellationException` from `send`).
    ///
    /// Returns `.success` when the value is delivered, or `.closed` / `.cancelled`
    /// when the channel is closed or the calling coroutine is cancelled.
    func send(_ value: Int, continuation: Int = 0) -> ChannelOperationStatus {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // 1. Closed channel -- fail immediately.
        if closed {
            lock.unlock()
            return .closed
        }

        // 2. If there is a waiting receiver, hand the value off directly
        //    (both rendezvous and buffered benefit from this fast path).
        if let receiver = receiverQueue.first {
            receiverQueue.removeFirst()
            receiver.result = value
            lock.unlock()
            // Preserve rendezvous handoff ordering: let the sender resume and
            // return from `send` before the waiting receiver continues.
            resumeReceiverAsync(receiver)
            return .success
        }

        // 3. Buffered channel with space -- enqueue and return immediately.
        if capacity > 0, buffer.count < capacity {
            buffer.append(value)
            lock.unlock()
            return .success
        }

        // 3a. Handle buffer overflow based on strategy (CORO-001)
        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                // Fall through to suspension logic below
                break
            case .dropOldest:
                // Remove oldest element and add new one
                _ = buffer.removeFirst()
                buffer.append(value)
                lock.unlock()
                return .success
            case .dropLatest:
                // Drop the element being sent
                lock.unlock()
                return .success
            }
        }

        // 4. No room (buffer full or rendezvous) -- suspend the sender.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let senderSem = DispatchSemaphore(value: 0)
        let entry = SuspendedSender(semaphore: senderSem, continuation: continuation, value: value)

        senderQueue.append(entry)
        lock.unlock()

        // Channel send is not yet lowered as a true suspend point, so the
        // runtime must block here until a receiver or close/cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { receive() }` queued on this thread can run.
        RuntimePendingLaunchQueue.flush()
        senderSem.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasDelivered = entry.delivered
        let wasCancelled = entry.cancelledWakeup
        lock.unlock()

        // Cancellation only aborts the send if delivery did not already complete.
        if wasCancelled || (!wasDelivered && isCancelled(continuation: continuation)) {
            return wasCancelled ? .cancelled : .closed
        }
        return wasDelivered ? .success : .closed
    }

    /// Attempt to send a value without suspending.  A full rendezvous or
    /// buffered channel reports `.failed`; a closed channel reports `.closed`.
    func trySend(_ value: Int) -> ChannelOperationStatus {
        lock.lock()

        if closed {
            lock.unlock()
            return .closed
        }

        if let receiver = receiverQueue.first {
            receiverQueue.removeFirst()
            receiver.result = value
            lock.unlock()
            resumeReceiverAsync(receiver)
            return .success
        }

        if capacity > 0, buffer.count < capacity {
            buffer.append(value)
            lock.unlock()
            return .success
        }

        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                break
            case .dropOldest:
                _ = buffer.removeFirst()
                buffer.append(value)
                lock.unlock()
                return .success
            case .dropLatest:
                lock.unlock()
                return .success
            }
        }

        lock.unlock()
        return .failed
    }

    /// Receive a value from the channel, suspending (blocking) the caller when
    /// the buffer is empty and no sender is ready.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending (Kotlin suspend
    /// semantics: `receive` throws `CancellationException` if cancelled).
    ///
    /// On `.success`, writes the received value to `outValue`.  Returns `.closed`
    /// when the channel is closed and fully drained, or `.cancelled` when the
    /// coroutine was cancelled.
    func receive(continuation: Int = 0, outValue: UnsafeMutablePointer<Int>) -> ChannelOperationStatus {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // 1. Try to take from the buffer.
        if !buffer.isEmpty {
            let value = buffer.removeFirst()
            // If a sender is suspended (backpressure), wake the oldest one and
            // move its value into the buffer to maintain ordering.
            if let sender = senderQueue.first {
                senderQueue.removeFirst()
                buffer.append(sender.value)
                sender.delivered = true
                lock.unlock()
                // CORO-004: Use continuation-based resume if available
                resumeSender(sender)
            } else {
                lock.unlock()
            }
            outValue.pointee = value
            return .success
        }

        // 2. Buffer is empty -- try to pair directly with a waiting sender
        //    (rendezvous fast-path, also applies to buffered when a sender
        //    arrived while the buffer was full and then got drained completely).
        if let sender = senderQueue.first {
            senderQueue.removeFirst()
            let value = sender.value
            sender.delivered = true
            lock.unlock()
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
            outValue.pointee = value
            return .success
        }

        // 3. Nothing available -- if closed, report closed status.
        if closed {
            lock.unlock()
            return .closed
        }

        // 4. Suspend the receiver.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let receiverEntry = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: continuation)

        receiverQueue.append(receiverEntry)
        lock.unlock()

        // Channel receive is not yet lowered as a true suspend point, so the
        // runtime must block here until a sender, close, or cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { send(x) }` queued on this thread can run.
        // Without this, channel_basic-style rendezvous deadlocks (run exit 124).
        RuntimePendingLaunchQueue.flush()
        receiverEntry.semaphore.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasCancelled = receiverEntry.cancelledWakeup
        let value = receiverEntry.result
        lock.unlock()

        // Cancellation only aborts the receive if no sender delivered a value.
        if wasCancelled || (value == nil && isCancelled(continuation: continuation)) {
            return wasCancelled ? .cancelled : .closed
        }
        if let value {
            outValue.pointee = value
            return .success
        }
        // Woken by close() with no value -- channel is done.
        return .closed
    }

    /// Convenience wrapper used by in-process runtime tests.
    func receive(continuation: Int = 0) -> (status: ChannelOperationStatus, value: Int) {
        var value = 0
        let status = receive(continuation: continuation, outValue: &value)
        return (status, value)
    }

    /// `true` when the channel is closed AND its buffer is fully drained.
    /// Once `isClosedForReceive` is `true`, any subsequent `receive()` call will
    /// immediately return `.closed` without blocking.
    /// Matches Kotlin's `ReceiveChannel.isClosedForReceive` contract.
    var isClosedForReceive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed && buffer.isEmpty && senderQueue.isEmpty
    }

    /// Close the channel.  Remaining buffered values are still receivable.
    ///
    /// Returns `true` if this call actually closed the channel, `false` if it
    /// was already closed.  Matches Kotlin's `SendChannel.close()` contract.
    @discardableResult
    func close() -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        closed = true
        let pendingSenders = senderQueue
        senderQueue.removeAll()
        let pendingReceivers = receiverQueue
        receiverQueue.removeAll()
        lock.unlock()

        // Wake all suspended senders -- they will see `closed == true` and
        // return the closed sentinel.
        for sender in pendingSenders {
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        // Wake all suspended receivers -- they will find no result deposited
        // and return the closed sentinel.
        for receiver in pendingReceivers {
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
        return true
    }

    /// Cancel all suspended senders and receivers.  This is called when a
    /// coroutine is cancelled while it has an outstanding channel operation.
    ///
    /// In the current design we cancel *all* waiters because the continuation
    /// identity is not threaded into the waiter entries (the suspend-point is
    /// blocking the calling thread directly).  This is safe because each
    /// channel operation is called from exactly one coroutine at a time.
    func cancelAllWaiters() {
        lock.lock()
        let pendingSenders = senderQueue
        senderQueue.removeAll()
        let pendingReceivers = receiverQueue
        receiverQueue.removeAll()
        lock.unlock()

        for sender in pendingSenders {
            sender.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        for receiver in pendingReceivers {
            receiver.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
    }

    /// Returns the current suspended waiter counts under the channel lock.
    ///
    /// Runtime tests use this snapshot to synchronize with actual suspension
    /// instead of assuming a background queue has progressed after a fixed delay.
    func suspendedWaiterCountsSnapshot() -> (senders: Int, receivers: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (senderQueue.count, receiverQueue.count)
    }

    // MARK: - Private helpers

    /// CORO-004: Resume a suspended sender using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeSender(_ sender: SuspendedSender) {
        if let resumeClosure = sender.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            sender.semaphore.signal()
        }
    }

    /// CORO-004: Resume a suspended receiver using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeReceiver(_ receiver: SuspendedReceiver) {
        if let resumeClosure = receiver.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            receiver.semaphore.signal()
        }
    }

    /// Dispatch receiver wakeup asynchronously even for semaphore-backed waiters.
    /// This keeps direct sender->receiver handoff aligned with Kotlin's observed
    /// rendezvous ordering where the sender resumes from `send` before the
    /// receiver continues past `receive`.
    func resumeReceiverAsync(_ receiver: SuspendedReceiver) {
        DispatchQueue.global().async {
            self.resumeReceiver(receiver)
        }
    }

    /// Check whether the coroutine associated with `continuation` has been cancelled.
    private func isCancelled(continuation: Int) -> Bool {
        guard continuation != 0 else {
            return false
        }
        guard let state = runtimeContinuationState(from: continuation),
              let job = state.jobHandle
        else {
            return false
        }
        return job.cancellationSnapshot()
    }

    /// Thread-safe snapshot of the closed flag.
    ///
    /// Acquires the channel lock before reading `closed` to avoid data races
    /// with concurrent `send()`, `receive()`, and `close()` calls.
    func isClosedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }
}

@_cdecl("kk_channel_create")
public func kk_channel_create(_ capacity: Int) -> Int {
    let channel = RuntimeChannelHandle(capacity: capacity)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

public func kk_channel_send(_ handle: Int, _ value: Int) -> Int {
    kk_channel_send(handle, value, 0)
}

@_cdecl("kk_channel_send")
public func kk_channel_send(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else {
            return false
        }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }

    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(handle), isRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return channel.send(resolvedValue, continuation: continuation).rawValue
}

/// Non-suspending channel send used by `ProducerScope.trySend`.
@_cdecl("kk_channel_try_send")
public func kk_channel_try_send(_ handle: Int, _ value: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else {
            return false
        }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }

    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(handle), isRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_try_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return channel.trySend(resolvedValue).rawValue
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(
    _ handle: Int,
    _ continuation: Int,
    _ outValue: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    if let outValue {
        return channel.receive(continuation: continuation, outValue: outValue).rawValue
    }
    var scratch = 0
    return channel.receive(continuation: continuation, outValue: &scratch).rawValue
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close() ? 1 : 0
}

/// Returns 1 when `status` indicates a closed or cancelled channel operation,
/// 0 for successful and non-closed try-send failures.
@_cdecl("kk_channel_is_closed_token")
public func kk_channel_is_closed_token(_ status: Int) -> Int {
    return status == kChannelResultClosed || status == kChannelResultCancelled ? 1 : 0
}

/// Returns 1 if the channel is closed for receiving (i.e., it is closed AND the buffer
/// is empty — no more values will ever be available).  Returns 0 if the channel is
/// open or if it is closed but still has buffered values to drain.
///
/// Maps to Kotlin's `Channel.isClosedForReceive` property.
@_cdecl("kk_channel_is_closed_for_receive")
public func kk_channel_is_closed_for_receive(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedForReceive ? 1 : 0
}

/// Returns 1 if the channel is closed for sending (i.e., it has been closed via
/// `close()`).  Returns 0 if the channel is still open for new sends.
///
/// Maps to Kotlin's `Channel.isClosedForSend` property.
@_cdecl("kk_channel_is_closed_for_send")
public func kk_channel_is_closed_for_send(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedSnapshot() ? 1 : 0
}

// MARK: - Channel Iterator (CORO-075)
//
// A lightweight wrapper that allows channels to participate in the
// `kk_range_iterator` / `kk_range_hasNext` / `kk_range_next` loop protocol.
//
// The iterator holds the channel handle (strongly retained) and caches the
// result of the most recent `receive()` call.  `hasNext` must be called before
// `next` in each iteration step — which matches the pattern emitted by
// ControlFlowLowerer.lowerForExpr.
//
// IMPORTANT: `kk_channel_iterator_hasNext` suspends (blocking) on each call
// until either a value arrives or the channel is closed.  This means that
// for-in loops over channels are blocking-suspend operations, consistent with
// Kotlin's semantics when running inside runBlocking / launch.
private final class RuntimeChannelIterator: @unchecked Sendable {
    let channel: RuntimeChannelHandle
    /// Most recent value fetched by `hasNext`.  Reset to `nil` after `next`.
    var peekedValue: Int?
    /// Set to `true` once we observe the closed sentinel from `receive()`.
    var done: Bool = false
    private let lock = NSLock()

    init(channel: RuntimeChannelHandle) {
        self.channel = channel
    }

    /// Advance the iterator by doing a blocking receive.  Returns `true` if a
    /// value is available, `false` if the channel is closed and drained.
    func advance(continuation: Int = 0) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        lock.unlock()

        var value = 0
        let status = channel.receive(continuation: continuation, outValue: &value)
        lock.lock()
        defer { lock.unlock() }
        if status != .success {
            done = true
            peekedValue = nil
            return false
        }
        peekedValue = value
        return true
    }

    /// Return the cached value and clear it.
    func takeValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let v = peekedValue ?? 0
        peekedValue = nil
        return v
    }
}

/// Create a channel iterator for use in for-in loops.  The iterator reference
/// is registered in `runtimeStorage` so the GC can track it.
@_cdecl("kk_channel_iterator")
public func kk_channel_iterator(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_iterator received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let iter = RuntimeChannelIterator(channel: channel)
    let iterPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(iter).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: iterPtr))
    }
    return Int(bitPattern: iterPtr)
}

/// Returns 1 if the channel iterator has a next value, 0 if the channel is
/// closed and drained.  Blocks (suspends) until a value arrives or the channel
/// is closed.
@_cdecl("kk_channel_iterator_hasNext")
public func kk_channel_iterator_hasNext(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.advance() ? 1 : 0
}

/// Returns the value fetched by the most recent `kk_channel_iterator_hasNext`
/// call.  Must only be called after `kk_channel_iterator_hasNext` returns 1.
@_cdecl("kk_channel_iterator_next")
public func kk_channel_iterator_next(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.takeValue()
}

/// Read an element from a runtime array by index (mirrors kk_array_get without throw).
func runtimeReadArrayElement(arrayRaw: Int, index: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    guard let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self) else {
        return 0
    }
    guard index >= 0, index < arrayBox.elements.count else {
        return 0
    }
    return arrayBox.elements[index]
}
