import Dispatch
import Foundation
@testable import Runtime
import Testing

// ThreadSafe container for test results in concurrent environments
class ThreadSafeInt: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }
}

/// One-shot completion signal for work performed on background queues.
private final class ChannelTestSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let description: String

    init(_ description: String) {
        self.description = description
    }

    func fulfill() {
        semaphore.signal()
    }

    func wait(timeout: TimeInterval, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            semaphore.wait(timeout: .now() + timeout) == .success,
            "\(description) should complete within \(timeout)s",
            sourceLocation: sourceLocation
        )
    }
}

private func waitForSignals(
    _ signals: [ChannelTestSignal],
    timeout: TimeInterval,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for signal in signals {
        signal.wait(timeout: timeout, sourceLocation: sourceLocation)
    }
}

/// Receive helper: returns `(status, value)` using the out-of-band `outValue` slot.
private func channelReceivePair(_ handle: Int, _ continuation: Int = 0) -> (status: Int, value: Int) {
    var value = 0
    let status = kk_channel_receive(handle, continuation, &value)
    return (status, value)
}

private func channelReceiveValue(_ handle: Int, _ continuation: Int = 0) -> Int {
    channelReceivePair(handle, continuation).value
}

private func runtimeChannelHandle(_ raw: Int) -> RuntimeChannelHandle {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        preconditionFailure("channel handle must be non-zero")
    }
    return Unmanaged<RuntimeChannelHandle>.fromOpaque(pointer).takeUnretainedValue()
}

private func waitForSuspendedWaiters(
    in channel: RuntimeChannelHandle,
    senders expectedSenders: Int = 0,
    receivers expectedReceivers: Int = 0,
    timeout: DispatchTimeInterval = .seconds(2)
) -> Bool {
    let deadline = DispatchTime.now() + timeout
    repeat {
        let counts = channel.suspendedWaiterCountsSnapshot()
        if counts.senders == expectedSenders, counts.receivers == expectedReceivers {
            return true
        }
        Thread.sleep(forTimeInterval: 0.001)
    } while DispatchTime.now() < deadline
    return false
}

private func waitForSuspendedWaiters(
    in rawChannel: Int,
    senders: Int = 0,
    receivers: Int = 0,
    timeout: DispatchTimeInterval = .seconds(2)
) -> Bool {
    waitForSuspendedWaiters(
        in: runtimeChannelHandle(rawChannel),
        senders: senders,
        receivers: receivers,
        timeout: timeout
    )
}

// MARK: - BUG-041 × channel blocking interaction

/// Shared rendezvous-channel handle for `runtime_test_channel_pending_launch_send`.
private final class ChannelPendingLaunchTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var channelHandle = 0

    func setChannel(_ handle: Int) {
        lock.lock()
        channelHandle = handle
        lock.unlock()
    }

    func channel() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return channelHandle
    }
}

private let channelPendingLaunchTestState = ChannelPendingLaunchTestState()
private let channelPendingLaunchFunctionID = 9201
private typealias ChannelPendingLaunchEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

