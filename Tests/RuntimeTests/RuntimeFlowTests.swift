import Foundation
@testable import Runtime
import XCTest

private typealias RuntimeFlowEmitterEntry = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
/// Non-suspend collector ABI: (closureRaw, value, outThrown)
private typealias RuntimeFlowCollectorEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
/// Map/filter ABI: (closureRaw, elem, outThrown)
private typealias RuntimeFlowUnaryEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int

private enum RuntimeFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case onEach = 4
    case distinctUntilChanged = 5
}

private final class RuntimeFlowTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var collectedValues: [Int] = []
    private var mapCallCount = 0
    private var filterCallCount = 0
    private var collectorCallCount = 0
    private var emitCallCount = 0

    func reset() {
        lock.lock()
        collectedValues.removeAll(keepingCapacity: true)
        mapCallCount = 0
        filterCallCount = 0
        collectorCallCount = 0
        emitCallCount = 0
        lock.unlock()
    }

    func recordEmitCall() {
        lock.lock()
        emitCallCount += 1
        lock.unlock()
    }

    func recordMapCall() {
        lock.lock()
        mapCallCount += 1
        lock.unlock()
    }

    func recordFilterCall() {
        lock.lock()
        filterCallCount += 1
        lock.unlock()
    }

    @discardableResult
    func recordCollectorValue(_ value: Int) -> Int {
        lock.lock()
        collectorCallCount += 1
        collectedValues.append(value)
        let count = collectorCallCount
        lock.unlock()
        return count
    }

    func snapshot() -> (values: [Int], mapCalls: Int, filterCalls: Int, collectorCalls: Int, emitCalls: Int) {
        lock.lock()
        let snapshot = (values: collectedValues, mapCalls: mapCallCount, filterCalls: filterCallCount, collectorCalls: collectorCallCount, emitCalls: emitCallCount)
        lock.unlock()
        return snapshot
    }
}

private let runtimeFlowTestState = RuntimeFlowTestState()

@_cdecl("runtime_test_flow_emitter_values_1_2_3_4")
func runtime_test_flow_emitter_values_1_2_3_4(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let sentinel = kk_flow_stopped()
    for value in 1 ... 4 {
        runtimeFlowTestState.recordEmitCall()
        let result = kk_flow_emit(0, value, RuntimeFlowTag.emit.rawValue)
        if result == sentinel { break }
    }
    return 0
}

@_cdecl("runtime_test_flow_map_throw_on_two")
func runtime_test_flow_map_throw_on_two(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowTestState.recordMapCall()
    if value == 2 {
        outThrown?.pointee = 1
        return 0
    }
    outThrown?.pointee = 0
    return value
}

@_cdecl("runtime_test_flow_filter_even")
func runtime_test_flow_filter_even(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowTestState.recordFilterCall()
    outThrown?.pointee = 0
    return value % 2 == 0 ? 1 : 0
}

@_cdecl("runtime_test_flow_map_double")
func runtime_test_flow_map_double(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowTestState.recordMapCall()
    outThrown?.pointee = 0
    return value * 2
}

@_cdecl("runtime_test_flow_collect_store")
func runtime_test_flow_collect_store(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = runtimeFlowTestState.recordCollectorValue(value)
    outThrown?.pointee = 0
    return 0
}

@_cdecl("runtime_test_flow_collect_throw_on_first")
func runtime_test_flow_collect_throw_on_first(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let callIndex = runtimeFlowTestState.recordCollectorValue(value)
    if callIndex == 1 {
        outThrown?.pointee = 1
        return 0
    }
    outThrown?.pointee = 0
    return 0
}

/// Emits 10_000 values (1..10000) to simulate a very large / "infinite-ish" source.
/// Records each emit attempt and respects the stop sentinel so the emitter terminates
/// early when the pipeline signals completion (e.g. take(n) exhaustion).
@_cdecl("runtime_test_flow_emitter_large_source")
func runtime_test_flow_emitter_large_source(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let sentinel = kk_flow_stopped()
    for value in 1 ... 10_000 {
        runtimeFlowTestState.recordEmitCall()
        let result = kk_flow_emit(0, value, RuntimeFlowTag.emit.rawValue)
        if result == sentinel { break }
    }
    return 0
}

/// Filter that rejects every element (always returns 0 / false).
@_cdecl("runtime_test_flow_filter_reject_all")
func runtime_test_flow_filter_reject_all(_: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowTestState.recordFilterCall()
    outThrown?.pointee = 0
    return 0
}

