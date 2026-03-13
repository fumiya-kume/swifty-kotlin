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

private let foldOrder: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc * 10 + value
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

private let sortBySelfStringValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value
}

private let mapEntrySum: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_first(pairRaw) + kk_pair_second(pairRaw)
}

private let keepEvenValueEntries: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_second(pairRaw) % 2 == 0 ? 1 : 0
}

private let accumulateEntryScore: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    gHOFState.addSum(kk_pair_first(pairRaw) * 10 + kk_pair_second(pairRaw))
    return 0
}

private let mapEntryValueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_second(pairRaw) * 10
}

private let mapEntryKeyPlusHundred: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_first(pairRaw) + 100
}

private let returnSeven: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    gHOFState.addCall()
    return 7
}

private let throwForGetOrPut: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    gHOFState.addCall()
    outThrown?.pointee = runtimeAllocateThrowable(message: "test getOrPut throw")
    return 123
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
        let filtered = kk_list_filter(source, unsafeBitCast(filterGreaterThanOne, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        let mapped = kk_list_map(filtered, unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(mapped), [4, 6])
    }

    func testCaptureLambdaForMapAndForEach() {
        let source = makeList([1, 2, 3])
        let closure = makeArray([5])

        let mapped = kk_list_map(source, unsafeBitCast(addCapture, to: Int.self), closure, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(mapped), [6, 7, 8])

        _ = kk_list_forEach(source, unsafeBitCast(forEachCapture, to: Int.self), closure, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(gHOFState.sumSnapshot(), 21)
    }

    func testFlatMapFoldReduceAndSortedBy() {
        let source = makeList([1, 2, 3])
        let flatMapped = kk_list_flatMap(source, unsafeBitCast(flatMapPair, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(flatMapped), [1, 10, 2, 20, 3, 30])

        XCTAssertEqual(kk_list_fold(source, 0, unsafeBitCast(foldOrder, to: Int.self), 0, nil), 123)
        XCTAssertEqual(kk_list_reduce(source, unsafeBitCast(foldOrder, to: Int.self), 0, nil), 123)

        let sorted = kk_list_sortedBy(makeList([22, 12, 21, 11]), unsafeBitCast(sortedByTens, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(sorted), [12, 11, 22, 21])
    }

    func testSortedByWithStringKeyHandlesNonIntegerComparison() {
        let source = makeList([makeRuntimeStringRaw("b"), makeRuntimeStringRaw("a"), makeRuntimeStringRaw("c")])

        let sorted = kk_list_sortedBy(
            source,
            unsafeBitCast(sortBySelfStringValue, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(sorted).map(runtimeStringValue), ["a", "b", "c"])

        let sortedDesc = kk_list_sortedByDescending(
            source,
            unsafeBitCast(sortBySelfStringValue, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(sortedDesc).map(runtimeStringValue), ["c", "b", "a"])
    }

    func testMutableListSortByStringKeyMutatesInPlace() {
        let source = makeList([makeRuntimeStringRaw("b"), makeRuntimeStringRaw("a"), makeRuntimeStringRaw("c")])
        _ = kk_mutable_list_sortBy(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["a", "b", "c"])

        _ = kk_mutable_list_sortByDescending(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["c", "b", "a"])
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

    func testMapForEachFilterAndMapUsePairEntries() {
        let keys = makeArray([1, 2, 3])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        _ = kk_map_forEach(map, unsafeBitCast(accumulateEntryScore, to: Int.self), 0, nil)
        XCTAssertEqual(gHOFState.sumSnapshot(), 123)

        let mapped = kk_map_map(map, unsafeBitCast(mapEntrySum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [11, 23, 35])

        let filtered = kk_map_filter(map, unsafeBitCast(keepEvenValueEntries, to: Int.self), 0, nil)
        XCTAssertEqual(mapKeys(filtered), [1, 3])
        XCTAssertEqual(kk_map_get(filtered, 1), 10)
        XCTAssertEqual(kk_map_get(filtered, 3), 32)
    }

    func testMapValuesMapKeysAndToListUsePairEntries() {
        let keys = makeArray([1, 2, 1])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        let mappedValues = kk_map_mapValues(map, unsafeBitCast(mapEntryValueTimesTen, to: Int.self), 0, nil)
        XCTAssertEqual(mapKeys(mappedValues), [1, 2])
        XCTAssertEqual(kk_map_get(mappedValues, 1), 320)
        XCTAssertEqual(kk_map_get(mappedValues, 2), 210)

        let mappedKeys = kk_map_mapKeys(map, unsafeBitCast(mapEntryKeyPlusHundred, to: Int.self), 0, nil)
        XCTAssertEqual(mapKeys(mappedKeys), [101, 102])
        XCTAssertEqual(kk_map_get(mappedKeys, 101), 32)
        XCTAssertEqual(kk_map_get(mappedKeys, 102), 21)

        let list = kk_map_toList(map)
        XCTAssertEqual(listElements(list).map { kk_pair_first($0) }, [1, 2])
        XCTAssertEqual(listElements(list).map { kk_pair_second($0) }, [32, 21])
    }

    func testMapKeysValuesEntriesProperties() {
        let keys = makeArray([1, 2, 1])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        XCTAssertEqual(setElements(kk_map_keys(map)), [1, 2])
        XCTAssertEqual(listElements(kk_map_values(map)), [32, 21])

        let entries = setElements(kk_map_entries(map))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            entries.map { kk_pair_first($0) },
            mapKeys(map)
        )
        XCTAssertEqual(
            entries.map { kk_pair_second($0) },
            listElements(kk_map_values(map))
        )
    }

    func testMapPlusNormalizesMismatchedEntriesBeforeUpdate() {
        let corruptedMap = registerRuntimeObject(RuntimeMapBox(keys: [1, 2, 3], values: [10, 20]))
        let updated = kk_map_plus(corruptedMap, kk_pair_new(3, 99))

        XCTAssertEqual(mapKeys(updated), [1, 2, 3])
        XCTAssertEqual(listElements(kk_map_values(updated)), [10, 20, 99])
    }

    func testMapMinusNormalizesMismatchedEntriesBeforeRemoval() {
        let corruptedMap = registerRuntimeObject(RuntimeMapBox(keys: [1, 2, 3], values: [10, 20]))
        let updated = kk_map_minus(corruptedMap, 2)

        XCTAssertEqual(mapKeys(updated), [1])
        XCTAssertEqual(listElements(kk_map_values(updated)), [10])
    }

    func testListPlusCollectionAppendsSetElements() {
        let list = makeList([1, 2])
        let set = kk_set_of(makeArray([3, 4]), 2)

        let combined = kk_list_plus_collection(list, set)

        XCTAssertEqual(listElements(combined), [1, 2, 3, 4])
    }

    func testMutableMapGetOrPutPreservesStoredRuntimeLongBoxAtNullSentinelValue() {
        let boxedLongMin = registerRuntimeObject(RuntimeLongBox(runtimeNullSentinelInt))
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [boxedLongMin]))

        gHOFState.reset()
        let result = kk_mutable_map_getOrPut(map, 1, unsafeBitCast(returnSeven, to: Int.self), 0, nil)

        XCTAssertEqual(gHOFState.callsSnapshot(), 0)
        XCTAssertEqual(result, boxedLongMin)
        XCTAssertEqual(kk_map_get(map, 1), boxedLongMin)
    }

    func testMutableMapGetOrPutReturnsZeroWhenLambdaThrowsForExistingNullEntry() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [runtimeNullSentinelInt]))

        gHOFState.reset()
        var thrown = 0
        let result = kk_mutable_map_getOrPut(map, 1, unsafeBitCast(throwForGetOrPut, to: Int.self), 0, &thrown)

        XCTAssertEqual(gHOFState.callsSnapshot(), 1)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(kk_map_get(map, 1), runtimeNullSentinelInt)
    }

    func testBoolAbiForCollectionHelpersReturnsRaw() {
        let source = makeList([1, 2, 3])
        XCTAssertEqual(kk_unbox_bool(kk_list_contains(source, 2)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_list_contains(source, 9)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_list_is_empty(source)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_list_is_empty(makeList([]))), 1)

        let keys = makeArray([1, 2])
        let values = makeArray([10, 20])
        let map = kk_map_of(keys, values, 2)
        XCTAssertEqual(kk_unbox_bool(kk_map_contains_key(map, 2)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_map_contains_key(map, 9)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_map_is_empty(map)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_map_is_empty(kk_map_of(0, 0, 0))), 1)
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

    private func setElements(_ setRaw: Int) -> [Int] {
        guard let set = runtimeSetBox(from: setRaw) else {
            return []
        }
        return set.elements
    }

    private func mapKeys(_ mapRaw: Int) -> [Int] {
        let iterator = kk_map_iterator(mapRaw)
        var keys: [Int] = []
        while kk_map_iterator_hasNext(iterator) != 0 {
            keys.append(kk_map_iterator_next(iterator))
        }
        return keys
    }

    private func makeRuntimeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
