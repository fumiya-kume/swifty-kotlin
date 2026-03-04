import Foundation
@testable import Runtime
import XCTest

private final class HOFState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var sum = 0

    func reset() {
        lock.lock()
        calls = 0
        sum = 0
        lock.unlock()
    }

    func addCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func addSum(_ value: Int) {
        lock.lock()
        sum += value
        lock.unlock()
    }

    func callsSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func sumSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sum
    }
}

private let gHOFState = HOFState()

private let mapTimesTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 2
}

private let filterGreaterThanOne: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value > 1 ? 1 : 0
}

private let flatMapPair: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    let array = kk_array_new(2)
    var thrown = 0
    _ = kk_array_set(array, 0, value, &thrown)
    _ = kk_array_set(array, 1, value * 10, &thrown)
    return kk_list_of(array, 2)
}

private let foldSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc + value
}

private let addCapture: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, value, outThrown in
    var thrown = 0
    let capture = kk_array_get(closureRaw, 0, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return value + capture
}

private let forEachCapture: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, value, outThrown in
    var thrown = 0
    let capture = kk_array_get(closureRaw, 0, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    gHOFState.addSum(value + capture)
    return 0
}

private let anyGtTwoCounting: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    gHOFState.addCall()
    return value > 2 ? 1 : 0
}

private let allLtThreeCounting: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    gHOFState.addCall()
    return value < 3 ? 1 : 0
}

private let noneEqTwoCounting: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    gHOFState.addCall()
    return value == 2 ? 1 : 0
}

private let countEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

private let firstGreaterThanTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value > 2 ? 1 : 0
}

private let lastLessThanThree: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value < 3 ? 1 : 0
}

private let findEqualTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == 2 ? 1 : 0
}

private let groupByParity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let sortedByTens: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value / 10
}

final class RuntimeCollectionHOFTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        gHOFState.reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testFilterThenMapMatchesExpectedChain() {
        let source = makeList([1, 2, 3])
        let filtered = kk_list_filter(source, unsafeBitCast(filterGreaterThanOne, to: Int.self), 0, nil)
        let mapped = kk_list_map(filtered, unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [4, 6])
    }

    func testCaptureLambdaForMapAndForEach() {
        let source = makeList([1, 2, 3])
        let closure = makeArray([5])

        let mapped = kk_list_map(source, unsafeBitCast(addCapture, to: Int.self), closure, nil)
        XCTAssertEqual(listElements(mapped), [6, 7, 8])

        _ = kk_list_forEach(source, unsafeBitCast(forEachCapture, to: Int.self), closure, nil)
        XCTAssertEqual(gHOFState.sumSnapshot(), 21)
    }

    func testFlatMapFoldReduceAndSortedBy() {
        let source = makeList([1, 2, 3])
        let flatMapped = kk_list_flatMap(source, unsafeBitCast(flatMapPair, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(flatMapped), [1, 10, 2, 20, 3, 30])

        XCTAssertEqual(kk_list_fold(source, 0, unsafeBitCast(foldSum, to: Int.self), 0, nil), 6)
        XCTAssertEqual(kk_list_reduce(source, unsafeBitCast(foldSum, to: Int.self), 0, nil), 6)

        let sorted = kk_list_sortedBy(makeList([21, 11, 12, 22]), unsafeBitCast(sortedByTens, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(sorted), [11, 12, 21, 22])
    }

    func testAnyAllNoneShortCircuitAndNoArgOverloads() {
        let source = makeList([1, 2, 3, 4])

        gHOFState.reset()
        XCTAssertEqual(kk_list_any(source, unsafeBitCast(anyGtTwoCounting, to: Int.self), 0, nil), 1)
        XCTAssertEqual(gHOFState.callsSnapshot(), 3)

        gHOFState.reset()
        XCTAssertEqual(kk_list_all(source, unsafeBitCast(allLtThreeCounting, to: Int.self), 0, nil), 0)
        XCTAssertEqual(gHOFState.callsSnapshot(), 3)

        gHOFState.reset()
        XCTAssertEqual(kk_list_none(source, unsafeBitCast(noneEqTwoCounting, to: Int.self), 0, nil), 0)
        XCTAssertEqual(gHOFState.callsSnapshot(), 2)

        XCTAssertEqual(kk_list_any(source, 0, 0, nil), 1)
        XCTAssertEqual(kk_list_none(makeList([]), 0, 0, nil), 1)
    }

    func testCountFirstLastFindAndEmptyFailures() {
        let source = makeList([1, 2, 3, 4])

        XCTAssertEqual(kk_list_count(source, 0, 0, nil), 4)
        XCTAssertEqual(kk_list_count(source, unsafeBitCast(countEven, to: Int.self), 0, nil), 2)

        XCTAssertEqual(kk_list_first(source, 0, 0, nil), 1)
        XCTAssertEqual(kk_list_last(source, 0, 0, nil), 4)
        XCTAssertEqual(kk_list_first(source, unsafeBitCast(firstGreaterThanTwo, to: Int.self), 0, nil), 3)
        XCTAssertEqual(kk_list_last(source, unsafeBitCast(lastLessThanThree, to: Int.self), 0, nil), 2)
        XCTAssertEqual(kk_list_find(source, unsafeBitCast(findEqualTwo, to: Int.self), 0, nil), 2)
        XCTAssertEqual(kk_list_find(source, unsafeBitCast(firstGreaterThanTwo, to: Int.self), 0, nil), 3)

        var thrown = 0
        XCTAssertEqual(kk_list_reduce(makeList([]), unsafeBitCast(foldSum, to: Int.self), 0, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_list_first(makeList([]), 0, 0, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_list_last(makeList([]), 0, 0, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testGroupByPreservesKeyAndBucketOrder() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouped = kk_list_groupBy(source, unsafeBitCast(groupByParity, to: Int.self), 0, nil)

        XCTAssertEqual(mapKeys(grouped), [1, 0])
        XCTAssertEqual(listElements(kk_map_get(grouped, 1)), [3, 1, 5])
        XCTAssertEqual(listElements(kk_map_get(grouped, 0)), [4, 2])
    }

    func testBoolAbiForCollectionHelpersReturnsRaw() {
        let source = makeList([1, 2, 3])
        XCTAssertEqual(kk_list_contains(source, 2), 1)
        XCTAssertEqual(kk_list_contains(source, 9), 0)
        XCTAssertEqual(kk_list_is_empty(source), 0)
        XCTAssertEqual(kk_list_is_empty(makeList([])), 1)

        let keys = makeArray([1, 2])
        let values = makeArray([10, 20])
        let map = kk_map_of(keys, values, 2)
        XCTAssertEqual(kk_map_contains_key(map, 2), 1)
        XCTAssertEqual(kk_map_contains_key(map, 9), 0)
        XCTAssertEqual(kk_map_is_empty(map), 0)
        XCTAssertEqual(kk_map_is_empty(kk_map_of(0, 0, 0)), 1)
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return arrayRaw
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = makeArray(elements)
        return kk_list_of(arrayRaw, elements.count)
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { index in
            kk_list_get(listRaw, index)
        }
    }

    private func mapKeys(_ mapRaw: Int) -> [Int] {
        let iterator = kk_map_iterator(mapRaw)
        var keys: [Int] = []
        while kk_map_iterator_hasNext(iterator) != 0 {
            keys.append(kk_map_iterator_next(iterator))
        }
        return keys
    }
}
