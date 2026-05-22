import Dispatch
import Foundation

/// Channel runtime (CORO-001), Channel iterator (CORO-075),
/// BroadcastChannel runtime (CORO-076), and the Channel pipeline runtime.
///
/// Split out from `RuntimeCoroutine.swift`.

// MARK: - Channel Runtime (CORO-001)

/// Sentinel returned by `receive()` when the channel is closed and the buffer
/// is drained.  Callers can compare against this to detect the end-of-channel
/// condition without confusing it with a legitimate `0` value.
///
/// **ABI restriction**: `Int.min` is reserved as the closed-channel sentinel.
/// Sending `Int.min` (`Long.MIN_VALUE` in Kotlin) through a channel will cause
/// receivers / codegen to misidentify it as the closed token.  This is an
/// intentional trade-off for the current in-band signaling design.
///
/// TODO(CORO-001): Migrate to an out-of-band signaling mechanism (e.g., a
/// status+value return pair via pointer parameter, matching the pattern used by
/// `kk_coroutine_check_cancellation`) so that every `Int` value is sendable.
let kChannelClosedSentinel: Int = Int.min

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
    /// Returns the sent `value` on success, or `kChannelClosedSentinel` if the
    /// channel was closed before or during the send, or the coroutine was cancelled.
    func send(_ value: Int, continuation: Int = 0) -> Int {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 1. Closed channel -- fail immediately.
        if closed {
            lock.unlock()
            return kChannelClosedSentinel
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
            return value
        }

        // 3. Buffered channel with space -- enqueue and return immediately.
        if capacity > 0, buffer.count < capacity {
            buffer.append(value)
            lock.unlock()
            return value
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
                return value
            case .dropLatest:
                // Drop the element being sent
                lock.unlock()
                return value
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
        senderSem.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasDelivered = entry.delivered
        let wasCancelled = entry.cancelledWakeup
        lock.unlock()

        // Cancellation only aborts the send if delivery did not already complete.
        if wasCancelled || (!wasDelivered && isCancelled(continuation: continuation)) {
            return kChannelClosedSentinel
        }
        return wasDelivered ? value : kChannelClosedSentinel
    }

    /// Receive a value from the channel, suspending (blocking) the caller when
    /// the buffer is empty and no sender is ready.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending (Kotlin suspend
    /// semantics: `receive` throws `CancellationException` if cancelled).
    ///
    /// Returns the received value, or `kChannelClosedSentinel` when the channel
    /// is closed and fully drained, or the coroutine was cancelled.
    func receive(continuation: Int = 0) -> Int {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return kChannelClosedSentinel
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
            return value
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
            return value
        }

        // 3. Nothing available -- if closed, return the sentinel.
        if closed {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 4. Suspend the receiver.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let receiverEntry = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: continuation)
        
        receiverQueue.append(receiverEntry)
        lock.unlock()

        // Channel receive is not yet lowered as a true suspend point, so the
        // runtime must block here until a sender, close, or cancellation wakes it.
        receiverEntry.semaphore.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasCancelled = receiverEntry.cancelledWakeup
        let value = receiverEntry.result
        lock.unlock()

        // Cancellation only aborts the receive if no sender delivered a value.
        if wasCancelled || (value == nil && isCancelled(continuation: continuation)) {
            return kChannelClosedSentinel
        }
        if let value {
            return value
        }
        // Woken by close() with no value -- channel is done.
        return kChannelClosedSentinel
    }

    /// `true` when the channel is closed AND its buffer is fully drained.
    /// Once `isClosedForReceive` is `true`, any subsequent `receive()` call will
    /// immediately return `kChannelClosedSentinel` without blocking.
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

    /// Non-blocking receive: returns a buffered value immediately, or `nil`
    /// when the buffer is empty (regardless of closed state).  Does NOT
    /// suspend the caller or pair with a waiting sender.
    ///
    /// This is used by `kk_channel_pipeline_drain` to avoid blocking the
    /// thread when the source channel is empty but not yet closed.
    func tryReceive() -> Int? {
        lock.lock()
        if !buffer.isEmpty {
            let value = buffer.removeFirst()
            // Wake a waiting sender to fill the slot we just freed.
            if let sender = senderQueue.first {
                senderQueue.removeFirst()
                buffer.append(sender.value)
                sender.delivered = true
                lock.unlock()
                resumeSender(sender)
            } else {
                lock.unlock()
            }
            return value
        }
        // No buffered value; try to pair with a suspended sender directly.
        if let sender = senderQueue.first {
            senderQueue.removeFirst()
            let value = sender.value
            sender.delivered = true
            lock.unlock()
            resumeSender(sender)
            return value
        }
        lock.unlock()
        return nil
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
    runtimeStorage.withLock { state in
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
        let isRegistered = runtimeStorage.withLock { state in
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
    return channel.send(resolvedValue, continuation: continuation)
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.receive(continuation: continuation)
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close() ? 1 : 0
}

/// Returns 1 if `value` equals the closed-channel sentinel, 0 otherwise.
/// Codegen calls this after `kk_channel_receive` / `kk_channel_send` to detect
/// end-of-channel.
///
/// **ABI note**: Because the sentinel is currently the in-band value `Int.min`,
/// this function will also return 1 for a legitimately-sent `Int.min`.  See the
/// `kChannelClosedSentinel` documentation for the planned migration to
/// out-of-band signaling.
@_cdecl("kk_channel_is_closed_token")
public func kk_channel_is_closed_token(_ value: Int) -> Int {
    return value == kChannelClosedSentinel ? 1 : 0
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

        let value = channel.receive(continuation: continuation)
        lock.lock()
        defer { lock.unlock() }
        if value == kChannelClosedSentinel {
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
    runtimeStorage.withLock { state in
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

// MARK: - BroadcastChannel Runtime (CORO-076)

/// BroadcastChannel: a channel that delivers each sent value to all currently
/// subscribed receivers simultaneously (fan-out / multicast semantics).
///
/// Each subscriber gets its own receive queue backed by an individual
/// `RuntimeChannelHandle`.  `send` atomically enqueues the value into every
/// subscriber's channel so ordering is preserved per-subscriber.
///
/// **Lifecycle**:
/// - Call `subscribe()` to obtain a per-subscriber handle before receiving.
/// - Call `unsubscribe(handle:)` when the subscriber is done.
/// - Call `close()` to close the broadcast channel and all subscriber channels.
final class RuntimeBroadcastChannelHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [RuntimeChannelHandle] = []
    private var closed = false
    private let subscriberCapacity: Int

    init(subscriberCapacity: Int) {
        self.subscriberCapacity = subscriberCapacity
    }

    /// Create a new subscriber channel and register it.  Returns the channel handle.
    /// If the broadcast channel is already closed, the returned channel is immediately
    /// closed so that downstream receivers will not block forever.
    func subscribe() -> RuntimeChannelHandle {
        let ch = RuntimeChannelHandle(capacity: subscriberCapacity)
        lock.lock()
        if !closed {
            subscribers.append(ch)
            lock.unlock()
        } else {
            lock.unlock()
            _ = ch.close()
        }
        return ch
    }

    /// Remove a subscriber channel.  Closes the channel to unblock waiting receivers.
    func unsubscribe(_ channel: RuntimeChannelHandle) {
        lock.lock()
        subscribers.removeAll { $0 === channel }
        lock.unlock()
        _ = channel.close()
    }

    /// Send a value to all subscribers.  Returns the value on success, or
    /// `kChannelClosedSentinel` when the broadcast channel is closed.
    @discardableResult
    func send(_ value: Int) -> Int {
        lock.lock()
        if closed {
            lock.unlock()
            return kChannelClosedSentinel
        }
        let snapshot = subscribers
        lock.unlock()
        for ch in snapshot {
            _ = ch.send(value)
        }
        return value
    }

    /// Close the broadcast channel and every subscriber channel.
    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let snapshot = subscribers
        subscribers.removeAll()
        lock.unlock()
        for ch in snapshot {
            _ = ch.close()
        }
    }
}

@_cdecl("kk_broadcast_channel_create")
public func kk_broadcast_channel_create(_ subscriberCapacity: Int) -> Int {
    let bc = RuntimeBroadcastChannelHandle(subscriberCapacity: subscriberCapacity)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(bc).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_broadcast_channel_subscribe")
public func kk_broadcast_channel_subscribe(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_broadcast_channel_subscribe received invalid handle")
    }
    let bc = Unmanaged<RuntimeBroadcastChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let sub = bc.subscribe()
    let subPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(sub).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: subPtr))
    }
    return Int(bitPattern: subPtr)
}

