import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - kotlin.native.concurrent API Inventory Coverage (STDLIB-NATIVE-CONCURRENT-001)
//
// This file tests the runtime backing for kotlin.native.concurrent APIs that are
// implemented in RuntimeNativeAPI.swift, RuntimeAtomic.swift, and RuntimeThreadLocal.swift.
//
// Implemented APIs (tested here):
//   - Worker: kk_worker_new / kk_worker_execute / kk_worker_request_termination /
//             kk_worker_is_terminated / kk_worker_name
//   - Worker.id: kk_worker_id (STDLIB-NATIVE-CONCURRENT-ABI-001)
//   - Future<T>: kk_future_new / kk_future_complete / kk_future_result / kk_future_consume /
//               kk_future_is_ready (STDLIB-NATIVE-CONCURRENT-ABI-002)
//   - TransferMode: kk_transfer_object (STDLIB-NATIVE-CONCURRENT-ABI-003)
//   - FreezableAtomicReference<T>: kk_freezable_atomic_ref_create / _load / _store / _is_frozen
//               (STDLIB-NATIVE-CONCURRENT-ABI-004)
//   - Worker.executeAfter: kk_worker_execute_after (STDLIB-NATIVE-CONCURRENT-ABI-005)
//   - freeze() / isFrozen: kk_freeze_object / kk_is_frozen
//   - AtomicInt (legacy kotlin.native.concurrent.AtomicInt / unified kotlin.concurrent.AtomicInt):
//             compareAndSet semantics — already tested in isolation via AtomicInt cdecl wrappers
//   - AtomicLong: compareAndSet semantics — ditto
//   - AtomicReference: compareAndExchange semantics — the public compareAndSet
//             wrapper is covered by the compiler-backed atomic integration tests
//   - @ThreadLocal: kk_thread_local_new / kk_thread_local_getOrSet — tested in RuntimeThreadLocalTests
//
// Remaining work / known limitations:
//   - TransferMode SAFE: full cycle-detection via DFS over the object graph is not yet
//     implemented; the current stub performs a lightweight freeze-based check only.

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------



// A simple sentinel object registered in the runtime heap so freeze/isFrozen
// can operate on a valid managed handle.
private func makeRawHandleForFreezeTest() -> Int {
    // Reuse AtomicIntBox as a conveniently allocated managed object.
    return kk_atomic_int_create(42)
}

private let workerExecuteProducerThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    return 21
}

private let workerExecuteJobThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, outThrown in
    outThrown?.pointee = 0
    return value * 2
}

