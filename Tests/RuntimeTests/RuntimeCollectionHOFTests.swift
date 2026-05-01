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

private let firstNonNullEvenTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? value * 10 : runtimeNullSentinelInt
}

private let alwaysNullTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let filterGreaterThanOne: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value > 1 ? 1 : 0
}

// Helper function to extract string value from runtime handle
private func runtimeStringValue(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

private func runtimeStringRaw(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
        }
    }
}

private let flatMapPair: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    let array = kk_array_new(2)
    var thrown = 0
    _ = _ = kk_array_set(array, 0, value, &thrown)
    _ = _ = kk_array_set(array, 1, value * 10, &thrown)
    return kk_list_of(array, 2)
}

private let windowSum: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, windowRaw, _ in
    guard let windowBox = runtimeListBox(from: windowRaw) else { return 0 }
    return windowBox.elements.reduce(0, +)
}

private let foldSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc + value
}

private let foldOrder: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc * 10 + value
}

private let groupingFoldToInitialValueSelector: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, key, element, _ in
    gHOFState.addCall()
    return key * 100 + element
}

private let groupingFoldToSelectorOperation: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, key, accumulator, element, _ in
    accumulator + key + element
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

private let groupingByStringKey: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    runtimeStringRaw(value % 2 == 0 ? "even" : "odd")
}

private let groupingReduceToFold: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, key, acc, value, _ in
    acc * 10 + value + key
}

private let groupingInitialValueSelector: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, key, element, _ in
    key * 100 + element
}

private let groupingFoldOperation: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, key, accumulator, element, _ in
    accumulator + key + element
}

private let aggregateGroupingLambda: @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, key, accumulator, element, first, _ in
    if first != 0 {
        return key * 10 + element
    }
    return accumulator + key + element
}

// Lambda that returns value * 10 (for associateWithTo tests)
private let valueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 10
}

private let sortedByTens: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value / 10
}

private let sortBySelfStringValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    // Return the string value itself for comparison
    // The sort function will use runtimeCompareValues to compare these values
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

// Lambda that throws for collection HOF1 signature (closureRaw, value, outThrown) -> Int
private let throwingHOFLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "test HOF throw")
    return 0
}

private let mapSentinelToValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == runtimeNullSentinelInt ? 99 : value * 2
}