final class RuntimeFlowTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        runtimeFlowTestState.reset()
    }

    func testChainedTakeAppliesAllTakeStepsAndResetsPerCollect() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let firstTake = kk_flow_emit(flowHandle, 3, RuntimeFlowTag.take.rawValue)
        let chainedTake = kk_flow_emit(firstTake, 2, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(chainedTake, collectorPtr, 0)
        let snapshot1 = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot1.values, [1, 2], "Both take steps should be applied in a chain.")
        // Emitter should stop after take(2) terminates: 2 delivered + 1 that sees sentinel = 3.
        XCTAssertLessThanOrEqual(snapshot1.emitCalls, 3, "Emitter should stop early after chained take exhaustion.")

        runtimeFlowTestState.reset()
        _ = kk_flow_collect(chainedTake, collectorPtr, 0)
        let snapshot2 = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot2.values, [1, 2], "take counters should reset on each collect.")
        XCTAssertLessThanOrEqual(snapshot2.emitCalls, 3, "Emitter should stop early on re-collect too.")
    }

    func testMapThrowTerminatesFlowAndSkipsSubsequentEmits() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_throw_on_two as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let mapped = kk_flow_emit(flowHandle, mapPtr, RuntimeFlowTag.map.rawValue)
        _ = kk_flow_collect(mapped, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [1], "Values after a thrown map step must not reach collector.")
        XCTAssertEqual(snapshot.mapCalls, 2, "Map should run for values 1 and 2, then terminate.")
        XCTAssertEqual(snapshot.collectorCalls, 1)
        // Emitter should stop early: value 1 ok, value 2 throws -> terminated.
        // Value 3 emitted -> sees stop sentinel and breaks. So emitCalls <= 3.
        XCTAssertLessThanOrEqual(snapshot.emitCalls, 3, "Emitter should stop early after map throw terminates pipeline.")
    }

    func testFilterMapTakePipelinePreservesOrderAndStopsAfterTake() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let filterPtr = unsafeBitCast(runtime_test_flow_filter_even as RuntimeFlowUnaryEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_double as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let filtered = kk_flow_emit(flowHandle, filterPtr, RuntimeFlowTag.filter.rawValue)
        let mapped = kk_flow_emit(filtered, mapPtr, RuntimeFlowTag.map.rawValue)
        let taken = kk_flow_emit(mapped, 1, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(taken, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [4], "filter/map/take pipeline should keep order and stop after one element.")
        // Lazy per-element semantics: only values 1 and 2 are processed (1 is
        // filtered out, 2 passes filter+map and take(1) stops further processing).
        XCTAssertEqual(snapshot.filterCalls, 2, "Filter runs lazily per element; stops after take(1) is satisfied.")
        XCTAssertEqual(snapshot.mapCalls, 1, "Map runs only for the single element that passed filter before take exhausted.")
        XCTAssertEqual(snapshot.collectorCalls, 1)
        // Verify the *source emitter* stops early rather than iterating all 4 elements.
        // Element 1 emitted -> filtered out. Element 2 emitted -> passes filter, map, take(1) delivers and terminates.
        // Element 3 emitted -> sees stop sentinel, emitter breaks. So emitCalls <= 3.
        XCTAssertLessThanOrEqual(snapshot.emitCalls, 3, "Emitter should stop early once take(1) terminates the pipeline.")
    }

    func testCollectorThrowTerminatesFlowAfterFirstCollectedValue() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let throwingCollectorPtr = unsafeBitCast(runtime_test_flow_collect_throw_on_first as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        _ = kk_flow_collect(flowHandle, throwingCollectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [1], "Collector throw should stop subsequent emissions.")
        XCTAssertEqual(snapshot.collectorCalls, 1)
        // Emitter should stop early: value 1 delivered -> collector throws -> terminated.
        // Value 2 emitted -> sees stop sentinel and breaks. So emitCalls <= 2.
        XCTAssertLessThanOrEqual(snapshot.emitCalls, 2, "Emitter should stop early after collector throw terminates pipeline.")
    }

    func testTakeFollowedByRejectAllFilterTerminatesOverLargeSource() {
        // Regression: .take(n) followed by a filter that drops everything must still
        // terminate promptly -- the take counter exhaustion must propagate even when
        // downstream ops drop the element via early return.
        // Also validates that the *source emitter* stops early (important for infinite streams).
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_large_source as RuntimeFlowEmitterEntry, to: Int.self)
        let filterPtr = unsafeBitCast(runtime_test_flow_filter_reject_all as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let taken = kk_flow_emit(flowHandle, 3, RuntimeFlowTag.take.rawValue)
        let filtered = kk_flow_emit(taken, filterPtr, RuntimeFlowTag.filter.rawValue)

        _ = kk_flow_collect(filtered, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        // The filter rejects everything so nothing reaches the collector.
        XCTAssertEqual(snapshot.values, [], "No elements should pass the reject-all filter.")
        // take(3) allows exactly 3 elements through before terminating.
        // The filter runs on each of those 3 elements but rejects them all.
        XCTAssertEqual(snapshot.filterCalls, 3, "Filter should run exactly take(n) times, then pipeline terminates.")
        XCTAssertEqual(snapshot.collectorCalls, 0, "Collector should never be called when filter rejects all.")
        // The emitter should stop after take(3) terminates the pipeline, NOT iterate
        // all 10,000 elements. We allow take(n)+1 emits because the (n+1)th emit is
        // where the emitter observes the stop sentinel.
        XCTAssertLessThanOrEqual(snapshot.emitCalls, 4, "Emitter should stop around take(n) rather than iterating the whole 10,000-element source.")
    }

    func testFlowRetainReleaseKeepsHandleAliveUntilLastRelease() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let retained = kk_flow_retain(flowHandle)
        XCTAssertEqual(retained, flowHandle)

        _ = kk_flow_release(flowHandle)

        runtimeFlowTestState.reset()
        _ = kk_flow_collect(retained, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [1, 2, 3, 4])

        _ = kk_flow_release(retained)

        runtimeFlowTestState.reset()
        _ = kk_flow_collect(retained, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [])
    }

    // MARK: - Cold stream semantics tests (STDLIB-088)

    func testColdStreamReExecutesEmitterOnEachCollect() {
        // Verify emitter runs fresh for every collect call by using a
        // counting emitter that increments a global counter on each invocation.
        runtimeFlowEmitterCallCounter.reset()
        let emitterPtr = unsafeBitCast(runtime_test_flow_counting_emitter as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)

        XCTAssertEqual(runtimeFlowEmitterCallCounter.count, 0, "Emitter should not run before collect.")

        _ = kk_flow_collect(flowHandle, collectorPtr, 0)
        let firstCollect = runtimeFlowTestState.snapshot().values
        XCTAssertEqual(firstCollect, [1, 2, 3, 4])
        XCTAssertEqual(runtimeFlowEmitterCallCounter.count, 1, "Emitter should run exactly once after first collect.")

        runtimeFlowTestState.reset()
        _ = kk_flow_collect(flowHandle, collectorPtr, 0)
        let secondCollect = runtimeFlowTestState.snapshot().values
        XCTAssertEqual(secondCollect, [1, 2, 3, 4], "Cold stream should re-emit on each collect.")
        XCTAssertEqual(runtimeFlowEmitterCallCounter.count, 2, "Emitter should run again on second collect (cold stream).")
    }

    func testLazyMapOnlyProcessesNeededElements() {
        // With take(2), map should only run for the first 2 source elements.
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_double as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let mapped = kk_flow_emit(flowHandle, mapPtr, RuntimeFlowTag.map.rawValue)
        let taken = kk_flow_emit(mapped, 2, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(taken, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [2, 4], "take(2) after map should yield first 2 mapped values.")
        XCTAssertEqual(snapshot.mapCalls, 2, "Lazy: map should only run for the 2 elements before take exhausted.")
    }

    func testOnEachDoesNotTransformValues() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let onEachPtr = unsafeBitCast(runtime_test_flow_map_double as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let withOnEach = kk_flow_emit(flowHandle, onEachPtr, RuntimeFlowTag.onEach.rawValue)

        _ = kk_flow_collect(withOnEach, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        // onEach runs the action but does not change the value.
        XCTAssertEqual(snapshot.values, [1, 2, 3, 4], "onEach should not transform values.")
        XCTAssertEqual(snapshot.mapCalls, 4, "onEach action should run for all elements.")
    }

    func testDistinctUntilChangedFiltersConsecutiveDuplicates() {
        // Emit: 1, 1, 2, 2, 3, 1
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_with_dupes as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let distinct = kk_flow_emit(flowHandle, 0, RuntimeFlowTag.distinctUntilChanged.rawValue)

        _ = kk_flow_collect(distinct, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [1, 2, 3, 1], "distinctUntilChanged should remove consecutive duplicates.")
    }

    func testFlowOfCreatesFlowFromFixedValues() {
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        // Create an array with values [10, 20, 30]
        let arrayHandle = kk_array_new(3)
        kk_array_set(arrayHandle, 0, 10, nil)
        kk_array_set(arrayHandle, 1, 20, nil)
        kk_array_set(arrayHandle, 2, 30, nil)

        let flowHandle = kk_flow_of(arrayHandle, 3)

        _ = kk_flow_collect(flowHandle, collectorPtr, 0)
        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [10, 20, 30], "flowOf should emit the provided values.")

        // Cold stream: collect again should yield same values.
        runtimeFlowTestState.reset()
        _ = kk_flow_collect(flowHandle, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [10, 20, 30], "flowOf cold stream: re-collect yields same values.")
    }

    func testFlowOfWithOperators() {
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_double as RuntimeFlowUnaryEntry, to: Int.self)

        let arrayHandle = kk_array_new(3)
        kk_array_set(arrayHandle, 0, 5, nil)
        kk_array_set(arrayHandle, 1, 10, nil)
        kk_array_set(arrayHandle, 2, 15, nil)

        let flowHandle = kk_flow_of(arrayHandle, 3)
        let mapped = kk_flow_emit(flowHandle, mapPtr, RuntimeFlowTag.map.rawValue)
        let taken = kk_flow_emit(mapped, 2, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(taken, collectorPtr, 0)
        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [10, 20], "flowOf with map+take should work correctly.")
        XCTAssertEqual(snapshot.mapCalls, 2, "Lazy: map should only run for elements before take exhausted.")
    }

    func testFlowFirst() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let flowHandle = kk_flow_create(emitterPtr, 0)
        let result = kk_flow_first(flowHandle, 0)
        XCTAssertEqual(result, 1, "first() should return the first emitted value.")
    }

    func testFlowFirstWithFilter() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let filterPtr = unsafeBitCast(runtime_test_flow_filter_even as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let filtered = kk_flow_emit(flowHandle, filterPtr, RuntimeFlowTag.filter.rawValue)
        let result = kk_flow_first(filtered, 0)
        XCTAssertEqual(result, 2, "first() after filter(even) should return 2.")
    }

    func testFlowCount() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let flowHandle = kk_flow_create(emitterPtr, 0)
        let result = kk_flow_count(flowHandle, 0)
        XCTAssertEqual(result, 4, "count() should return number of emitted elements.")
    }

    func testFlowCountWithFilter() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let filterPtr = unsafeBitCast(runtime_test_flow_filter_even as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let filtered = kk_flow_emit(flowHandle, filterPtr, RuntimeFlowTag.filter.rawValue)
        let result = kk_flow_count(filtered, 0)
        XCTAssertEqual(result, 2, "count() after filter(even) on [1,2,3,4] should return 2.")
    }

    func testFlowToList() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_double as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let mapped = kk_flow_emit(flowHandle, mapPtr, RuntimeFlowTag.map.rawValue)
        let listHandle = kk_flow_to_list(mapped, 0)

        let size = kk_list_size(listHandle)
        XCTAssertEqual(size, 4)
        XCTAssertEqual(kk_list_get(listHandle, 0), 2)
        XCTAssertEqual(kk_list_get(listHandle, 1), 4)
        XCTAssertEqual(kk_list_get(listHandle, 2), 6)
        XCTAssertEqual(kk_list_get(listHandle, 3), 8)
    }

    func testFlowFold() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let foldOpPtr = unsafeBitCast(runtime_test_flow_fold_add as RuntimeFlowFoldEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let result = kk_flow_fold(flowHandle, 0, foldOpPtr, 0)
        XCTAssertEqual(result, 10, "fold with + and initial 0 on [1,2,3,4] should yield 10.")
    }

    func testFlowReduce() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let reduceOpPtr = unsafeBitCast(runtime_test_flow_fold_add as RuntimeFlowFoldEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let result = kk_flow_reduce(flowHandle, reduceOpPtr, 0)
        XCTAssertEqual(result, 10, "reduce with + on [1,2,3,4] should yield 10.")
    }

    func testTakeZeroEmitsNothing() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowCollectorEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let taken = kk_flow_emit(flowHandle, 0, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(taken, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [], "take(0) should emit nothing.")
    }
}

