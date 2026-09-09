import Foundation
@testable import Runtime
import Testing

private let nativeConcurrentTopLevelJob: @convention(c) (Int) -> Int = { value in
    value + 7
}

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeNativeConcurrentTopLevelTests {
    @Test
    func detachedGraphBridgeRoundTripsTheManagedReference() {
        let value = registerRuntimeObject(RuntimeStringBox("graph"))
        let token = __kk_native_concurrent_detach_object_graph(0, value)

        #expect(token == value)
        #expect(__kk_native_concurrent_attach_object_graph(token) == value)
    }

    @Test
    func consumeFutureBridgeIsOneShot() {
        let future = kk_future_new()
        _ = kk_future_complete(future, 42)

        #expect(__kk_native_concurrent_consume_future(future) == 42)
        #expect(__kk_native_concurrent_consume_future(future) == 0)
    }

    @Test
    func executeImplBridgeRunsTheJobOnTheWorker() {
        let worker = __kk_native_concurrent_start_worker(1, 0)
        defer { _ = __kk_native_concurrent_terminate_worker(worker) }
        let address = unsafeBitCast(nativeConcurrentTopLevelJob, to: Int.self)
        let job = kk_cpointer_new(address)

        let future = __kk_native_concurrent_execute_impl(worker, 0, 35, job)

        #expect(future != 0)
        #expect(kk_future_result(future) == 42)
    }

    @Test
    func waitForMultipleFuturesReturnsOnlyConsumableFutures() throws {
        let pending = kk_future_new()
        let ready = kk_future_new()
        _ = kk_future_complete(ready, 9)
        let futures = registerRuntimeObject(RuntimeListBox(elements: [pending, ready]))

        let result = __kk_native_concurrent_wait_for_multiple_futures(futures, 25)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: result))
        let set = try #require(tryCast(pointer, to: RuntimeSetBox.self))

        #expect(set.elements == [ready])

        _ = __kk_native_concurrent_consume_future(ready)
        let afterConsume = __kk_native_concurrent_wait_for_multiple_futures(futures, 0)
        let afterConsumePointer = try #require(UnsafeMutableRawPointer(bitPattern: afterConsume))
        let emptySet = try #require(tryCast(afterConsumePointer, to: RuntimeSetBox.self))
        #expect(emptySet.elements.isEmpty)
    }

    @Test
    func workerLifecycleBridgesTerminateAndWait() {
        let name = registerRuntimeObject(RuntimeStringBox("top-level-worker"))
        let worker = __kk_native_concurrent_start_worker(1, name)
        #expect(worker != 0)
        #expect(kk_worker_is_terminated(worker) == 0)

        _ = __kk_native_concurrent_terminate_worker(worker)
        _ = __kk_native_concurrent_wait_worker_termination(worker)

        #expect(kk_worker_is_terminated(worker) == 1)
    }
}
