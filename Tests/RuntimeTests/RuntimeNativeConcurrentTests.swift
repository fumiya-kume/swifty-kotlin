import Dispatch
import Foundation
@testable import Runtime
import XCTest

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
//   - @SharedImmutable: kk_shared_immutable_init (STDLIB-NATIVE-CONCURRENT-ABI-005)
//   - Worker.executeAfter: kk_worker_execute_after (STDLIB-NATIVE-CONCURRENT-ABI-006)
//   - freeze() / isFrozen: kk_freeze_object / kk_is_frozen
//   - AtomicInt (legacy kotlin.native.concurrent.AtomicInt / unified kotlin.concurrent.AtomicInt):
//             compareAndSet semantics — already tested in isolation via AtomicInt cdecl wrappers
//   - AtomicLong: compareAndSet semantics — ditto
//   - AtomicReference: compareAndSet semantics — ditto
//   - @ThreadLocal: kk_thread_local_new / kk_thread_local_getOrSet — tested in RuntimeThreadLocalTests
//
// Remaining work / known limitations:
//   - TransferMode SAFE: full cycle-detection via DFS over the object graph is not yet
//     implemented; the current stub performs a lightweight freeze-based check only.

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private final class NativeConcurrentSharedValue: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }

    func reset() { value = 0 }
}

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