@_cdecl("kk_broadcast_channel_unsubscribe")
public func kk_broadcast_channel_unsubscribe(_ broadcastHandle: Int, _ subscriberHandle: Int) -> Int {
    guard let bcPtr = UnsafeMutableRawPointer(bitPattern: broadcastHandle),
          let subPtr = UnsafeMutableRawPointer(bitPattern: subscriberHandle) else {
        return 0
    }
    let bc = Unmanaged<RuntimeBroadcastChannelHandle>.fromOpaque(bcPtr).takeUnretainedValue()
    let sub = Unmanaged<RuntimeChannelHandle>.fromOpaque(subPtr).takeUnretainedValue()
    bc.unsubscribe(sub)
    return 0
}

@_cdecl("kk_broadcast_channel_send")
public func kk_broadcast_channel_send(_ handle: Int, _ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_broadcast_channel_send received invalid handle")
    }
    let bc = Unmanaged<RuntimeBroadcastChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return bc.send(value)
}

@_cdecl("kk_broadcast_channel_close")
public func kk_broadcast_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_broadcast_channel_close received invalid handle")
    }
    let bc = Unmanaged<RuntimeBroadcastChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    bc.close()
    return 0
}

// MARK: - Channel Pipeline Runtime (CORO-076)

/// Creates a pipeline stage: reads from `sourceHandle`, applies an identity
/// transform (the actual transform is done in Kotlin coroutine code via the
/// stdlib `produce` / channel pipeline pattern), and writes to `destHandle`.
/// This ABI entry exists so codegen can link against it for future lowering.
/// In the current implementation the pipeline logic is handled in the Kotlin
/// stdlib layer backed by the existing `kk_channel_send` / `kk_channel_receive`
/// primitives; this function provides a synchronous drain helper for testing.
///
/// Reads all available (non-blocking) values from `sourceHandle` and forwards
/// them to `destHandle`.  Stops at the first closed-sentinel or empty drain.
/// Returns the number of values forwarded.
@_cdecl("kk_channel_pipeline_drain")
public func kk_channel_pipeline_drain(_ sourceHandle: Int, _ destHandle: Int) -> Int {
    guard let srcPtr = UnsafeMutableRawPointer(bitPattern: sourceHandle),
          let dstPtr = UnsafeMutableRawPointer(bitPattern: destHandle) else {
        return 0
    }
    let src = Unmanaged<RuntimeChannelHandle>.fromOpaque(srcPtr).takeUnretainedValue()
    let dst = Unmanaged<RuntimeChannelHandle>.fromOpaque(dstPtr).takeUnretainedValue()
    var count = 0
    while true {
        // Use non-blocking tryReceive to avoid blocking when the source channel
        // is empty but not yet closed (fixes indefinite thread stall).
        guard let v = src.tryReceive() else { break }
        if v == kChannelClosedSentinel { break }
        let sent = dst.send(v)
        if sent == kChannelClosedSentinel { break }
        count += 1
    }
    return count
}

// MARK: - Deferred / awaitAll Runtime Stub (P5-135)

@_cdecl("kk_await_all")
public func kk_await_all(_ handlesArray: Int, _ count: Int) -> Int {
    // Await each handle sequentially and return the result of the last one.
    // handlesArray points to a KKArray of async task handles.
    guard count > 0 else {
        return 0
    }
    var lastResult = 0
    for i in 0 ..< count {
        // Read handle from array using kk_array_get pattern
        let handleValue = runtimeReadArrayElement(arrayRaw: handlesArray, index: i)
        if handleValue != 0 {
            guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handleValue) else {
                continue
            }
            let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()
            lastResult = task.awaitResult()
        }
    }
    return lastResult
}

/// Read an element from a runtime array by index (mirrors kk_array_get without throw).
func runtimeReadArrayElement(arrayRaw: Int, index: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withLock { state in
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