// MARK: - Additional test helpers

/// Thread-safe counter to track how many times an emitter function is invoked.
private final class RuntimeFlowEmitterCallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _count = 0
        lock.unlock()
    }
}

private let runtimeFlowEmitterCallCounter = RuntimeFlowEmitterCallCount()

/// Emitter that emits [1, 2, 3, 4] and increments a call counter each time
/// it is invoked, allowing tests to verify cold-stream re-execution.
@_cdecl("runtime_test_flow_counting_emitter")
func runtime_test_flow_counting_emitter(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowEmitterCallCounter.increment()
    outThrown?.pointee = 0
    for value in 1 ... 4 {
        _ = kk_flow_emit(0, value, RuntimeFlowTag.emit.rawValue)
    }
    return 0
}

@_cdecl("runtime_test_flow_emitter_with_dupes")
func runtime_test_flow_emitter_with_dupes(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    for value in [1, 1, 2, 2, 3, 1] {
        _ = kk_flow_emit(0, value, RuntimeFlowTag.emit.rawValue)
    }
    return 0
}

/// Fold/reduce operation: (closureRaw, acc, value, outThrown) -> acc + value
private typealias RuntimeFlowFoldEntry = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

@_cdecl("runtime_test_flow_fold_add")
func runtime_test_flow_fold_add(_: Int, _ acc: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return acc + value
}