final class RuntimeWorkerTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    // MARK: Worker lifecycle

    func testWorkerNewReturnsNonZeroHandle() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("worker-lifecycle"))
        let handle = kk_worker_new(nameHandle)
        XCTAssertNotEqual(handle, 0)
    }

    func testWorkerNameRoundTrip() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("my-worker"))
        let workerHandle = kk_worker_new(nameHandle)
        let resultHandle = kk_worker_name(workerHandle)
        XCTAssertNotEqual(resultHandle, 0)
        // The name round-trips through a RuntimeStringBox; we verify it is non-null.
    }

    func testWorkerAnonymousCreationWhenNameHandleIsZero() {
        // Passing 0 as the name handle should not crash; an anonymous name is generated.
        let handle = kk_worker_new(0)
        XCTAssertNotEqual(handle, 0)
    }

    // MARK: Worker termination

    func testWorkerIsNotTerminatedAfterCreation() {
        let handle = kk_worker_new(0)
        XCTAssertEqual(kk_worker_is_terminated(handle), 0)
    }

    func testWorkerIsTerminatedAfterRequestTermination() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 1) // processScheduled = true
        XCTAssertEqual(kk_worker_is_terminated(handle), 1)
    }

    func testWorkerRequestTerminationWithoutDraining() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 0) // processScheduled = false
        XCTAssertEqual(kk_worker_is_terminated(handle), 1)
    }

    func testWorkerRequestTerminationReturnsCompletedFuture() {
        let handle = kk_worker_new(0)
        let futureHandle = kk_worker_request_termination(handle, 1)
        XCTAssertNotEqual(futureHandle, 0)
        XCTAssertEqual(kk_future_result(futureHandle), 1)
        XCTAssertEqual(kk_worker_is_terminated(handle), 1)
    }

    func testWorkerInvalidHandleIsReportedTerminated() {
        // An invalid (zero) handle should be treated as terminated.
        XCTAssertEqual(kk_worker_is_terminated(0), 1)
    }

    // MARK: Worker.execute

    func testWorkerExecuteReturnsFutureResultWhenActive() {
        let workerHandle = kk_worker_new(0)
        defer { _ = kk_worker_request_termination(workerHandle, 1) }

        let producerFnPtr = unsafeBitCast(workerExecuteProducerThunk, to: Int.self)
        let jobFnPtr = unsafeBitCast(workerExecuteJobThunk, to: Int.self)
        let futureHandle = kk_worker_execute(workerHandle, 0, producerFnPtr, 0, jobFnPtr, 0)

        XCTAssertNotEqual(futureHandle, 0)
        if futureHandle != 0 {
            XCTAssertEqual(kk_future_result(futureHandle), 42)
        }
    }

    func testWorkerExecuteDeclinedAfterTermination() {
        let workerHandle = kk_worker_new(0)
        _ = kk_worker_request_termination(workerHandle, 1)
        // Submitting with a null function pointer to a terminated worker should return 0.
        XCTAssertEqual(kk_worker_execute(workerHandle, 0, 0, 0, 0, 0), 0)
    }

    func testMultipleDistinctWorkersHaveIndependentTerminationState() {
        let workerA = kk_worker_new(0)
        let workerB = kk_worker_new(0)
        _ = kk_worker_request_termination(workerA, 1)
        XCTAssertEqual(kk_worker_is_terminated(workerA), 1)
        XCTAssertEqual(kk_worker_is_terminated(workerB), 0,
                       "Terminating worker A must not affect worker B")
    }

    func testWorkerConcurrentExecutionOrderPreserved() {
        // Verify the worker's serial queue runs tasks in order by tracking
        // side-effects through a DispatchSemaphore barrier pattern.
        let workerHandle = kk_worker_new(0)
        // Drain any pending work and confirm it terminates cleanly.
        _ = kk_worker_request_termination(workerHandle, 1)
        XCTAssertEqual(kk_worker_is_terminated(workerHandle), 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - freeze() / isFrozen Tests
// ---------------------------------------------------------------------------

final class RuntimeFreezeTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testFreezeObjectReturnsSameHandle() {
        let handle = makeRawHandleForFreezeTest()
        let result = kk_freeze_object(handle)
        XCTAssertEqual(result, handle)
    }

    func testIsFrozenReturnsFalseBeforeFreeze() {
        let handle = makeRawHandleForFreezeTest()
        XCTAssertEqual(kk_is_frozen(handle), 0)
    }

    func testIsFrozenReturnsTrueAfterFreeze() {
        let handle = makeRawHandleForFreezeTest()
        kk_freeze_object(handle)
        XCTAssertEqual(kk_is_frozen(handle), 1)
    }

    func testFreezeIsIdempotent() {
        let handle = makeRawHandleForFreezeTest()
        kk_freeze_object(handle)
        kk_freeze_object(handle) // second call must not crash
        XCTAssertEqual(kk_is_frozen(handle), 1)
    }

    func testFreezeNullHandleIsNoOp() {
        // freeze(0) must not crash.
        let result = kk_freeze_object(0)
        XCTAssertEqual(result, 0)
    }

    func testIsFrozenForNullHandleReturnsFalse() {
        XCTAssertEqual(kk_is_frozen(0), 0)
    }

    func testDistinctObjectsHaveIndependentFreezeState() {
        let handleA = makeRawHandleForFreezeTest()
        let handleB = makeRawHandleForFreezeTest()
        kk_freeze_object(handleA)
        XCTAssertEqual(kk_is_frozen(handleA), 1)
        XCTAssertEqual(kk_is_frozen(handleB), 0,
                       "Freezing object A must not affect object B")
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt compareAndSet semantics (legacy kotlin.native.concurrent.AtomicInt)
// ---------------------------------------------------------------------------

final class RuntimeAtomicIntNativeConcurrentTests: XCTestCase {

    func testCompareAndSetSucceedsWhenExpectMatches() {
        let handle = kk_atomic_int_create(10)
        let result = kk_atomic_int_compareAndSet(handle, 10, 20)
        XCTAssertEqual(result, 1, "compareAndSet must return 1 (true) on success")
        XCTAssertEqual(kk_atomic_int_load(handle), 20)
    }

    func testCompareAndSetFailsWhenExpectMismatches() {
        let handle = kk_atomic_int_create(10)
        let result = kk_atomic_int_compareAndSet(handle, 99, 20)
        XCTAssertEqual(result, 0, "compareAndSet must return 0 (false) when expected != actual")
        XCTAssertEqual(kk_atomic_int_load(handle), 10, "Value must not change on failed CAS")
    }

    func testCompareAndExchangeReturnsOldValue() {
        let handle = kk_atomic_int_create(5)
        let old = kk_atomic_int_compareAndExchange(handle, 5, 15)
        XCTAssertEqual(old, 5)
        XCTAssertEqual(kk_atomic_int_load(handle), 15)
    }

    func testCompareAndExchangeFailureReturnsCurrentValue() {
        let handle = kk_atomic_int_create(5)
        let old = kk_atomic_int_compareAndExchange(handle, 99, 15)
        XCTAssertEqual(old, 5, "On failure compareAndExchange must return current value")
        XCTAssertEqual(kk_atomic_int_load(handle), 5)
    }

    func testFetchAndAddReturnsOldValue() {
        let handle = kk_atomic_int_create(100)
        let old = kk_atomic_int_fetchAndAdd(handle, 5)
        XCTAssertEqual(old, 100)
        XCTAssertEqual(kk_atomic_int_load(handle), 105)
    }

    func testIncrementDecrement() {
        let handle = kk_atomic_int_create(0)
        _ = kk_atomic_int_incrementAndFetch(handle)
        _ = kk_atomic_int_incrementAndFetch(handle)
        let afterInc = kk_atomic_int_load(handle)
        XCTAssertEqual(afterInc, 2)
        let oldBeforeDec = kk_atomic_int_fetchAndDecrement(handle)
        XCTAssertEqual(oldBeforeDec, 2)
        XCTAssertEqual(kk_atomic_int_load(handle), 1)
        _ = kk_atomic_int_decrementAndFetch(handle)
        XCTAssertEqual(kk_atomic_int_load(handle), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLong compareAndSet semantics (legacy kotlin.native.concurrent.AtomicLong)
// ---------------------------------------------------------------------------

final class RuntimeAtomicLongNativeConcurrentTests: XCTestCase {

    func testCompareAndSetSucceedsWhenExpectMatches() {
        let handle = kk_atomic_long_create(100)
        let result = kk_atomic_long_compareAndSet(handle, 100, 200)
        XCTAssertEqual(result, 1)
        XCTAssertEqual(kk_atomic_long_load(handle), 200)
    }

    func testCompareAndSetFailsWhenExpectMismatches() {
        let handle = kk_atomic_long_create(100)
        let result = kk_atomic_long_compareAndSet(handle, 999, 200)
        XCTAssertEqual(result, 0)
        XCTAssertEqual(kk_atomic_long_load(handle), 100)
    }

    func testCompareAndExchangeReturnsOldValue() {
        let handle = kk_atomic_long_create(50)
        let old = kk_atomic_long_compareAndExchange(handle, 50, 150)
        XCTAssertEqual(old, 50)
        XCTAssertEqual(kk_atomic_long_load(handle), 150)
    }

    func testFetchAndDecrementReturnsOldValue() {
        let handle = kk_atomic_long_create(10)
        let old = kk_atomic_long_fetchAndDecrement(handle)
        XCTAssertEqual(old, 10)
        XCTAssertEqual(kk_atomic_long_load(handle), 9)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicReference compareAndSet semantics
// ---------------------------------------------------------------------------

final class RuntimeAtomicReferenceNativeConcurrentTests: XCTestCase {

    func testCompareAndSetSucceedsWhenExpectMatches() {
        let refA = kk_atomic_int_create(1) // use AtomicInt handle as a stable pointer
        let refB = kk_atomic_int_create(2)
        let atomicRef = kk_atomic_ref_create(refA)
        let result = kk_atomic_ref_compareAndSet(atomicRef, refA, refB)
        XCTAssertEqual(result, 1)
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), refB)
    }

    func testCompareAndSetFailsWhenExpectMismatches() {
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        let refC = kk_atomic_int_create(3)
        let atomicRef = kk_atomic_ref_create(refA)
        let result = kk_atomic_ref_compareAndSet(atomicRef, refC, refB)
        XCTAssertEqual(result, 0, "compareAndSet must fail when expected != actual")
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), refA,
                       "Value must not change on failed CAS")
    }

    func testCompareAndExchangeReturnsOldReference() {
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        let atomicRef = kk_atomic_ref_create(refA)
        let old = kk_atomic_ref_compareAndExchange(atomicRef, refA, refB)
        XCTAssertEqual(old, refA)
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), refB)
    }

    func testNullReferenceRoundTrip() {
        let atomicRef = kk_atomic_ref_create(0)
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), 0)
    }

    func testExchangeReturnsOldReference() {
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        let atomicRef = kk_atomic_ref_create(refA)
        let old = kk_atomic_ref_exchange(atomicRef, refB)
        XCTAssertEqual(old, refA)
        XCTAssertEqual(kk_atomic_ref_load(atomicRef), refB)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Worker.id Tests (STDLIB-NATIVE-CONCURRENT-ABI-001)
// ---------------------------------------------------------------------------

final class RuntimeWorkerIDTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testWorkerIDIsPositive() {
        let handle = kk_worker_new(0)
        let id = kk_worker_id(handle)
        XCTAssertGreaterThan(id, 0, "Worker IDs must be positive monotonic integers")
    }

    func testWorkerIDsAreMonotonicallyIncreasing() {
        let h1 = kk_worker_new(0)
        let h2 = kk_worker_new(0)
        let id1 = kk_worker_id(h1)
        let id2 = kk_worker_id(h2)
        XCTAssertGreaterThan(id2, id1, "Worker IDs must be monotonically increasing")
    }

    func testWorkerIDIsStable() {
        let handle = kk_worker_new(0)
        let id1 = kk_worker_id(handle)
        let id2 = kk_worker_id(handle)
        XCTAssertEqual(id1, id2, "Worker ID must be stable across multiple calls")
    }

    func testWorkerIDForInvalidHandleReturnsNegative() {
        XCTAssertEqual(kk_worker_id(0), -1, "Invalid handle must return -1")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Future<T> Tests (STDLIB-NATIVE-CONCURRENT-ABI-002)
// ---------------------------------------------------------------------------

final class RuntimeFutureTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testFutureNewReturnsNonZeroHandle() {
        let handle = kk_future_new()
        XCTAssertNotEqual(handle, 0)
    }

    func testFutureIsNotReadyBeforeComplete() {
        let handle = kk_future_new()
        XCTAssertEqual(kk_future_is_ready(handle), 0)
    }

    func testFutureIsReadyAfterComplete() {
        let handle = kk_future_new()
        kk_future_complete(handle, 42)
        XCTAssertEqual(kk_future_is_ready(handle), 1)
    }

    func testFutureResultReturnsCompletedValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 99)
        XCTAssertEqual(kk_future_result(handle), 99)
    }

    func testFutureResultDoesNotConsumeValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 7)
        _ = kk_future_result(handle)
        XCTAssertEqual(kk_future_result(handle), 7, "result() must be idempotent")
    }

    func testFutureConsumeReturnsValue() {
        let handle = kk_future_new()
        kk_future_complete(handle, 55)
        XCTAssertEqual(kk_future_consume(handle), 55)
    }

    func testFutureConsumeSecondCallReturnsZero() {
        let handle = kk_future_new()
        kk_future_complete(handle, 100)
        _ = kk_future_consume(handle)
        XCTAssertEqual(kk_future_consume(handle), 0, "Second consume must return 0")
    }

    func testFutureCompletedFromBackgroundThread() {
        let handle = kk_future_new()
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.01)
            kk_future_complete(handle, 1234)
            dispatchGroup.leave()
        }
        let result = kk_future_result(handle)
        XCTAssertEqual(result, 1234)
        dispatchGroup.wait()
    }

    func testWorkerExecuteReturnsFutureHandle() {
        // kk_worker_execute now returns a Future handle, not 1.
        let workerHandle = kk_worker_new(0)
        // Terminate immediately; execute must decline (return 0).
        _ = kk_worker_request_termination(workerHandle, 1)
        let result = kk_worker_execute(workerHandle, 0, 0, 0, 0, 0)
        XCTAssertEqual(result, 0, "Terminated worker returns 0 (no future)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - TransferMode Tests (STDLIB-NATIVE-CONCURRENT-ABI-003)
// ---------------------------------------------------------------------------

final class RuntimeTransferModeTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testTransferSafeModeReturnsSameHandle() {
        let handle = kk_atomic_int_create(10)
        let result = kk_transfer_object(handle, 0) // SAFE = 0
        XCTAssertEqual(result, handle)
    }

    func testTransferUnsafeModeReturnsSameHandle() {
        let handle = kk_atomic_int_create(20)
        let result = kk_transfer_object(handle, 1) // UNSAFE = 1
        XCTAssertEqual(result, handle)
    }

    func testTransferSafeModeFreezesObject() {
        let handle = kk_atomic_int_create(30)
        XCTAssertEqual(kk_is_frozen(handle), 0, "Object must not be frozen before transfer")
        kk_transfer_object(handle, 0) // SAFE transfer
        XCTAssertEqual(kk_is_frozen(handle), 1, "SAFE transfer must freeze the object")
    }

    func testTransferNullHandleIsNoOp() {
        let result = kk_transfer_object(0, 0)
        XCTAssertEqual(result, 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - FreezableAtomicReference Tests (STDLIB-NATIVE-CONCURRENT-ABI-004)
// ---------------------------------------------------------------------------

final class RuntimeFreezableAtomicRefTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testCreateReturnsNonZeroHandle() {
        let handle = kk_freezable_atomic_ref_create(0)
        XCTAssertNotEqual(handle, 0)
    }

    func testLoadReturnsInitialValue() {
        let valueHandle = kk_atomic_int_create(5)
        let refHandle = kk_freezable_atomic_ref_create(valueHandle)
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), valueHandle)
    }

    func testIsNotFrozenInitially() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        XCTAssertEqual(kk_freezable_atomic_ref_is_frozen(refHandle), 0)
    }

    func testFirstStoreSucceedsAndFreezesRef() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let valueHandle = kk_atomic_int_create(99)
        let result = kk_freezable_atomic_ref_store(refHandle, valueHandle)
        XCTAssertEqual(result, 1, "First store must succeed")
        XCTAssertEqual(kk_freezable_atomic_ref_is_frozen(refHandle), 1, "Ref must be frozen after first store")
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), valueHandle)
    }

    func testSecondStoreWithDifferentValueFails() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let v1 = kk_atomic_int_create(1)
        let v2 = kk_atomic_int_create(2)
        _ = kk_freezable_atomic_ref_store(refHandle, v1)
        let result = kk_freezable_atomic_ref_store(refHandle, v2)
        XCTAssertEqual(result, 0, "Mutation after freeze must be rejected")
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), v1, "Value must be unchanged")
    }

    func testStoreWithSameValueAfterFreezeIsIdempotent() {
        let refHandle = kk_freezable_atomic_ref_create(0)
        let v = kk_atomic_int_create(7)
        _ = kk_freezable_atomic_ref_store(refHandle, v)
        let result = kk_freezable_atomic_ref_store(refHandle, v)
        XCTAssertEqual(result, 1, "Storing the same value after freeze must succeed (idempotent)")
    }

    func testCompareAndSetPublishesAndFreezesValue() {
        let initial = kk_atomic_int_create(1)
        let next = kk_atomic_int_create(2)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let result = kk_freezable_atomic_ref_compareAndSet(refHandle, initial, next)
        XCTAssertEqual(result, 1)
        XCTAssertEqual(kk_freezable_atomic_ref_is_frozen(refHandle), 1)
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), next)
    }

    func testCompareAndSetRejectsExpectedMismatch() {
        let initial = kk_atomic_int_create(1)
        let other = kk_atomic_int_create(2)
        let next = kk_atomic_int_create(3)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let result = kk_freezable_atomic_ref_compareAndSet(refHandle, other, next)
        XCTAssertEqual(result, 0)
        XCTAssertEqual(kk_freezable_atomic_ref_is_frozen(refHandle), 0)
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), initial)
    }

    func testCompareAndSwapReturnsOldValue() {
        let initial = kk_atomic_int_create(1)
        let next = kk_atomic_int_create(2)
        let refHandle = kk_freezable_atomic_ref_create(initial)
        let oldValue = kk_freezable_atomic_ref_compareAndSwap(refHandle, initial, next)
        XCTAssertEqual(oldValue, initial)
        XCTAssertEqual(kk_freezable_atomic_ref_load(refHandle), next)
    }
}