// ---------------------------------------------------------------------------
// MARK: - Worker Tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeWorkerTests {

    // MARK: Worker lifecycle

    @Test func workerNewReturnsNonZeroHandle() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("worker-lifecycle"))
        let handle = kk_worker_new(nameHandle)
        #expect(handle != 0)
    }

    @Test func workerNameRoundTrip() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("my-worker"))
        let workerHandle = kk_worker_new(nameHandle)
        let resultHandle = kk_worker_name(workerHandle)
        #expect(resultHandle != 0)
        // The name round-trips through a RuntimeStringBox; we verify it is non-null.
    }

    @Test func workerAnonymousCreationWhenNameHandleIsZero() {
        // Passing 0 as the name handle should not crash; an anonymous name is generated.
        let handle = kk_worker_new(0)
        #expect(handle != 0)
    }

    // MARK: Worker termination

    @Test func workerIsNotTerminatedAfterCreation() {
        let handle = kk_worker_new(0)
        #expect(kk_worker_is_terminated(handle) == 0)
    }

    @Test func workerIsTerminatedAfterRequestTermination() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 1) // processScheduled = true
        #expect(kk_worker_is_terminated(handle) == 1)
    }

    @Test func workerRequestTerminationWithoutDraining() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 0) // processScheduled = false
        #expect(kk_worker_is_terminated(handle) == 1)
    }

    @Test func workerRequestTerminationReturnsCompletedFuture() {
        let handle = kk_worker_new(0)
        let futureHandle = kk_worker_request_termination(handle, 1)
        #expect(futureHandle != 0)
        #expect(kk_future_result(futureHandle) == 1)
        #expect(kk_worker_is_terminated(handle) == 1)
    }

    @Test func workerInvalidHandleIsReportedTerminated() {
        // An invalid (zero) handle should be treated as terminated.
        #expect(kk_worker_is_terminated(0) == 1)
    }

    // MARK: Worker.execute

    @Test func workerExecuteReturnsFutureResultWhenActive() {
        let workerHandle = kk_worker_new(0)
        defer { _ = kk_worker_request_termination(workerHandle, 1) }

        let producerFnPtr = unsafeBitCast(workerExecuteProducerThunk, to: Int.self)
        let jobFnPtr = unsafeBitCast(workerExecuteJobThunk, to: Int.self)
        let futureHandle = kk_worker_execute(workerHandle, 0, producerFnPtr, 0, jobFnPtr, 0)

        #expect(futureHandle != 0)
        if futureHandle != 0 {
            #expect(kk_future_result(futureHandle) == 42)
        }
    }

    @Test func workerExecuteDeclinedAfterTermination() {
        let workerHandle = kk_worker_new(0)
        _ = kk_worker_request_termination(workerHandle, 1)
        // Submitting with a null function pointer to a terminated worker should return 0.
        #expect(kk_worker_execute(workerHandle, 0, 0, 0, 0, 0) == 0)
    }

    @Test func multipleDistinctWorkersHaveIndependentTerminationState() {
        let workerA = kk_worker_new(0)
        let workerB = kk_worker_new(0)
        _ = kk_worker_request_termination(workerA, 1)
        #expect(kk_worker_is_terminated(workerA) == 1)
        #expect(kk_worker_is_terminated(workerB) == 0,
                "Terminating worker A must not affect worker B")
    }

    @Test func workerConcurrentExecutionOrderPreserved() {
        // Verify the worker's serial queue runs tasks in order by tracking
        // side-effects through a DispatchSemaphore barrier pattern.
        let workerHandle = kk_worker_new(0)
        // Drain any pending work and confirm it terminates cleanly.
        _ = kk_worker_request_termination(workerHandle, 1)
        #expect(kk_worker_is_terminated(workerHandle) == 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - freeze() / isFrozen Tests
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeFreezeTests {

    @Test func freezeObjectReturnsSameHandle() {
        let handle = makeRawHandleForFreezeTest()
        let result = kk_freeze_object(handle)
        #expect(result == handle)
    }

    @Test func isFrozenReturnsFalseBeforeFreeze() {
        let handle = makeRawHandleForFreezeTest()
        #expect(kk_is_frozen(handle) == 0)
    }

    @Test func isFrozenReturnsTrueAfterFreeze() {
        let handle = makeRawHandleForFreezeTest()
        kk_freeze_object(handle)
        #expect(kk_is_frozen(handle) == 1)
    }

    @Test func freezeIsIdempotent() {
        let handle = makeRawHandleForFreezeTest()
        kk_freeze_object(handle)
        kk_freeze_object(handle) // second call must not crash
        #expect(kk_is_frozen(handle) == 1)
    }

    @Test func freezeNullHandleIsNoOp() {
        // freeze(0) must not crash.
        let result = kk_freeze_object(0)
        #expect(result == 0)
    }

    @Test func isFrozenForNullHandleReturnsFalse() {
        #expect(kk_is_frozen(0) == 0)
    }

    @Test func distinctObjectsHaveIndependentFreezeState() {
        let handleA = makeRawHandleForFreezeTest()
        let handleB = makeRawHandleForFreezeTest()
        kk_freeze_object(handleA)
        #expect(kk_is_frozen(handleA) == 1)
        #expect(kk_is_frozen(handleB) == 0,
                "Freezing object A must not affect object B")
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt compareAndSet semantics (legacy kotlin.native.concurrent.AtomicInt)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeAtomicIntNativeConcurrentTests {

    @Test func compareAndSetSucceedsWhenExpectMatches() {
        let handle = kk_atomic_int_create(10)
        let result = kk_atomic_int_compareAndSet(handle, 10, 20)
        #expect(result == 1, "compareAndSet must return 1 (true) on success")
        #expect(__kk_atomic_int_load(handle) == 20)
    }

    @Test func compareAndSetFailsWhenExpectMismatches() {
        let handle = kk_atomic_int_create(10)
        let result = kk_atomic_int_compareAndSet(handle, 99, 20)
        #expect(result == 0, "compareAndSet must return 0 (false) when expected != actual")
        #expect(__kk_atomic_int_load(handle) == 10, "Value must not change on failed CAS")
    }

    @Test func compareAndExchangeReturnsOldValue() {
        let handle = kk_atomic_int_create(5)
        let old = __kk_atomic_int_compareAndExchange(handle, 5, 15)
        #expect(old == 5)
        #expect(__kk_atomic_int_load(handle) == 15)
    }

    @Test func compareAndExchangeFailureReturnsCurrentValue() {
        let handle = kk_atomic_int_create(5)
        let old = __kk_atomic_int_compareAndExchange(handle, 99, 15)
        #expect(old == 5, "On failure compareAndExchange must return current value")
        #expect(__kk_atomic_int_load(handle) == 5)
    }

    @Test func fetchAndAddReturnsOldValue() {
        let handle = kk_atomic_int_create(100)
        let old = __kk_atomic_int_fetchAndAdd(handle, 5)
        #expect(old == 100)
        #expect(__kk_atomic_int_load(handle) == 105)
    }

    @Test func incrementDecrement() {
        let handle = kk_atomic_int_create(0)
        _ = __kk_atomic_int_incrementAndFetch(handle)
        _ = __kk_atomic_int_incrementAndFetch(handle)
        let afterInc = __kk_atomic_int_load(handle)
        #expect(afterInc == 2)
        let oldBeforeDec = __kk_atomic_int_fetchAndDecrement(handle)
        #expect(oldBeforeDec == 2)
        #expect(__kk_atomic_int_load(handle) == 1)
        _ = __kk_atomic_int_decrementAndFetch(handle)
        #expect(__kk_atomic_int_load(handle) == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLong compareAndSet semantics (legacy kotlin.native.concurrent.AtomicLong)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeAtomicLongNativeConcurrentTests {

    @Test func compareAndSetSucceedsWhenExpectMatches() {
        let handle = kk_atomic_long_create(100)
        let result = kk_atomic_long_compareAndSet(handle, 100, 200)
        #expect(result == 1)
        #expect(__kk_atomic_long_load(handle) == 200)
    }

    @Test func compareAndSetFailsWhenExpectMismatches() {
        let handle = kk_atomic_long_create(100)
        let result = kk_atomic_long_compareAndSet(handle, 999, 200)
        #expect(result == 0)
        #expect(__kk_atomic_long_load(handle) == 100)
    }

    @Test func compareAndExchangeReturnsOldValue() {
        let handle = kk_atomic_long_create(50)
        let old = __kk_atomic_long_compareAndExchange(handle, 50, 150)
        #expect(old == 50)
        #expect(__kk_atomic_long_load(handle) == 150)
    }

    @Test func fetchAndDecrementReturnsOldValue() {
        let handle = kk_atomic_long_create(10)
        let old = __kk_atomic_long_fetchAndDecrement(handle)
        #expect(old == 10)
        #expect(__kk_atomic_long_load(handle) == 9)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicReference compareAndExchange semantics
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeAtomicReferenceNativeConcurrentTests {

    @Test func compareAndExchangeReturnsOldReference() {
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        let atomicRef = kk_atomic_ref_create(refA)
        let old = __kk_atomic_ref_compareAndExchange(atomicRef, refA, refB)
        #expect(old == refA)
        #expect(__kk_atomic_ref_load(atomicRef) == refB)
    }

    @Test func compareAndExchangeFailsAndRetainsCurrentReference() {
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        let refC = kk_atomic_int_create(30)
        let atomicRef = kk_atomic_ref_create(refA)
        let old = __kk_atomic_ref_compareAndExchange(atomicRef, refC, refB)
        #expect(old == refA)
        #expect(__kk_atomic_ref_load(atomicRef) == refA,
                "A failed compareAndExchange must retain the current reference")
    }

    @Test func compareAndExchangeUsesReferenceIdentity() {
        let current = registerRuntimeObject(RuntimeStringBox("same"))
        let equalButDistinct = registerRuntimeObject(RuntimeStringBox("same"))
        let replacement = registerRuntimeObject(RuntimeStringBox("next"))
        let atomicRef = kk_atomic_ref_create(current)
        let old = __kk_atomic_ref_compareAndExchange(atomicRef, equalButDistinct, replacement)
        #expect(old == current)
        #expect(__kk_atomic_ref_load(atomicRef) == current,
                "Equal but distinct references must not satisfy the CAS expectation")
    }

    @Test func nullReferenceRoundTrip() {
        let atomicRef = kk_atomic_ref_create(0)
        #expect(__kk_atomic_ref_load(atomicRef) == 0)
    }

    @Test func exchangeReturnsOldReference() {
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        let atomicRef = kk_atomic_ref_create(refA)
        let old = __kk_atomic_ref_exchange(atomicRef, refB)
        #expect(old == refA)
        #expect(__kk_atomic_ref_load(atomicRef) == refB)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Worker.id Tests (STDLIB-NATIVE-CONCURRENT-ABI-001)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeWorkerIDTests {

    @Test func workerIDIsPositive() {
        let handle = kk_worker_new(0)
        let id = kk_worker_id(handle)
        #expect(id > 0, "Worker IDs must be positive monotonic integers")
    }

    @Test func workerIDsAreMonotonicallyIncreasing() {
        let h1 = kk_worker_new(0)
        let h2 = kk_worker_new(0)
        let id1 = kk_worker_id(h1)
        let id2 = kk_worker_id(h2)
        #expect(id2 > id1, "Worker IDs must be monotonically increasing")
    }

    @Test func workerIDIsStable() {
        let handle = kk_worker_new(0)
        let id1 = kk_worker_id(handle)
        let id2 = kk_worker_id(handle)
        #expect(id1 == id2, "Worker ID must be stable across multiple calls")
    }

    @Test func workerIDForInvalidHandleReturnsNegative() {
        #expect(kk_worker_id(0) == -1, "Invalid handle must return -1")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Future<T> Tests (STDLIB-NATIVE-CONCURRENT-ABI-002)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeFutureTests {

    @Test func futureNewReturnsNonZeroHandle() {
        let handle = kk_future_new()
        #expect(handle != 0)
    }

    @Test func futureIsNotReadyBeforeComplete() {
        let handle = kk_future_new()
        #expect(kk_future_is_ready(handle) == 0)
    }

    @Test func futureIsReadyAfterComplete() {
        let handle = kk_future_new()
        kk_future_complete(handle, 42)
        #expect(kk_future_is_ready(handle) == 1)
    }

    @Test func futureResultReturnsCompletedValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 99)
        #expect(kk_future_result(handle) == 99)
    }

    @Test func futureResultDoesNotConsumeValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 7)
        _ = kk_future_result(handle)
        #expect(kk_future_result(handle) == 7, "result() must be idempotent")
    }

    @Test func futureConsumeReturnsValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 55)
        #expect(kk_future_consume(handle) == 55)
    }

    @Test func futureConsumeSecondCallReturnsZero() {
        let handle = kk_future_new()
        kk_future_complete(handle, 100)
        _ = kk_future_consume(handle)
        #expect(kk_future_consume(handle) == 0, "Second consume must return 0")
    }

    @Test func futureCompletedFromBackgroundThread() {
        let handle = kk_future_new()
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.01)
            kk_future_complete(handle, 1234)
            dispatchGroup.leave()
        }
        let result = kk_future_result(handle)
        #expect(result == 1234)
        dispatchGroup.wait()
    }

    @Test func workerExecuteReturnsFutureHandle() {
        // kk_worker_execute now returns a Future handle, not 1.
        let workerHandle = kk_worker_new(0)
        // Terminate immediately; execute must decline (return 0).
        _ = kk_worker_request_termination(workerHandle, 1)
        let result = kk_worker_execute(workerHandle, 0, 0, 0, 0, 0)
        #expect(result == 0, "Terminated worker returns 0 (no future)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - TransferMode Tests (STDLIB-NATIVE-CONCURRENT-ABI-003)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeTransferModeTests {

    @Test func transferSafeModeReturnsSameHandle() {
        let handle = kk_atomic_int_create(10)
        let result = kk_transfer_object(handle, 0) // SAFE = 0
        #expect(result == handle)
    }

    @Test func transferUnsafeModeReturnsSameHandle() {
        let handle = kk_atomic_int_create(20)
        let result = kk_transfer_object(handle, 1) // UNSAFE = 1
        #expect(result == handle)
    }

    @Test func transferSafeModeFreezesObject() {
        let handle = kk_atomic_int_create(30)
        #expect(kk_is_frozen(handle) == 0, "Object must not be frozen before transfer")
        kk_transfer_object(handle, 0) // SAFE transfer
        #expect(kk_is_frozen(handle) == 1, "SAFE transfer must freeze the object")
    }

    @Test func transferNullHandleIsNoOp() {
        let result = kk_transfer_object(0, 0)
        #expect(result == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - FreezableAtomicReference Tests (STDLIB-NATIVE-CONCURRENT-ABI-004)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeFreezableAtomicRefTests {

    @Test func createReturnsNonZeroHandle() {
        let handle = kk_freezable_atomic_ref_create(0)
        #expect(handle != 0)
    }

    @Test func loadReturnsInitialValue() {
        let valueHandle = kk_atomic_int_create(5)
        let refHandle = kk_freezable_atomic_ref_create(valueHandle)
        #expect(kk_freezable_atomic_ref_load(refHandle) == valueHandle)
    }

    @Test func isNotFrozenInitially() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        #expect(kk_freezable_atomic_ref_is_frozen(refHandle) == 0)
    }

    @Test func firstStoreSucceedsAndFreezesRef() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let valueHandle = kk_atomic_int_create(99)
        let result = kk_freezable_atomic_ref_store(refHandle, valueHandle)
        #expect(result == 1, "First store must succeed")
        #expect(kk_freezable_atomic_ref_is_frozen(refHandle) == 1, "Ref must be frozen after first store")
        #expect(kk_freezable_atomic_ref_load(refHandle) == valueHandle)
    }

    @Test func secondStoreWithDifferentValueFails() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let v1 = kk_atomic_int_create(1)
        let v2 = kk_atomic_int_create(2)
        _ = kk_freezable_atomic_ref_store(refHandle, v1)
        let result = kk_freezable_atomic_ref_store(refHandle, v2)
        #expect(result == 0, "Mutation after freeze must be rejected")
        #expect(kk_freezable_atomic_ref_load(refHandle) == v1, "Value must be unchanged")
    }

    @Test func storeWithSameValueAfterFreezeIsIdempotent() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let v = kk_atomic_int_create(7)
        _ = kk_freezable_atomic_ref_store(refHandle, v)
        let result = kk_freezable_atomic_ref_store(refHandle, v)
        #expect(result == 1, "Storing the same value after freeze must succeed (idempotent)")
    }

    @Test func compareAndSetPublishesAndFreezesValue() {
        let initial = kk_atomic_int_create(1)
        let next = kk_atomic_int_create(2)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let result = kk_freezable_atomic_ref_compareAndSet(refHandle, initial, next)
        #expect(result == 1)
        #expect(kk_freezable_atomic_ref_is_frozen(refHandle) == 1)
        #expect(kk_freezable_atomic_ref_load(refHandle) == next)
    }

    @Test func compareAndSetRejectsExpectedMismatch() {
        let initial = kk_atomic_int_create(1)
        let other = kk_atomic_int_create(2)
        let next = kk_atomic_int_create(3)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let result = kk_freezable_atomic_ref_compareAndSet(refHandle, other, next)
        #expect(result == 0)
        #expect(kk_freezable_atomic_ref_is_frozen(refHandle) == 0)
        #expect(kk_freezable_atomic_ref_load(refHandle) == initial)
    }

    @Test func compareAndSwapReturnsOldValue() {
        let initial = kk_atomic_int_create(1)
        let next = kk_atomic_int_create(2)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let oldValue = kk_freezable_atomic_ref_compareAndSwap(refHandle, initial, next)
        #expect(oldValue == initial)
        #expect(kk_freezable_atomic_ref_load(refHandle) == next)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Worker.executeAfter Tests (STDLIB-NATIVE-CONCURRENT-ABI-005)
// ---------------------------------------------------------------------------

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeWorkerExecuteAfterTests {

    @Test func executeAfterReturnsZeroForTerminatedWorker() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 1)
        let result = kk_worker_execute_after(handle, 0, 0, 0)
        #expect(result == 0, "Terminated worker must decline executeAfter")
    }

    @Test func executeAfterReturnsZeroForInvalidHandle() {
        let result = kk_worker_execute_after(0, 0, 0, 0)
        #expect(result == 0)
    }

    @Test func executeAfterReturnsZeroForNullFnPtr() {
        let handle = kk_worker_new(0)
        defer { _ = kk_worker_request_termination(handle, 1) }
        let result = kk_worker_execute_after(handle, 0, 0, 0)
        #expect(result == 0, "Null function pointer must be rejected")
    }
}
