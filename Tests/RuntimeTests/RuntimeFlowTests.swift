import Foundation
@testable import Runtime
import XCTest

private typealias RuntimeFlowEmitterEntry = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeFlowUnaryEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private enum RuntimeFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
}

private final class RuntimeFlowTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var collectedValues: [Int] = []
    private var mapCallCount = 0
    private var collectorCallCount = 0

    func reset() {
        lock.lock()
        collectedValues.removeAll(keepingCapacity: true)
        mapCallCount = 0
        collectorCallCount = 0
        lock.unlock()
    }

    func recordMapCall() {
        lock.lock()
        mapCallCount += 1
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

    func snapshot() -> (values: [Int], mapCalls: Int, collectorCalls: Int) {
        lock.lock()
        let snapshot = (values: collectedValues, mapCalls: mapCallCount, collectorCalls: collectorCallCount)
        lock.unlock()
        return snapshot
    }
}

private let runtimeFlowTestState = RuntimeFlowTestState()

@_cdecl("runtime_test_flow_emitter_values_1_2_3_4")
func runtime_test_flow_emitter_values_1_2_3_4(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    for value in 1 ... 4 {
        _ = kk_flow_emit(0, value, RuntimeFlowTag.emit.rawValue)
    }
    return 0
}

@_cdecl("runtime_test_flow_map_throw_on_two")
func runtime_test_flow_map_throw_on_two(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeFlowTestState.recordMapCall()
    if value == 2 {
        outThrown?.pointee = 1
        return 0
    }
    outThrown?.pointee = 0
    return value
}

@_cdecl("runtime_test_flow_collect_store")
func runtime_test_flow_collect_store(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = runtimeFlowTestState.recordCollectorValue(value)
    outThrown?.pointee = 0
    return 0
}

@_cdecl("runtime_test_flow_collect_throw_on_first")
func runtime_test_flow_collect_throw_on_first(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let callIndex = runtimeFlowTestState.recordCollectorValue(value)
    if callIndex == 1 {
        outThrown?.pointee = 1
        return 0
    }
    outThrown?.pointee = 0
    return 0
}

final class RuntimeFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        runtimeFlowTestState.reset()
    }

    override func tearDown() {
        runtimeFlowTestState.reset()
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testChainedTakeAppliesAllTakeStepsAndResetsPerCollect() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let firstTake = kk_flow_emit(flowHandle, 3, RuntimeFlowTag.take.rawValue)
        let chainedTake = kk_flow_emit(firstTake, 2, RuntimeFlowTag.take.rawValue)

        _ = kk_flow_collect(chainedTake, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [1, 2], "Both take steps should be applied in a chain.")

        runtimeFlowTestState.reset()
        _ = kk_flow_collect(chainedTake, collectorPtr, 0)
        XCTAssertEqual(runtimeFlowTestState.snapshot().values, [1, 2], "take counters should reset on each collect.")
    }

    func testMapThrowTerminatesFlowAndSkipsSubsequentEmits() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let mapPtr = unsafeBitCast(runtime_test_flow_map_throw_on_two as RuntimeFlowUnaryEntry, to: Int.self)
        let collectorPtr = unsafeBitCast(runtime_test_flow_collect_store as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        let mapped = kk_flow_emit(flowHandle, mapPtr, RuntimeFlowTag.map.rawValue)
        _ = kk_flow_collect(mapped, collectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [1], "Values after a thrown map step must not reach collector.")
        XCTAssertEqual(snapshot.mapCalls, 2, "Map should run for values 1 and 2, then terminate.")
        XCTAssertEqual(snapshot.collectorCalls, 1)
    }

    func testCollectorThrowTerminatesFlowAfterFirstCollectedValue() {
        let emitterPtr = unsafeBitCast(runtime_test_flow_emitter_values_1_2_3_4 as RuntimeFlowEmitterEntry, to: Int.self)
        let throwingCollectorPtr = unsafeBitCast(runtime_test_flow_collect_throw_on_first as RuntimeFlowUnaryEntry, to: Int.self)

        let flowHandle = kk_flow_create(emitterPtr, 0)
        _ = kk_flow_collect(flowHandle, throwingCollectorPtr, 0)

        let snapshot = runtimeFlowTestState.snapshot()
        XCTAssertEqual(snapshot.values, [1], "Collector throw should stop subsequent emissions.")
        XCTAssertEqual(snapshot.collectorCalls, 1)
    }
}