private let identityMapValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value
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

    func testWindowedTransformReturnsExpectedWindows() {
        let source = makeList([1, 2, 3, 4, 5])

        let defaultStep = kk_list_windowed_transform(
            source,
            3,
            1,
            0,
            unsafeBitCast(windowSum, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(defaultStep), [6, 9, 12])

        let explicitStep = kk_list_windowed_transform(
            source,
            3,
            2,
            0,
            unsafeBitCast(windowSum, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(explicitStep), [6, 12])

        let partialWindows = kk_list_windowed_transform(
            source,
            3,
            2,
            1,
            unsafeBitCast(windowSum, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(partialWindows), [6, 12, 5])

        let arraySource = makeArray([1, 2, 3, 4, 5])
        let arrayWindows = kk_list_windowed_transform(
            arraySource,
            3,
            1,
            0,
            unsafeBitCast(windowSum, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        XCTAssertEqual(listElements(arrayWindows), [6, 9, 12])

    }

    func testWindowedTransformPropagatesThrowingLambda() {
        let source = makeList([1, 2, 3, 4, 5])
        var thrown = 0

        let result = kk_list_windowed_transform(
            source,
            3,
            2,
            1,
            unsafeBitCast(throwingHOFLambda, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testCollectionMapNotNullPassesSentinelInputsToTransform() {
        let source = makeList([1, runtimeNullSentinelInt, 3])

        let listMapped = kk_list_mapNotNull(source, unsafeBitCast(mapSentinelToValue, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(listMapped), [2, 99, 6])

        let setSource = kk_set_of(makeArray([1, runtimeNullSentinelInt, 3]), 3)
        let setMapped = kk_set_mapNotNull(setSource, unsafeBitCast(mapSentinelToValue, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(setMapped)), Set([2, 99, 6]))

        let arraySource = makeArray([1, runtimeNullSentinelInt, 3])
        let arrayMapped = kk_array_mapNotNull(arraySource, unsafeBitCast(mapSentinelToValue, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(arrayMapped), [2, 99, 6])
    }

    func testIterableFirstNotNullOfReturnsFirstNonNullTransformResult() {
        var thrown = 0
        let listSource = makeList([1, 2, 4])
        let listResult = kk_iterable_firstNotNullOf(
            listSource,
            unsafeBitCast(firstNonNullEvenTimesTen, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(listResult, 20)
        XCTAssertEqual(thrown, 0)

        let setSource = kk_set_of(makeArray([1, 3, 4]), 3)
        let setResult = kk_iterable_firstNotNullOf(
            setSource,
            unsafeBitCast(firstNonNullEvenTimesTen, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(setResult, 40)
        XCTAssertEqual(thrown, 0)
    }

    func testIterableFirstNotNullOfThrowsWhenEveryTransformResultIsNull() {
        var thrown = 0
        let source = makeList([1, 3, 5])

        let result = kk_iterable_firstNotNullOf(
            source,
            unsafeBitCast(alwaysNullTransform, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testCollectionMapNotNullPreservesZeroResults() {
        let source = makeList([0, 1, 2])

        let listMapped = kk_list_mapNotNull(source, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(listMapped), [0, 1, 2])

        let setSource = kk_set_of(makeArray([0, 1, 2]), 3)
        let setMapped = kk_set_mapNotNull(setSource, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(setMapped)), Set([0, 1, 2]))

        let arraySource = makeArray([0, 1, 2])
        let arrayMapped = kk_array_mapNotNull(arraySource, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(arrayMapped), [0, 1, 2])
    }

    func testCollectionFilterNotNullPreservesZeroAfterMapNotNull() {
        let source = makeList([0, 1, 2])
        let mapped = kk_list_mapNotNull(source, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        let filtered = kk_list_filterNotNull(mapped)
        XCTAssertEqual(listElements(filtered), [0, 1, 2])

        let setSource = kk_set_of(makeArray([0, 1, 2]), 3)
        let setMapped = kk_set_mapNotNull(setSource, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        let setFiltered = kk_list_filterNotNull(setMapped)
        XCTAssertEqual(Set(listElements(setFiltered)), Set([0, 1, 2]))

        let arraySource = makeArray([0, 1, 2])
        let arrayMapped = kk_array_mapNotNull(arraySource, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        let arrayFiltered = kk_list_filterNotNull(arrayMapped)
        XCTAssertEqual(listElements(arrayFiltered), [0, 1, 2])
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
        // Use different string values to ensure different handles for proper sorting
        let strA = makeRuntimeStringRaw("a")
        let strB = makeRuntimeStringRaw("b") 
        let strC = makeRuntimeStringRaw("c")
        let source = makeList([strB, strA, strC])
        _ = kk_mutable_list_sortBy(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["a", "b", "c"])

        _ = kk_mutable_list_sortByDescending(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["c", "b", "a"])
    }

    func testMutableListShuffleAndReverse() {
        // Test shuffle
        let source = makeList([1, 2, 3, 4, 5])
        let originalElements = listElements(source)
        
        _ = kk_mutable_list_shuffle(source)
        let shuffledElements = listElements(source)
        
        // Should have same elements but different order (most likely)
        XCTAssertEqual(shuffledElements.count, originalElements.count)
        XCTAssertEqual(Set(shuffledElements), Set(originalElements))
        
        // Test reverse
        _ = kk_mutable_list_reverse(source)
        let reversedElements = listElements(source)
        
        // Should be the reverse of shuffled
        XCTAssertEqual(reversedElements, shuffledElements.reversed())
        
        // Test with empty list
        let emptyList = makeList([])
        _ = kk_mutable_list_shuffle(emptyList)
        XCTAssertEqual(listElements(emptyList), [])
        
        _ = kk_mutable_list_reverse(emptyList)
        XCTAssertEqual(listElements(emptyList), [])
        
        // Test with single element
        let singleList = makeList([42])
        _ = kk_mutable_list_shuffle(singleList)
        XCTAssertEqual(listElements(singleList), [42])
        
        _ = kk_mutable_list_reverse(singleList)
        XCTAssertEqual(listElements(singleList), [42])
        
        // Test with duplicate elements
        let duplicateList = makeList([5, 2, 5, 2, 5])
        _ = kk_mutable_list_reverse(duplicateList)
        XCTAssertEqual(listElements(duplicateList), [5, 2, 5, 2, 5].reversed())
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
        XCTAssertEqual(kk_list_reduce(makeList([]), unsafeBitCast(foldSum, to: Int.self), 0, &thrown), runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_list_first(makeList([]), 0, 0, &thrown), runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_list_last(makeList([]), 0, 0, &thrown), runtimeExceptionCaughtSentinel)
    }

    func testGroupByPreservesKeyAndBucketOrder() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouped = kk_list_groupBy(source, unsafeBitCast(groupByParity, to: Int.self), 0, nil)

        XCTAssertEqual(mapKeys(grouped), [1, 0])
        XCTAssertEqual(listElements(kk_map_get(grouped, 1)), [3, 1, 5])
        XCTAssertEqual(listElements(kk_map_get(grouped, 0)), [4, 2])
    }

    func testGroupingByEachCountPreservesKeyOrderAndCounts() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let counts = kk_grouping_eachCount(grouping, nil)

        XCTAssertEqual(mapKeys(counts), [1, 0])
        XCTAssertEqual(kk_unbox_int(kk_map_get(counts, 1)), 3)
        XCTAssertEqual(kk_unbox_int(kk_map_get(counts, 0)), 2)
    }

    func testGroupingByEachCountUsesValueEqualityForStringKeys() {
        let source = makeList([1, 2, 3, 4])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupingByStringKey, to: Int.self), 0)
        let counts = kk_grouping_eachCount(grouping, nil)

        XCTAssertEqual(mapKeys(counts).map(runtimeStringValue), ["odd", "even"])
        XCTAssertEqual(kk_unbox_int(kk_map_get(counts, runtimeStringRaw("odd"))), 2)
        XCTAssertEqual(kk_unbox_int(kk_map_get(counts, runtimeStringRaw("even"))), 2)
    }

    func testGroupingReduceToUsesExistingDestinationAndAddsNewKeys() {
        let source = makeList([1, 3, 2])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [10]))

        let result = kk_grouping_reduceTo(
            grouping,
            dest,
            unsafeBitCast(groupingReduceToFold, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(kk_map_get(result, 1), 1024)
        XCTAssertEqual(kk_map_get(result, 0), 2)
    }

    func testGroupingReduceToEmptySourceLeavesDestinationUnchanged() {
        let grouping = kk_list_groupingBy(makeList([]), unsafeBitCast(groupByParity, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [10]))

        let result = kk_grouping_reduceTo(
            grouping,
            dest,
            unsafeBitCast(groupingReduceToFold, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1])
        XCTAssertEqual(kk_map_get(result, 1), 10)
    }

    func testGroupingFoldInitialValueSelectorUsesKeyAndFirstElement() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let folded = kk_grouping_fold_initialValueSelector(
            grouping,
            unsafeBitCast(groupingInitialValueSelector, to: Int.self),
            0,
            unsafeBitCast(groupingFoldOperation, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(mapKeys(folded), [1, 0])
        XCTAssertEqual(kk_unbox_int(kk_map_get(folded, 1)), 115)
        XCTAssertEqual(kk_unbox_int(kk_map_get(folded, 0)), 10)
    }

    func testGroupingFoldToWithInitialValueMutatesDestination() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [1000]))

        let result = kk_grouping_foldTo(
            grouping,
            dest,
            10,
            unsafeBitCast(foldSum, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(kk_map_get(result, 1), 1009)
        XCTAssertEqual(kk_map_get(result, 0), 16)
    }

    func testGroupingFoldToWithInitialValueSelectorUsesExistingValues() {
        let source = makeList([3, 1, 4, 2])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [0], values: [500]))

        let result = kk_grouping_foldTo_selector(
            grouping,
            dest,
            unsafeBitCast(groupingFoldToInitialValueSelector, to: Int.self),
            0,
            unsafeBitCast(groupingFoldToSelectorOperation, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [0, 1])
        XCTAssertEqual(kk_map_get(result, 0), 506)
        XCTAssertEqual(kk_map_get(result, 1), 109)
        XCTAssertEqual(gHOFState.callsSnapshot(), 1)
    }

    func testGroupingAggregatePreservesKeyOrderAndAccumulatorValues() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let aggregated = kk_grouping_aggregate(grouping, unsafeBitCast(aggregateGroupingLambda, to: Int.self), 0, nil)

        XCTAssertEqual(mapKeys(aggregated), [1, 0])
        XCTAssertEqual(kk_unbox_int(kk_map_get(aggregated, 1)), 21)
        XCTAssertEqual(kk_unbox_int(kk_map_get(aggregated, 0)), 6)
    }

    func testGroupingAggregateToUpdatesDestinationAndPreservesKeyOrder() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let destination = kk_map_of(makeArray([1]), makeArray([100]), 1)
        let aggregated = kk_grouping_aggregateTo(
            grouping,
            destination,
            unsafeBitCast(aggregateGroupingLambda, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(aggregated, destination)
        XCTAssertEqual(mapKeys(aggregated), [1, 0])
        XCTAssertEqual(kk_unbox_int(kk_map_get(aggregated, 1)), 112)
        XCTAssertEqual(kk_unbox_int(kk_map_get(aggregated, 0)), 6)
    }

    func testGroupingByEachCountToAccumulatesIntoExistingDestination() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupByParity, to: Int.self), 0)
        let dest = makeMutableMap(keys: [1], values: [kk_box_int(7)])

        let result = kk_grouping_eachCountTo(grouping, dest, nil)

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(kk_unbox_int(kk_map_get(result, 1)), 10)
        XCTAssertEqual(kk_unbox_int(kk_map_get(result, 0)), 2)
    }

    func testGroupingByEachCountToUsesValueEqualityForStringKeys() {
        let source = makeList([1, 2, 3, 4])
        let grouping = kk_list_groupingBy(source, unsafeBitCast(groupingByStringKey, to: Int.self), 0)
        let dest = makeMutableMap(
            keys: [runtimeStringRaw("odd")],
            values: [kk_box_int(5)]
        )

        let result = kk_grouping_eachCountTo(grouping, dest, nil)

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result).map(runtimeStringValue), ["odd", "even"])
        XCTAssertEqual(kk_unbox_int(kk_map_get(result, runtimeStringRaw("odd"))), 7)
        XCTAssertEqual(kk_unbox_int(kk_map_get(result, runtimeStringRaw("even"))), 2)
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
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(kk_map_get(map, 1), runtimeNullSentinelInt)
    }

    func testMutableMapPutAllNormalizesCorruptedTargetEntryArrays() {
        let target = registerRuntimeObject(RuntimeMapBox(keys: [1, 2], values: [10]))
        let source = registerRuntimeObject(RuntimeMapBox(keys: [2, 3], values: [20, 30]))

        _ = kk_mutable_map_putAll(target, source)

        XCTAssertEqual(mapKeys(target), [1, 2, 3])
        XCTAssertEqual(listElements(kk_map_values(target)), [10, 20, 30])
    }

    func testMutableSetAddAllAcceptsSetInput() {
        let target = registerRuntimeObject(RuntimeSetBox(elements: [1, 2]))
        let source = registerRuntimeObject(RuntimeSetBox(elements: [2, 3, 4]))

        let modified = kk_mutable_set_addAll(target, source)

        XCTAssertEqual(kk_unbox_bool(modified), 1)
        XCTAssertEqual(setElements(target), [1, 2, 3, 4])
    }

    func testSetBinaryOperationsWithStringHandlesUseValueEqualityAndPreserveLeftOrder() {
        let leftAlpha = makeRuntimeStringRaw("alpha")
        let leftBeta = makeRuntimeStringRaw("beta")
        let rightBeta = makeRuntimeStringRaw("beta")
        let rightGamma = makeRuntimeStringRaw("gamma")

        let left = registerRuntimeObject(RuntimeSetBox(elements: [leftAlpha, leftBeta]))
        let right = registerRuntimeObject(RuntimeListBox(elements: [rightBeta, rightGamma, rightBeta]))

        let intersected = kk_set_intersect(left, right)
        let unioned = kk_set_union(left, right)
        let subtracted = kk_set_subtract(left, right)

        XCTAssertEqual(setElements(intersected), [leftBeta])
        XCTAssertEqual(setElements(unioned), [leftAlpha, leftBeta, rightGamma])
        XCTAssertEqual(setElements(subtracted), [leftAlpha])
    }

    func testSetBinaryOperationsAcceptSetInputAndPreserveOrder() {
        let left = registerRuntimeObject(RuntimeSetBox(elements: [1, 2, 3]))
        let right = registerRuntimeObject(RuntimeSetBox(elements: [3, 4, 2]))

        let intersected = kk_set_intersect(left, right)
        let unioned = kk_set_union(left, right)
        let subtracted = kk_set_subtract(left, right)

        XCTAssertEqual(setElements(intersected), [2, 3])
        XCTAssertEqual(setElements(unioned), [1, 2, 3, 4])
        XCTAssertEqual(setElements(subtracted), [1])
    }

    func testBoolAbiForCollectionHelpersReturnsRaw() {
        let source = makeList([1, 2, 3])
        XCTAssertEqual(kk_unbox_bool(kk_list_contains(source, 2)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_list_contains(source, 9)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_list_containsAll(source, makeList([1, 3]))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_list_containsAll(source, makeList([1, 9]))), 0)
        XCTAssertEqual(kk_unbox_bool(kk_list_is_empty(source)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_list_is_empty(makeList([]))), 1)

        let set = kk_set_of(makeArray([1, 2, 3]), 3)
        XCTAssertEqual(kk_unbox_bool(kk_set_containsAll(set, makeList([1, 3]))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_set_containsAll(set, makeList([1, 9]))), 0)

        let keys = makeArray([1, 2])
        let values = makeArray([10, 20])
        let map = kk_map_of(keys, values, 2)
        XCTAssertEqual(kk_unbox_bool(kk_map_contains_key(map, 2)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_map_contains_key(map, 9)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_map_is_empty(map)), 0)
        XCTAssertEqual(kk_unbox_bool(kk_map_is_empty(kk_map_of(0, 0, 0))), 1)
    }

    func testReduceOrNullReturnsZeroForEmptyList() {
        let emptyList = makeList([])
        var thrown = 0
        let result = kk_list_reduceOrNull(emptyList, unsafeBitCast(foldSum, to: Int.self), 0, &thrown)
        XCTAssertEqual(result, runtimeNullSentinelInt, "reduceOrNull should return runtimeNullSentinelInt (null) for empty list")
        XCTAssertEqual(thrown, 0, "reduceOrNull should not set outThrown for empty list")
    }

    func testReduceOrNullReturnsSingleElementForSingletonList() {
        let singleton = makeList([42])
        var thrown = 0
        let result = kk_list_reduceOrNull(singleton, unsafeBitCast(foldSum, to: Int.self), 0, &thrown)
        XCTAssertEqual(result, 42, "reduceOrNull should return the single element without invoking lambda")
        XCTAssertEqual(thrown, 0)
    }

    func testReduceOrNullMatchesReduceForNonEmptyList() {
        let source = makeList([1, 2, 3])
        let reduceResult = kk_list_reduce(source, unsafeBitCast(foldOrder, to: Int.self), 0, nil)
        let reduceOrNullResult = kk_list_reduceOrNull(source, unsafeBitCast(foldOrder, to: Int.self), 0, nil)
        XCTAssertEqual(reduceOrNullResult, reduceResult, "reduceOrNull should produce same result as reduce for non-empty lists")
    }

    func testUnsignedListToPrimitiveArrayConversionsCopyElements() {
        XCTAssertEqual(arrayElements(kk_list_toUByteArray(makeList([1, 255]))), [1, 255])
        XCTAssertEqual(arrayElements(kk_list_toUShortArray(makeList([1, 65_535]))), [1, 65_535])
        XCTAssertEqual(arrayElements(kk_list_toUIntArray(makeList([1, 4_000_000_000]))), [1, 4_000_000_000])
        XCTAssertEqual(arrayElements(kk_list_toULongArray(makeList([1, -1]))), [1, -1])
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = _ = kk_array_set(arrayRaw, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return arrayRaw
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = makeArray(elements)
        return kk_list_of(arrayRaw, elements.count)
    }

    private func makeMutableMap(keys: [Int], values: [Int]) -> Int {
        registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
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

    private func arrayElements(_ arrayRaw: Int) -> [Int] {
        guard let array = runtimeArrayBox(from: arrayRaw) else {
            return []
        }
        return array.elements
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

    // MARK: - associateByTo / associateWithTo / groupByTo tests

    func testAssociateByToBasic() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil
        )
        // Returns same destination handle
        XCTAssertEqual(result, dest)
        // Keys are lambda results (value*2), values are elements
        XCTAssertEqual(mapKeys(result), [2, 4, 6])
    }

    func testAssociateByToDuplicateKeysLastWriteWins() {
        // Elements 1 and 3 both have key = parity 1; 2 has key = parity 0
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Last-write-wins: key 1 -> last elem with odd parity is 3, key 0 -> 2
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(kk_map_get(result, 1), 3)
        XCTAssertEqual(kk_map_get(result, 0), 2)
    }

    func testAssociateByToPrePopulatedDestination() {
        // Pre-populate destination with key=100 -> value=999
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [100], values: [999]))
        let source = makeList([5, 10])

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil
        )
        // Existing entry preserved, new entries added
        XCTAssertEqual(result, dest)
        XCTAssertEqual(kk_map_get(result, 100), 999)
        XCTAssertTrue(mapKeys(result).contains(10))  // key for elem 5
        XCTAssertTrue(mapKeys(result).contains(20))  // key for elem 10
    }

    func testAssociateWithToBasic() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        // Keys are elements, values are lambda results (elem*10)
        XCTAssertEqual(result, dest)
        XCTAssertEqual(kk_map_get(result, 1), 10)
        XCTAssertEqual(kk_map_get(result, 2), 20)
        XCTAssertEqual(kk_map_get(result, 3), 30)
    }

    func testAssociateWithToDuplicateKeysLastWriteWins() {
        let source = makeList([1, 1, 2])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        // Duplicate key 1: last write wins (both map to 10, so same value)
        XCTAssertEqual(mapKeys(result), [1, 2])
        XCTAssertEqual(kk_map_get(result, 1), 10)
        XCTAssertEqual(kk_map_get(result, 2), 20)
    }

    func testAssociateWithToPrePopulatedDestination() {
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [100], values: [999]))
        let source = makeList([5])

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        XCTAssertEqual(result, dest)
        XCTAssertEqual(kk_map_get(result, 100), 999)
        XCTAssertEqual(kk_map_get(result, 5), 50)
    }

    func testGroupByToBasic() {
        let source = makeList([3, 1, 4, 2, 5])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Same destination handle returned
        XCTAssertEqual(result, dest)
        // Odd elements (parity 1) grouped, even elements (parity 0) grouped
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(listElements(kk_map_get(result, 1)), [3, 1, 5])
        XCTAssertEqual(listElements(kk_map_get(result, 0)), [4, 2])
    }

    func testGroupByToPrePopulatedDestinationAppends() {
        // Pre-populate with key=1 already containing [100]
        let existingList = registerRuntimeObject(RuntimeListBox(elements: [100]))
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [existingList]))
        let source = makeList([3, 5])  // both have parity 1

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Existing list should have new elements appended
        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(kk_map_get(result, 1)), [100, 3, 5])
    }

    func testGroupByToNewAndExistingKeys() {
        // Pre-populate with key=0 containing [10]
        let existingList = registerRuntimeObject(RuntimeListBox(elements: [10]))
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [0], values: [existingList]))
        let source = makeList([1, 2])  // 1->parity 1 (new key), 2->parity 0 (existing)

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Existing key 0 gets 2 appended; new key 1 gets [1]
        XCTAssertEqual(listElements(kk_map_get(result, 0)), [10, 2])
        XCTAssertEqual(listElements(kk_map_get(result, 1)), [1])
    }

    // MARK: - Throwing lambda tests for *To functions

    func testAssociateByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testAssociateWithToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testGroupByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

}