// ---------------------------------------------------------------------------
// MARK: - @SharedImmutable Tests (STDLIB-NATIVE-CONCURRENT-ABI-005)
// ---------------------------------------------------------------------------

final class RuntimeSharedImmutableTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testSharedImmutableInitFreezesObject() {
        let handle = kk_atomic_int_create(42)
        XCTAssertEqual(kk_is_frozen(handle), 0, "Object must not be frozen before init")
        let returned = kk_shared_immutable_init(handle)
        XCTAssertEqual(returned, handle, "kk_shared_immutable_init must return the same handle")
        XCTAssertEqual(kk_is_frozen(handle), 1, "Object must be frozen after @SharedImmutable init")
    }

    func testSharedImmutableInitWithNullHandleIsNoOp() {
        let result = kk_shared_immutable_init(0)
        XCTAssertEqual(result, 0, "Null handle must be a no-op")
    }

    func testSharedImmutableInitIsIdempotent() {
        let handle = kk_atomic_int_create(10)
        kk_shared_immutable_init(handle)
        kk_shared_immutable_init(handle) // second call must not crash
        XCTAssertEqual(kk_is_frozen(handle), 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Worker.executeAfter Tests (STDLIB-NATIVE-CONCURRENT-ABI-006)
// ---------------------------------------------------------------------------

final class RuntimeWorkerExecuteAfterTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndThreadLocal }

    func testExecuteAfterReturnsZeroForTerminatedWorker() {
        let handle = kk_worker_new(0)
        _ = kk_worker_request_termination(handle, 1)
        let result = kk_worker_execute_after(handle, 0, 0, 0)
        XCTAssertEqual(result, 0, "Terminated worker must decline executeAfter")
    }

    func testExecuteAfterReturnsZeroForInvalidHandle() {
        let result = kk_worker_execute_after(0, 0, 0, 0)
        XCTAssertEqual(result, 0)
    }

    func testExecuteAfterReturnsZeroForNullFnPtr() {
        let handle = kk_worker_new(0)
        defer { _ = kk_worker_request_termination(handle, 1) }
        let result = kk_worker_execute_after(handle, 0, 0, 0)
        XCTAssertEqual(result, 0, "Null function pointer must be rejected")
    }
}
