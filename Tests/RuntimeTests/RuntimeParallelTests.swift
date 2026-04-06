import Foundation
@testable import Runtime
import XCTest

private final class ParallelVisitState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func reset() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func append(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private let parallelVisitState = ParallelVisitState()

private let parallelMapSquareThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * value
}

private let parallelForEachCaptureThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    parallelVisitState.append(value)
    return 0
}

private let parallelReduceAddThunk: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    lhs + rhs
}

final class RuntimeParallelTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        parallelVisitState.reset()
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = _ = kk_array_set(array, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    private func makeList(_ elements: [Int]) -> Int {
        let array = makeArray(elements)
        return kk_list_of(array, elements.count)
    }

    private func makeSequence(_ elements: [Int]) -> Int {
        kk_sequence_from_list(makeList(elements))
    }

    private func makeParallelStream(from elements: [Int], workerCount: Int = 2) -> Int {
        kk_parallel_stream_from_collection(makeSequence(elements), kk_parallel_pool_new(workerCount))
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        runtimeListBox(from: listRaw)?.elements ?? []
    }

    func testParallelStreamAcceptsSequencesAndPreservesOrder() {
        let stream = makeParallelStream(from: [1, 2, 3, 4])
        XCTAssertEqual(listElements(kk_parallel_stream_to_list(stream)), [1, 2, 3, 4])
    }

    func testParallelStreamMapPreservesOrder() {
        let stream = makeParallelStream(from: [1, 2, 3, 4])
        let mapped = kk_parallel_stream_map(
            stream,
            unsafeBitCast(parallelMapSquareThunk, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(listElements(kk_parallel_stream_to_list(mapped)), [1, 4, 9, 16])
    }

    func testParallelStreamForEachVisitsAllElements() {
        let stream = makeParallelStream(from: [10, 20, 30, 40, 50])
        _ = kk_parallel_stream_forEach(
            stream,
            unsafeBitCast(parallelForEachCaptureThunk, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(parallelVisitState.snapshot().sorted(), [10, 20, 30, 40, 50])
    }

    func testParallelStreamReduceCombinesValues() {
        let stream = makeParallelStream(from: [1, 2, 3, 4])
        let reduced = kk_parallel_stream_reduce(
            stream,
            0,
            unsafeBitCast(parallelReduceAddThunk, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(reduced, 10)
    }
}
