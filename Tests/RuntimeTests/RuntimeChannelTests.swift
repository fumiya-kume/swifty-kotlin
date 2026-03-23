import Dispatch
@testable import Runtime
import XCTest

final class RuntimeChannelTests: IsolatedRuntimeXCTestCase {

    // MARK: - Rendezvous Channel (capacity == 0)

    func testRendezvousSendReceivePairing() {
        let channelHandle = kk_channel_create(0)
        XCTAssertNotEqual(channelHandle, 0)

        let expectation = XCTestExpectation(description: "receive completes")
        nonisolated(unsafe) var receivedValue = 0

        // Receive on a background thread (will suspend until a sender pairs).
        DispatchQueue.global().async {
            receivedValue = kk_channel_receive(channelHandle, 0)
            expectation.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Send on the main thread -- should wake the receiver.
        let sendResult = kk_channel_send(channelHandle, 42, 0)
        XCTAssertEqual(sendResult, 42, "send should return the sent value")

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedValue, 42, "receiver should get the sent value")

        _ = kk_channel_close(channelHandle)
    }

    func testRendezvousSenderSuspendsUntilReceiverArrives() {
        let channelHandle = kk_channel_create(0)

        let sendDone = XCTestExpectation(description: "send completes")
        nonisolated(unsafe) var sendResult = 0

        // Send on background thread -- no receiver yet, so it should suspend.
        DispatchQueue.global().async {
            sendResult = kk_channel_send(channelHandle, 99, 0)
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Receive on the main thread -- should unblock the sender.
        let received = kk_channel_receive(channelHandle, 0)
        XCTAssertEqual(received, 99)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(sendResult, 99)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Buffered Channel (capacity > 0)

    func testBufferedSendDoesNotBlockWhenBufferHasSpace() {
        let channelHandle = kk_channel_create(2)

        // Two sends should return immediately without any receiver.
        let r1 = kk_channel_send(channelHandle, 10, 0)
        let r2 = kk_channel_send(channelHandle, 20, 0)
        XCTAssertEqual(r1, 10)
        XCTAssertEqual(r2, 20)

        // Receive both in order.
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 10)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 20)

        _ = kk_channel_close(channelHandle)
    }

    func testBufferedSendSuspendsWhenFull() {
        let channelHandle = kk_channel_create(1)

        // First send fills the buffer.
        XCTAssertEqual(kk_channel_send(channelHandle, 1, 0), 1)

        let sendDone = XCTestExpectation(description: "second send completes")
        nonisolated(unsafe) var secondSendResult = 0

        // Second send should suspend (backpressure).
        DispatchQueue.global().async {
            secondSendResult = kk_channel_send(channelHandle, 2, 0)
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Receive the first item -- should free buffer space and wake the sender.
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 1)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(secondSendResult, 2, "suspended sender should complete after space opens")

        // The second value should now be in the buffer.
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 2)