/// Launched body: send `42` into the shared rendezvous channel, then exit.
@_cdecl("runtime_test_channel_pending_launch_send")
func runtime_test_channel_pending_launch_send(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let status = kk_channel_send(channelPendingLaunchTestState.channel(), 42, continuation)
    return kk_coroutine_state_exit(continuation, status)
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeChannelTests {
    // MARK: - Rendezvous Channel (capacity == 0)

    @Test func rendezvousSendReceivePairing() {
        let channelHandle = kk_channel_create(0)
        #expect(channelHandle != 0)

        let expectation = ChannelTestSignal("receive completes")
        let sendDone = ChannelTestSignal("send completes")
        let receivedValue = ThreadSafeInt()
        let sendResult = ThreadSafeInt()

        // Receive on a background thread (will suspend until a sender pairs).
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(channelHandle, 0))
            expectation.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: channelHandle, receivers: 1),
            "receiver should be suspended before the sender starts"
        )

        // Send on the main thread -- should wake the receiver.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 42, 0))
            sendDone.fulfill()
        }

        waitForSignals([expectation, sendDone], timeout: 2.0)
        #expect(sendResult.get() == kChannelResultSuccess, "send should return success status")
        #expect(receivedValue.get() == 42, "receiver should get the sent value")

        _ = kk_channel_close(channelHandle)
    }

    @Test func rendezvousSenderSuspendsUntilReceiverArrives() {
        let channelHandle = kk_channel_create(0)

        let sendDone = ChannelTestSignal("send completes")
        let receiveDone = ChannelTestSignal("receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        // Send on background thread -- no receiver yet, so it should suspend.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 99, 0))
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: channelHandle, senders: 1),
            "sender should be suspended before the receiver starts"
        )

        // Receive on the main thread -- should unblock the sender.
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(channelHandle, 0))
            receiveDone.fulfill()
        }

        waitForSignals([sendDone, receiveDone], timeout: 2.0)
        #expect(receivedValue.get() == 99)
        #expect(sendResult.get() == kChannelResultSuccess)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Buffered Channel (capacity > 0)

    @Test func bufferedSendDoesNotBlockWhenBufferHasSpace() {
        let channelHandle = kk_channel_create(2)

        // Two sends should return immediately without any receiver.
        #expect(kk_channel_send(channelHandle, 10, 0) == kChannelResultSuccess)
        #expect(kk_channel_send(channelHandle, 20, 0) == kChannelResultSuccess)

        // Receive both in order.
        #expect(channelReceiveValue(channelHandle, 0) == 10)
        #expect(channelReceiveValue(channelHandle, 0) == 20)

        _ = kk_channel_close(channelHandle)
    }

    @Test func bufferedSendSuspendsWhenFull() {
        let channelHandle = kk_channel_create(1)

        // First send fills the buffer.
        #expect(kk_channel_send(channelHandle, 1, 0) == kChannelResultSuccess)

        let sendDone = ChannelTestSignal("second send completes")
        let secondSendResult = ThreadSafeInt()

        // Second send should suspend (backpressure).
        DispatchQueue.global().async {
            secondSendResult.set(kk_channel_send(channelHandle, 2, 0))
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: channelHandle, senders: 1),
            "second sender should be suspended while the buffer is full"
        )

        // Receive the first item -- should free buffer space and wake the sender.
        #expect(channelReceiveValue(channelHandle, 0) == 1)

        waitForSignals([sendDone], timeout: 2.0)
        #expect(secondSendResult.get() == kChannelResultSuccess, "suspended sender should complete after space opens")

        // The second value should now be in the buffer.
        #expect(channelReceiveValue(channelHandle, 0) == 2)

        _ = kk_channel_close(channelHandle)
    }

    @Test func bufferedChannelPreservesFIFOOrder() {
        let channelHandle = kk_channel_create(4)

        for i in 1 ... 4 {
            #expect(kk_channel_send(channelHandle, i, 0) == kChannelResultSuccess)
        }

        for i in 1 ... 4 {
            #expect(channelReceiveValue(channelHandle, 0) == i, "FIFO order violated at index \(i)")
        }

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Close Semantics

    @Test func closeWakesSuspendedReceiverWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let receiveDone = ChannelTestSignal("receive wakes on close")
        let receivedValue = ThreadSafeInt()

        DispatchQueue.global().async {
            receivedValue.set(channelReceivePair(channelHandle, 0).status)
            receiveDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: channelHandle, receivers: 1),
            "receiver should be suspended before the channel closes"
        )

        _ = kk_channel_close(channelHandle)

        waitForSignals([receiveDone], timeout: 2.0)
        #expect(
            kk_channel_is_closed_token(receivedValue.get()) == 1,
            "Receiver should get closed status when channel closes with empty buffer"
        )
    }

    @Test func closeWakesSuspendedSenderWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let sendDone = ChannelTestSignal("send wakes on close")
        let sendResult = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 77, 0))
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: channelHandle, senders: 1),
            "sender should be suspended before the channel closes"
        )

        _ = kk_channel_close(channelHandle)

        waitForSignals([sendDone], timeout: 2.0)
        #expect(
            kk_channel_is_closed_token(sendResult.get()) == 1,
            "Sender should get the closed sentinel when channel closes"
        )
    }

    @Test func sendOnClosedChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = kk_channel_send(channelHandle, 42, 0)
        #expect(kk_channel_is_closed_token(result) == 1)
    }

    @Test func receiveOnClosedEmptyChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = channelReceivePair(channelHandle, 0).status
        #expect(kk_channel_is_closed_token(result) == 1)
    }

    @Test func receiveAfterCloseDrainsBufferFirst() {
        let channelHandle = kk_channel_create(3)

        #expect(kk_channel_send(channelHandle, 10, 0) == kChannelResultSuccess)
        #expect(kk_channel_send(channelHandle, 20, 0) == kChannelResultSuccess)

        _ = kk_channel_close(channelHandle)

        // Buffered values should still be receivable after close.
        #expect(channelReceiveValue(channelHandle, 0) == 10)
        #expect(channelReceiveValue(channelHandle, 0) == 20)

        // Now the buffer is drained -- should get closed status.
        let result = channelReceivePair(channelHandle, 0).status
        #expect(kk_channel_is_closed_token(result) == 1)
    }

    // MARK: - Closed Token Helper

    @Test func isClosedTokenDistinguishesStatusCodes() {
        #expect(kk_channel_is_closed_token(kChannelResultSuccess) == 0, "success is not a failure status")
        #expect(kk_channel_is_closed_token(kChannelResultClosed) == 1, "closed is a failure status")
        #expect(kk_channel_is_closed_token(kChannelResultCancelled) == 1, "cancelled is a failure status")
    }

    @Test func trySendReportsFailureWithoutSuspending() {
        let channelHandle = kk_channel_create(1)

        #expect(kk_channel_try_send(channelHandle, 10) == kChannelResultSuccess)
        #expect(kk_channel_try_send(channelHandle, 20) == kChannelResultFailed)
        #expect(kk_channel_is_closed_token(kChannelResultFailed) == 0)

        #expect(channelReceiveValue(channelHandle, 0) == 10)
        #expect(kk_channel_try_send(channelHandle, 20) == kChannelResultSuccess)
        #expect(channelReceiveValue(channelHandle, 0) == 20)

        _ = kk_channel_close(channelHandle)
        #expect(kk_channel_try_send(channelHandle, 30) == kChannelResultClosed)
    }

    @Test func sendAndReceiveLongMinValue() {
        let ch = kk_channel_create(1)
        #expect(kk_channel_send(ch, Int.min, 0) == kChannelResultSuccess)
        #expect(channelReceiveValue(ch, 0) == Int.min, "Long.MIN_VALUE must round-trip through the channel")
        _ = kk_channel_close(ch)
    }

    /// End-to-end test: `kk_channel_is_closed_token` returns 1 only after close
    /// *and* buffer drain through the full runtime -> ABI boundary path.
    @Test func isClosedTokenEndToEndCloseThenDrain() {
        let ch = kk_channel_create(2)

        // Send two values, then close.
        _ = kk_channel_send(ch, 100, 0)
        _ = kk_channel_send(ch, 200, 0)
        _ = kk_channel_close(ch)

        // Drain buffered values -- these should succeed with real payloads.
        let pair1 = channelReceivePair(ch, 0)
        #expect(kk_channel_is_closed_token(pair1.status) == 0,
                "Buffered value after close must not be identified as failure")
        #expect(pair1.value == 100)

        let pair2 = channelReceivePair(ch, 0)
        #expect(kk_channel_is_closed_token(pair2.status) == 0,
                "Buffered value after close must not be identified as failure")
        #expect(pair2.value == 200)

        // Buffer is now drained -- receive should return closed status.
        let pair3 = channelReceivePair(ch, 0)
        #expect(kk_channel_is_closed_token(pair3.status) == 1,
                "Receive after close+drain must return closed status")

        // send on a closed channel should also return closed status.
        let sendStatus = kk_channel_send(ch, 999, 0)
        #expect(kk_channel_is_closed_token(sendStatus) == 1,
                "Send on closed channel must return closed status")
    }

    // MARK: - Race Condition: Sender Woken by Receiver, Then Close

    /// Verify that a suspended sender reports success when a receiver accepts
    /// its value, even if close() races concurrently.  Before the delivered-flag
    /// fix this would incorrectly return kChannelClosedSentinel.
    @Test func senderReportsSuccessWhenReceiverAcceptsThenCloseRaces() {
        for _ in 0 ..< 20 {
            let ch = kk_channel_create(0) // rendezvous

            let sendDone = ChannelTestSignal("send completes")
            let receiveDone = ChannelTestSignal("receive completes")
            let sendResult = ThreadSafeInt()
            let receivedValue = ThreadSafeInt()

            // Sender suspends on rendezvous channel.
            DispatchQueue.global().async {
                sendResult.set(kk_channel_send(ch, 77, 0))
                sendDone.fulfill()
            }
            #expect(
                waitForSuspendedWaiters(in: ch, senders: 1),
                "sender should be suspended before the receiver starts"
            )

            // Receiver accepts the value -- sender should see success.
            DispatchQueue.global().async {
                receivedValue.set(channelReceiveValue(ch, 0))
                receiveDone.fulfill()
            }

            waitForSignals([receiveDone], timeout: 2.0)
            #expect(receivedValue.get() == 77)

            // Close immediately after receive to create the race window.
            _ = kk_channel_close(ch)

            waitForSignals([sendDone], timeout: 2.0)
            #expect(sendResult.get() == kChannelResultSuccess,
                    "Sender must report success when receiver accepted, even if close() races")
            #expect(kk_channel_is_closed_token(sendResult.get()) == 0,
                    "Send result must NOT be a failure status when receiver accepted the value")
        }
    }

    // MARK: - Backpressure with Multiple Senders

    @Test func multipleSendersBlockAndResumeInOrder() {
        let channelHandle = kk_channel_create(1)

        // Fill the single-slot buffer.
        #expect(kk_channel_send(channelHandle, 1, 0) == kChannelResultSuccess)

        let send2Done = ChannelTestSignal("sender 2 completes")
        let send3Done = ChannelTestSignal("sender 3 completes")

        // Two more senders should both suspend.
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 2, 0)
            send2Done.fulfill()
        }
        #expect(
            waitForSuspendedWaiters(in: channelHandle, senders: 1),
            "sender 2 should be first in the suspended queue"
        )
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 3, 0)
            send3Done.fulfill()
        }
        #expect(
            waitForSuspendedWaiters(in: channelHandle, senders: 2),
            "both senders should be queued before receiving"
        )

        // Receive all three values in FIFO order.
        #expect(channelReceiveValue(channelHandle, 0) == 1)
        #expect(channelReceiveValue(channelHandle, 0) == 2)
        #expect(channelReceiveValue(channelHandle, 0) == 3)

        waitForSignals([send2Done, send3Done], timeout: 2.0)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Multiple Receivers

    @Test func multipleReceiversBlockAndEachGetsOneValue() {
        let channelHandle = kk_channel_create(0)

        let recv1Done = ChannelTestSignal("receiver 1 completes")
        let recv2Done = ChannelTestSignal("receiver 2 completes")
        let received1 = ThreadSafeInt()
        let received2 = ThreadSafeInt()

        DispatchQueue.global().async {
            received1.set(channelReceiveValue(channelHandle, 0))
            recv1Done.fulfill()
        }
        #expect(
            waitForSuspendedWaiters(in: channelHandle, receivers: 1),
            "receiver 1 should be first in the suspended queue"
        )
        DispatchQueue.global().async {
            received2.set(channelReceiveValue(channelHandle, 0))
            recv2Done.fulfill()
        }
        #expect(
            waitForSuspendedWaiters(in: channelHandle, receivers: 2),
            "both receivers should be queued before sending"
        )

        // Send two values -- each receiver gets one.
        _ = kk_channel_send(channelHandle, 10, 0)
        _ = kk_channel_send(channelHandle, 20, 0)

        waitForSignals([recv1Done, recv2Done], timeout: 2.0)

        let values = Set([received1.get(), received2.get()])
        #expect(values == Set([10, 20]), "Each receiver should get exactly one distinct value")

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - close() Returns Boolean (Kotlin Semantics)

    @Test func closeReturnsTrueOnFirstCloseFalseOnSubsequent() {
        let ch = kk_channel_create(1)

        // First close should return 1 (true).
        let firstClose = kk_channel_close(ch)
        #expect(firstClose == 1, "First close() should return 1 (true)")

        // Second close should return 0 (false) -- already closed.
        let secondClose = kk_channel_close(ch)
        #expect(secondClose == 0, "Second close() should return 0 (false)")

        // Third close should also return 0 (false).
        let thirdClose = kk_channel_close(ch)
        #expect(thirdClose == 0, "Subsequent close() should return 0 (false)")
    }

    // MARK: - Cancellation-Aware Send/Receive

    @Test func sendWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- send would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        _ = job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Send with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no receiver is waiting).
        let result = kk_channel_send(ch, 42, contInt)
        #expect(kk_channel_is_closed_token(result) == 1,
                "send() with cancelled continuation should return the closed sentinel")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    @Test func receiveWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- receive would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        _ = job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Receive with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no sender is waiting).
        let result = channelReceivePair(ch, contInt).status
        #expect(kk_channel_is_closed_token(result) == 1,
                "receive() with cancelled continuation should return failure status")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    @Test func sendWithZeroContinuationStillWorks() {
        // Verify backward compatibility: continuation == 0 means no cancellation check.
        let ch = kk_channel_create(1) // buffered -- send won't block

        let result = kk_channel_send(ch, 42, 0)
        #expect(result == kChannelResultSuccess, "send() with zero continuation should succeed normally")

        let received = channelReceiveValue(ch, 0)
        #expect(received == 42)

        _ = kk_channel_close(ch)
    }

    // MARK: - CORO-001: Post-Wakeup Cancellation Semantics

    /// Once a rendezvous send is matched with a receiver, the send result should
    /// report success even if cancellation races with the wakeup.
    @Test func sendWithCancellationDuringSuspensionSucceedsAfterDelivery() {
        let ch = kk_channel_create(0) // rendezvous - will suspend

        let sendDone = ChannelTestSignal("send completes")
        let receiveDone = ChannelTestSignal("receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        // Create a job handle that we'll cancel while send is suspended
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Send on background thread - will suspend waiting for receiver
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 42, contInt))
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, senders: 1),
            "sender should be suspended before cancellation"
        )

        // Cancel the job while sender is suspended
        _ = job.cancel()

        // Now add a receiver - the rendezvous completes before cancellation can
        // affect the next suspension point, so the send still succeeds.
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(ch, 0))
            receiveDone.fulfill()
        }

        waitForSignals([sendDone, receiveDone], timeout: 2.0)
        #expect(sendResult.get() == kChannelResultSuccess, "Send should succeed once the value is delivered")
        #expect(receivedValue.get() == 42, "Receiver should observe the delivered value")

        // Clean up
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    /// Once a rendezvous receive is matched with a sender, the receive result should
    /// return the delivered value even if cancellation races with the wakeup.
    @Test func receiveWithCancellationDuringSuspensionSucceedsAfterDelivery() {
        let ch = kk_channel_create(0) // rendezvous - will suspend

        let receiveDone = ChannelTestSignal("receive completes")
        let sendDone = ChannelTestSignal("send completes")

        let receiveResult = ThreadSafeInt()
        let sendResult = ThreadSafeInt()

        // Create a job handle that we'll cancel while receive is suspended
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Receive on background thread - will suspend waiting for sender
        DispatchQueue.global().async {
            receiveResult.set(channelReceiveValue(ch, contInt))
            receiveDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, receivers: 1),
            "receiver should be suspended before cancellation"
        )

        // Cancel the job while receiver is suspended
        _ = job.cancel()

        // Now add a sender - the rendezvous completes before cancellation can
        // retroactively discard the received value.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 99, 0))
            sendDone.fulfill()
        }

        waitForSignals([receiveDone, sendDone], timeout: 2.0)
        #expect(receiveResult.get() == 99, "Receive should succeed once a sender delivered a value")
        #expect(sendResult.get() == kChannelResultSuccess, "Sender should observe successful delivery")

        // Clean up
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    // MARK: - CORO-001: Buffer Overflow Strategy Tests

    /// Test DROP_OLDEST buffer overflow strategy
    @Test func bufferOverflowDropOldest() {
        // Create a channel with DROP_OLDEST strategy
        let ch = RuntimeChannelHandle(capacity: 2, bufferOverflow: .dropOldest)

        // Fill the buffer
        #expect(ch.send(1) == .success)
        #expect(ch.send(2) == .success)

        // Send one more - should drop oldest (1) and add new one (3)
        #expect(ch.send(3) == .success)

        // Buffer should now contain [2, 3]
        #expect(ch.receive().value == 2)
        #expect(ch.receive().value == 3)
    }

    /// Test DROP_LATEST buffer overflow strategy
    @Test func bufferOverflowDropLatest() {
        // Create a channel with DROP_LATEST strategy
        let ch = RuntimeChannelHandle(capacity: 2, bufferOverflow: .dropLatest)

        // Fill the buffer
        #expect(ch.send(1) == .success)
        #expect(ch.send(2) == .success)

        // Send one more - should be dropped, buffer remains [1, 2]
        #expect(ch.send(3) == .success)

        // Buffer should still contain [1, 2]
        #expect(ch.receive().value == 1)
        #expect(ch.receive().value == 2)
    }

    /// Test SUSPEND buffer overflow strategy (default behavior)
    @Test func bufferOverflowSuspendBlocks() {
        let ch = RuntimeChannelHandle(capacity: 1, bufferOverflow: .suspend)

        // Fill the buffer
        #expect(ch.send(1) == .success)

        let sendDone = ChannelTestSignal("second send completes")
        let sendResult = ThreadSafeInt()

        // Second send should suspend
        DispatchQueue.global().async {
            sendResult.set(ch.send(2).rawValue)
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, senders: 1),
            "sender should be suspended while the buffer is full"
        )

        // Receive to free up space
        #expect(ch.receive().value == 1)

        waitForSignals([sendDone], timeout: 2.0)
        #expect(sendResult.get() == ChannelOperationStatus.success.rawValue)
    }

    @Test func cancelAllWaitersWakesSuspendedSenders() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let sendDone = ChannelTestSignal("send wakes on cancel")
        let sendResult = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(ch.send(42).rawValue)
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, senders: 1),
            "sender should be suspended before waiters are cancelled"
        )

        // Cancel all waiters.
        ch.cancelAllWaiters()

        waitForSignals([sendDone], timeout: 2.0)
        #expect(
            kk_channel_is_closed_token(sendResult.get()) == 1,
            "Cancelled sender should get failure status"
        )
    }

    // MARK: - CORO-004: Continuation Model Tests

    /// Test that continuation-based suspension works correctly
    @Test func continuationBasedSend() {
        // This test would require codegen support to fully test the continuation model
        // For now, we test that the fallback to semaphore still works
        let ch = kk_channel_create(0) // rendezvous

        let sendDone = ChannelTestSignal("send completes")
        let receiveDone = ChannelTestSignal("receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 42, 0)) // no continuation - fallback to semaphore
            sendDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, senders: 1),
            "sender should be suspended before the receiver starts"
        )

        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(ch, 0))
            receiveDone.fulfill()
        }

        waitForSignals([sendDone, receiveDone], timeout: 2.0)
        #expect(receivedValue.get() == 42)
        #expect(sendResult.get() == kChannelResultSuccess)

        _ = kk_channel_close(ch)
    }

    /// Test that the resume methods work correctly
    @Test func resumeMethodsWork() {
        let ch = RuntimeChannelHandle(capacity: 0)

        // Test that resume methods don't crash and handle nil resumeClosure gracefully
        let sender = SuspendedSender(semaphore: DispatchSemaphore(value: 0), continuation: 0, value: 42)
        let receiver = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: 0)

        // These should not crash and should fall back to semaphore
        ch.resumeSender(sender)
        ch.resumeReceiver(receiver)

        // Test with resume closure
        let resumeExpectation = ChannelTestSignal("resume closure called")
        let senderWithClosure = SuspendedSender(semaphore: DispatchSemaphore(value: 0), continuation: 0, value: 42)
        senderWithClosure.resumeClosure = {
            resumeExpectation.fulfill()
        }

        ch.resumeSender(senderWithClosure)
        waitForSignals([resumeExpectation], timeout: 1.0)
    }

    @Test func cancelAllWaitersWakesSuspendedReceivers() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let recvDone = ChannelTestSignal("receive wakes on cancel")
        let recvResult = ThreadSafeInt()

        DispatchQueue.global().async {
            recvResult.set(ch.receive().status.rawValue)
            recvDone.fulfill()
        }

        #expect(
            waitForSuspendedWaiters(in: ch, receivers: 1),
            "receiver should be suspended before waiters are cancelled"
        )

        // Cancel all waiters.
        ch.cancelAllWaiters()

        waitForSignals([recvDone], timeout: 2.0)
        #expect(
            kk_channel_is_closed_token(recvResult.get()) == 1,
            "Cancelled receiver should get failure status"
        )
    }

    /// BUG-041 deferred `launch{}` must be flushed before channel receive blocks.
    ///
    /// Reproduces the channel_basic.kt hang (diff run exit 124): inside an active
    /// coroutine burst, `launch { send }` is queued in RuntimePendingLaunchQueue
    /// and never dispatched until the burst yields. Channel receive is still a
    /// blocking semaphore wait (not a true suspend point), so without an explicit
    /// flush before `wait()` the receiver deadlocks forever.
    @Test func receiveFlushesPendingLaunchBeforeBlocking() {
        let channel = kk_channel_create(0)
        channelPendingLaunchTestState.setChannel(channel)

        RuntimeCoroutineBurstDepth.enter()
        defer {
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
        }

        let entryRaw = unsafeBitCast(
            runtime_test_channel_pending_launch_send as ChannelPendingLaunchEntry,
            to: Int.self
        )
        let job = kk_kxmini_launch(entryRaw, channelPendingLaunchFunctionID)
        #expect(job != 0, "launch should return a job handle")

        var value = 0
        let status = kk_channel_receive(channel, 0, &value)
        #expect(status == kChannelResultSuccess, "receive should complete after flushing the pending sender")
        #expect(value == 42)
        #expect(kk_job_join(job, 0) == kChannelResultSuccess)
    }
}