        _ = kk_channel_close(channelHandle)
    }

    func testBufferedChannelPreservesFIFOOrder() {
        let channelHandle = kk_channel_create(4)

        for i in 1 ... 4 {
            XCTAssertEqual(kk_channel_send(channelHandle, i, 0), i)
        }

        for i in 1 ... 4 {
            XCTAssertEqual(kk_channel_receive(channelHandle, 0), i, "FIFO order violated at index \(i)")
        }

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Close Semantics

    func testCloseWakesSuspendedReceiverWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let receiveDone = XCTestExpectation(description: "receive wakes on close")
        nonisolated(unsafe) var receivedValue = 0

        DispatchQueue.global().async {
            receivedValue = kk_channel_receive(channelHandle, 0)
            receiveDone.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        _ = kk_channel_close(channelHandle)

        wait(for: [receiveDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(receivedValue), 1,
            "Receiver should get the closed sentinel when channel closes with empty buffer"
        )
    }

    func testCloseWakesSuspendedSenderWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let sendDone = XCTestExpectation(description: "send wakes on close")
        nonisolated(unsafe) var sendResult = 0

        DispatchQueue.global().async {
            sendResult = kk_channel_send(channelHandle, 77, 0)
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        _ = kk_channel_close(channelHandle)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(sendResult), 1,
            "Sender should get the closed sentinel when channel closes"
        )
    }

    func testSendOnClosedChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = kk_channel_send(channelHandle, 42, 0)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    func testReceiveOnClosedEmptyChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = kk_channel_receive(channelHandle, 0)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    func testReceiveAfterCloseDrainsBufferFirst() {
        let channelHandle = kk_channel_create(3)

        XCTAssertEqual(kk_channel_send(channelHandle, 10, 0), 10)
        XCTAssertEqual(kk_channel_send(channelHandle, 20, 0), 20)

        _ = kk_channel_close(channelHandle)

        // Buffered values should still be receivable after close.
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 10)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 20)

        // Now the buffer is drained -- should get sentinel.
        let result = kk_channel_receive(channelHandle, 0)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    // MARK: - Closed Token Helper

    func testIsClosedTokenDistinguishesSentinelFromNormalValues() {
        XCTAssertEqual(kk_channel_is_closed_token(0), 0, "zero is not the sentinel")
        XCTAssertEqual(kk_channel_is_closed_token(1), 0, "one is not the sentinel")
        XCTAssertEqual(kk_channel_is_closed_token(-1), 0, "negative one is not the sentinel")
        XCTAssertEqual(kk_channel_is_closed_token(Int.min), 1, "Int.min is the sentinel")
    }

    /// End-to-end test: `kk_channel_is_closed_token` returns 1 only after close
    /// *and* buffer drain through the full runtime -> ABI boundary path.
    func testIsClosedTokenEndToEnd_closeThenDrain() {
        let ch = kk_channel_create(2)

        // Send two values, then close.
        _ = kk_channel_send(ch, 100, 0)
        _ = kk_channel_send(ch, 200, 0)
        _ = kk_channel_close(ch)

        // Drain buffered values -- these should NOT be the sentinel.
        let v1 = kk_channel_receive(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(v1), 0,
                       "Buffered value after close must not be identified as sentinel")
        XCTAssertEqual(v1, 100)

        let v2 = kk_channel_receive(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(v2), 0,
                       "Buffered value after close must not be identified as sentinel")
        XCTAssertEqual(v2, 200)

        // Buffer is now drained -- receive should return sentinel.
        let v3 = kk_channel_receive(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(v3), 1,
                       "Receive after close+drain must return sentinel")

        // send on a closed channel should also return sentinel.
        let v4 = kk_channel_send(ch, 999, 0)
        XCTAssertEqual(kk_channel_is_closed_token(v4), 1,
                       "Send on closed channel must return sentinel")
    }

    // MARK: - Race Condition: Sender Woken by Receiver, Then Close

    /// Verify that a suspended sender reports success when a receiver accepts
    /// its value, even if close() races concurrently.  Before the delivered-flag
    /// fix this would incorrectly return kChannelClosedSentinel.
    func testSenderReportsSuccessWhenReceiverAcceptsThenCloseRaces() {
        for _ in 0 ..< 20 {
            let ch = kk_channel_create(0) // rendezvous

            let sendDone = XCTestExpectation(description: "send completes")
            nonisolated(unsafe) var sendResult = 0

            // Sender suspends on rendezvous channel.
            DispatchQueue.global().async {
                sendResult = kk_channel_send(ch, 77, 0)
                sendDone.fulfill()
            }
            Thread.sleep(forTimeInterval: 0.01)

            // Receiver accepts the value -- sender should see success.
            let received = kk_channel_receive(ch, 0)
            XCTAssertEqual(received, 77)

            // Close immediately after receive to create the race window.
            _ = kk_channel_close(ch)

            wait(for: [sendDone], timeout: 2.0)
            XCTAssertEqual(sendResult, 77,
                           "Sender must report success (value) when receiver accepted, even if close() races")
            XCTAssertEqual(kk_channel_is_closed_token(sendResult), 0,
                           "Send result must NOT be the closed sentinel when receiver accepted the value")
        }
    }

    // MARK: - Backpressure with Multiple Senders

    func testMultipleSendersBlockAndResumeInOrder() {
        let channelHandle = kk_channel_create(1)

        // Fill the single-slot buffer.
        XCTAssertEqual(kk_channel_send(channelHandle, 1, 0), 1)

        let send2Done = XCTestExpectation(description: "sender 2 completes")
        let send3Done = XCTestExpectation(description: "sender 3 completes")

        // Two more senders should both suspend.
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 2, 0)
            send2Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 3, 0)
            send3Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)

        // Receive all three values in FIFO order.
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 1)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 2)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0), 3)

        wait(for: [send2Done, send3Done], timeout: 2.0)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Multiple Receivers

    func testMultipleReceiversBlockAndEachGetsOneValue() {
        let channelHandle = kk_channel_create(0)

        let recv1Done = XCTestExpectation(description: "receiver 1 completes")
        let recv2Done = XCTestExpectation(description: "receiver 2 completes")
        nonisolated(unsafe) var received1 = 0
        nonisolated(unsafe) var received2 = 0

        DispatchQueue.global().async {
            received1 = kk_channel_receive(channelHandle, 0)
            recv1Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)
        DispatchQueue.global().async {
            received2 = kk_channel_receive(channelHandle, 0)
            recv2Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)

        // Send two values -- each receiver gets one.
        _ = kk_channel_send(channelHandle, 10, 0)
        _ = kk_channel_send(channelHandle, 20, 0)

        wait(for: [recv1Done, recv2Done], timeout: 2.0)

        let values = Set([received1, received2])
        XCTAssertEqual(values, Set([10, 20]), "Each receiver should get exactly one distinct value")

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - close() Returns Boolean (Kotlin Semantics)

    func testCloseReturnsTrueOnFirstCloseFalseOnSubsequent() {
        let ch = kk_channel_create(1)

        // First close should return 1 (true).
        let firstClose = kk_channel_close(ch)
        XCTAssertEqual(firstClose, 1, "First close() should return 1 (true)")

        // Second close should return 0 (false) -- already closed.
        let secondClose = kk_channel_close(ch)
        XCTAssertEqual(secondClose, 0, "Second close() should return 0 (false)")

        // Third close should also return 0 (false).
        let thirdClose = kk_channel_close(ch)
        XCTAssertEqual(thirdClose, 0, "Subsequent close() should return 0 (false)")
    }

    // MARK: - Cancellation-Aware Send/Receive

    func testSendWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- send would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Send with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no receiver is waiting).
        let result = kk_channel_send(ch, 42, contInt)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1,
                       "send() with cancelled continuation should return the closed sentinel")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    func testReceiveWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- receive would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Receive with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no sender is waiting).
        let result = kk_channel_receive(ch, contInt)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1,
                       "receive() with cancelled continuation should return the closed sentinel")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    func testSendWithZeroContinuationStillWorks() {
        // Verify backward compatibility: continuation == 0 means no cancellation check.
        let ch = kk_channel_create(1) // buffered -- send won't block

        let result = kk_channel_send(ch, 42, 0)
        XCTAssertEqual(result, 42, "send() with zero continuation should succeed normally")

        let received = kk_channel_receive(ch, 0)
        XCTAssertEqual(received, 42)

        _ = kk_channel_close(ch)
    }

    // MARK: - cancelAllWaiters

    func testCancelAllWaitersWakesSuspendedSenders() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let sendDone = XCTestExpectation(description: "send wakes on cancel")
        nonisolated(unsafe) var sendResult = 0

        DispatchQueue.global().async {
            sendResult = ch.send(42)
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel all waiters.
        ch.cancelAllWaiters()

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(sendResult), 1,
            "Cancelled sender should get the closed sentinel"
        )
    }

    func testCancelAllWaitersWakesSuspendedReceivers() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let recvDone = XCTestExpectation(description: "receive wakes on cancel")
        nonisolated(unsafe) var recvResult = 0

        DispatchQueue.global().async {
            recvResult = ch.receive()
            recvDone.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel all waiters.
        ch.cancelAllWaiters()

        wait(for: [recvDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(recvResult), 1,
            "Cancelled receiver should get the closed sentinel"
        )
    }
}
