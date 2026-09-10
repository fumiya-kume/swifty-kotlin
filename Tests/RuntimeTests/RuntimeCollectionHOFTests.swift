#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

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

private let mapIndexedEvenIndexToValuePlusIndex: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index.isMultiple(of: 2) ? value + index : runtimeNullSentinelInt
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
    _ = kk_array_set(array, 0, value, &thrown)
    _ = kk_array_set(array, 1, value * 10, &thrown)
    return kk_list_of(array, 2)
}

private let flatMapIndexedPair: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    let array = kk_array_new(2)
    var thrown = 0
    _ = kk_array_set(array, 0, index, &thrown)
    _ = kk_array_set(array, 1, value * 10, &thrown)
    return kk_list_of(array, 2)
}

private let windowSum: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, windowRaw, _ in
    guard let windowBox = runtimeListBox(from: windowRaw) else { return 0 }
    return windowBox.elements.reduce(0, +)
}

private let sumByWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * value
}

private let maxWithOrNullNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs < rhs {
        return -1
    }
    if lhs > rhs {
        return 1
    }
    return 0
}

private let maxWithNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs < rhs {
        return -1
    }
    if lhs > rhs {
        return 1
    }
    return 0
}

private let reverseIntComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs > rhs {
        return -1
    }
    if lhs < rhs {
        return 1
    }
    return 0
}

private let maxOfWithOrNullNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs < rhs {
        return -1
    }
    if lhs > rhs {
        return 1
    }
    return 0
}

private let maxOfWithNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs < rhs {
        return -1
    }
    if lhs > rhs {
        return 1
    }
    return 0
}

private let maxOfWithOrNullSquareValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * value
}

private let sumByDoubleWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_double_to_bits(value == 2 ? 1.5 : 0.25)
}

private let maxByNegativeValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    -value
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

// Lambda that returns value * 10 (for associateWithTo tests)
private let valueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 10
}

private let associateParityTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_pair_new(value % 2, value * 10)
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

private let keepOddMapKeys: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, key, _ in
    key % 2 != 0 ? 1 : 0
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

private let mapEntryKeyTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_first(pairRaw) * 10
}

private let mapEntryValuePlusOne: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, pairRaw, _ in
    kk_pair_second(pairRaw) + 1
}

private let adjacentDifference: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, left, right, _ in
    right - left
}

private let throwForMapDefault: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    gHOFState.addCall()
    outThrown?.pointee = runtimeAllocateThrowable(message: "test map default throw")
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

private let firstNullableEvenTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value.isMultiple(of: 2) ? value * 10 : runtimeNullSentinelInt
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: { gHOFState.reset() }))
struct RuntimeCollectionHOFTests {
    @Test
    func testMapIndexedNotNullFiltersNullResults() {
        let source = makeList([10, 20, 30, 40])
        let mapped = kk_list_mapIndexedNotNull(
            source,
            unsafeBitCast(mapIndexedEvenIndexToValuePlusIndex, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(listElements(mapped) == [10, 32])
    }

    @Test
    func testCaptureLambdaForMapAndForEach() {
        let source = makeList([1, 2, 3])
        let closure = makeArray([5])

        let mapped = kk_list_map(source, unsafeBitCast(addCapture, to: Int.self), closure, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(mapped) == [6, 7, 8])

        _ = kk_list_forEach(source, unsafeBitCast(forEachCapture, to: Int.self), closure, nil as UnsafeMutablePointer<Int>?)
        #expect(gHOFState.sumSnapshot() == 21)
    }

    @Test
    func testFlatMapFoldReduceAndSortedBy() {
        let source = makeList([1, 2, 3])
        let flatMapped = kk_list_flatMap(source, unsafeBitCast(flatMapPair, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(flatMapped) == [1, 10, 2, 20, 3, 30])
        #expect(listElements(kk_list_flatten(makeList([makeList([1, 2]), makeList([3])]))) == [1, 2, 3])
        let nestedCollections = makeList([makeList([1]), kk_set_of(makeArray([2, 3]), 2)])
        #expect(listElements(kk_list_flatten(nestedCollections)) == [1, 2, 3])

        let flatMappedIndexed = kk_list_flatMapIndexed(source, unsafeBitCast(flatMapIndexedPair, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(flatMappedIndexed) == [0, 10, 1, 20, 2, 30])

        let sorted = kk_list_sortedBy(makeList([22, 12, 21, 11]), unsafeBitCast(sortedByTens, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(sorted) == [12, 11, 22, 21])
    }

    @Test
    func testMinOfReturnsSmallestSelectedValueAndThrowsOnEmpty() {
        var thrown = 0
        let result = kk_list_minOf(
            makeList([5, 2, 3]),
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0)
        #expect(result == 20)

        thrown = 0
        let emptyResult = kk_list_minOf(
            makeList([]),
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            &thrown
        )
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMaxByReturnsElementWithLargestSelectorAndThrowsOnEmpty() {
        var thrown = 0
        let source = makeList([3, 1, 4, 2])
        let result = kk_list_maxBy(source, unsafeBitCast(maxByNegativeValue, to: Int.self), 0, &thrown)

        #expect(result == 1)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_maxBy(makeList([]), unsafeBitCast(maxByNegativeValue, to: Int.self), 0, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMinOfOrNullReturnsSmallestSelectedValueAndNullOnEmpty() {
        let result = kk_list_minOfOrNull(
            makeList([5, 2, 3]),
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(result == 20)

        let emptyResult = kk_list_minOfOrNull(
            makeList([]),
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(emptyResult == runtimeNullSentinelInt)
    }

    @Test
    func testMinOrNullReturnsSmallestElementAndNullOnEmpty() {
        #expect(kk_list_minOrNull(makeList([5, 2, 3])) == 2)
        #expect(kk_list_minOrNull(makeList([])) == runtimeNullSentinelInt)
    }

    @Test
    func testMinWithReturnsComparatorMinimumAndThrowsOnEmpty() {
        var thrown = 0
        let result = kk_list_minWith(
            makeList([5, 2, 3]),
            unsafeBitCast(reverseIntComparator, to: Int.self),
            0,
            &thrown
        )
        #expect(result == 5)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_minWith(makeList([]), unsafeBitCast(reverseIntComparator, to: Int.self), 0, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMaxByOrNullReturnsElementWithLargestSelectorAndNullForEmpty() {
        var thrown = 0
        let source = makeList([3, 1, 4, 2])
        let result = kk_list_maxByOrNull(source, unsafeBitCast(maxByNegativeValue, to: Int.self), 0, &thrown)

        #expect(result == 1)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_maxByOrNull(makeList([]), unsafeBitCast(maxByNegativeValue, to: Int.self), 0, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testMaxWithOrNullReturnsLargestElementAndNullForEmpty() {
        var thrown = 0
        #expect(kk_list_maxWithOrNull(makeList([3, 1, 4, 2]), unsafeBitCast(maxWithOrNullNaturalComparator, to: Int.self), 0, &thrown) == 4)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_maxWithOrNull(makeList([]), unsafeBitCast(maxWithOrNullNaturalComparator, to: Int.self), 0, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testMaxOrNullReturnsLargestElementAndNullForEmpty() {
        #expect(kk_list_maxOrNull(makeList([3, 1, 4, 2])) == 4)
        #expect(kk_list_maxOrNull(makeList([])) == runtimeNullSentinelInt)
    }

    @Test
    func testMinByOrNullReturnsElementWithSmallestSelectorAndNullOnEmpty() {
        let result = kk_list_minByOrNull(
            makeList([5, 2, 3]),
            unsafeBitCast(countEven, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(result == 5)

        let emptyResult = kk_list_minByOrNull(
            makeList([]),
            unsafeBitCast(countEven, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(emptyResult == runtimeNullSentinelInt)
    }

    @Test
    func testMaxOfWithOrNullReturnsLargestTransformedValueAndNullForEmpty() {
        var thrown = 0
        let result = kk_list_maxOfWithOrNull(
            makeList([-3, 1, 2]),
            unsafeBitCast(maxOfWithOrNullNaturalComparator, to: Int.self),
            0,
            unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
            0,
            &thrown
        )

        #expect(result == 9)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_maxOfWithOrNull(
                makeList([]),
                unsafeBitCast(maxOfWithOrNullNaturalComparator, to: Int.self),
                0,
                unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
                0,
                &thrown
            ) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testMinOfWithReturnsSmallestTransformedValueAndThrowsOnEmpty() {
        var thrown = 0
        let result = kk_list_minOfWith(
            makeList([-3, 1, 2]),
            unsafeBitCast(maxOfWithNaturalComparator, to: Int.self),
            0,
            unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
            0,
            &thrown
        )

        #expect(result == 1)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_minOfWith(
                makeList([]),
                unsafeBitCast(maxOfWithNaturalComparator, to: Int.self),
                0,
                unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
                0,
                &thrown
            ) == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMinOfWithOrNullReturnsSmallestTransformedValueAndNullForEmpty() {
        var thrown = 0
        let result = kk_list_minOfWithOrNull(
            makeList([-3, 1, 2]),
            unsafeBitCast(maxOfWithOrNullNaturalComparator, to: Int.self),
            0,
            unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
            0,
            &thrown
        )

        #expect(result == 1)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_minOfWithOrNull(
                makeList([]),
                unsafeBitCast(maxOfWithOrNullNaturalComparator, to: Int.self),
                0,
                unsafeBitCast(maxOfWithOrNullSquareValue, to: Int.self),
                0,
                &thrown
            ) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testMaxWithReturnsLargestElementAndThrowsOnEmpty() {
        var thrown = 0
        #expect(kk_list_maxWith(makeList([3, 1, 4, 2]), unsafeBitCast(maxWithNaturalComparator, to: Int.self), 0, &thrown) == 4)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_maxWith(makeList([]), unsafeBitCast(maxWithNaturalComparator, to: Int.self), 0, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMinOfWithReturnsComparatorSelectedValueAndThrowsOnEmpty() {
        var thrown = 0
        let result = kk_list_minOfWith(
            makeList([5, 2, 3]),
            unsafeBitCast(reverseIntComparator, to: Int.self),
            0,
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0)
        #expect(result == 50)

        thrown = 0
        let emptyResult = kk_list_minOfWith(
            makeList([]),
            unsafeBitCast(reverseIntComparator, to: Int.self),
            0,
            unsafeBitCast(valueTimesTen, to: Int.self),
            0,
            &thrown
        )
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testListElementAtReturnsElementAndThrowsWhenOutOfBounds() {
        let source = makeList([10, 20, 30])

        var thrown = -1
        #expect(kk_list_elementAt(source, 1, &thrown) == 20)
        #expect(thrown == 0)

        thrown = 0
        #expect(kk_list_elementAt(source, 5, &thrown) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testListElementAtOrNullReturnsElementOrNullSentinel() {
        let source = makeList([10, 20, 30])

        #expect(kk_list_elementAtOrNull(source, 1) == 20)
        #expect(kk_list_elementAtOrNull(source, 5) == runtimeNullSentinelInt)
    }

    @Test
    func testCollectionMapNotNullPassesSentinelInputsToTransform() {
        let source = makeList([1, runtimeNullSentinelInt, 3])

        let listMapped = kk_list_mapNotNull(source, unsafeBitCast(mapSentinelToValue, to: Int.self), 0, nil)
        #expect(listElements(listMapped) == [2, 99, 6])

    }

    @Test
    func testIterableFirstNotNullOfReturnsFirstNonNullTransformResult() {
        var thrown = 0
        let listSource = makeList([1, 2, 4])
        let listResult = kk_iterable_firstNotNullOf(
            listSource,
            unsafeBitCast(firstNonNullEvenTimesTen, to: Int.self),
            0,
            &thrown
        )

        #expect(listResult == 20)
        #expect(thrown == 0)

        let setSource = kk_set_of(makeArray([1, 3, 4]), 3)
        let setResult = kk_iterable_firstNotNullOf(
            setSource,
            unsafeBitCast(firstNonNullEvenTimesTen, to: Int.self),
            0,
            &thrown
        )

        #expect(setResult == 40)
        #expect(thrown == 0)
    }

    @Test
    func testIterableFirstNotNullOfThrowsWhenEveryTransformResultIsNull() {
        var thrown = 0
        let source = makeList([1, 3, 5])

        let result = kk_iterable_firstNotNullOf(
            source,
            unsafeBitCast(alwaysNullTransform, to: Int.self),
            0,
            &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testCollectionMapNotNullPreservesZeroResults() {
        let source = makeList([0, 1, 2])

        let listMapped = kk_list_mapNotNull(source, unsafeBitCast(identityMapValue, to: Int.self), 0, nil)
        #expect(listElements(listMapped) == [0, 1, 2])

    }

    @Test
    func testIterableFirstNotNullOfOrNullReturnsFirstNonNullTransformResult() {
        let source = makeList([1, 2, 4])
        let result = kk_iterable_firstNotNullOfOrNull(
            source,
            unsafeBitCast(firstNullableEvenTimesTen, to: Int.self),
            0,
            nil
        )
        #expect(result == 20)

        let setSource = kk_set_of(makeArray([4]), 1)
        let setResult = kk_iterable_firstNotNullOfOrNull(
            setSource,
            unsafeBitCast(firstNullableEvenTimesTen, to: Int.self),
            0,
            nil
        )
        #expect(setResult == 40)
    }

    @Test
    func testIterableFirstNotNullOfOrNullReturnsNullWhenEveryTransformResultIsNull() {
        let source = makeList([1, 3, 5])
        let result = kk_iterable_firstNotNullOfOrNull(
            source,
            unsafeBitCast(alwaysNullTransform, to: Int.self),
            0,
            nil
        )
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
    func testIterableFirstNotNullOfOrNullPropagatesThrowingLambda() {
        let source = makeList([1, 2, 3])
        var thrown = 0

        let result = kk_iterable_firstNotNullOfOrNull(
            source,
            unsafeBitCast(throwingHOFLambda, to: Int.self),
            0,
            &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testIterableFirstNotNullOfOrNullAcceptsArrayReceiver() {
        let arraySource = makeArray([1, 2, 4])
        let result = kk_iterable_firstNotNullOfOrNull(
            arraySource,
            unsafeBitCast(firstNullableEvenTimesTen, to: Int.self),
            0,
            nil
        )
        #expect(result == 20)

        let emptyArray = makeArray([1, 3, 5])
        let nullResult = kk_iterable_firstNotNullOfOrNull(
            emptyArray,
            unsafeBitCast(alwaysNullTransform, to: Int.self),
            0,
            nil
        )
        #expect(nullResult == runtimeNullSentinelInt)
    }

    @Test
    func testSortedByWithStringKeyHandlesNonIntegerComparison() {
        let source = makeList([makeRuntimeStringRaw("b"), makeRuntimeStringRaw("a"), makeRuntimeStringRaw("c")])

        let sorted = kk_list_sortedBy(
            source,
            unsafeBitCast(sortBySelfStringValue, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(listElements(sorted).map(runtimeStringValue) == ["a", "b", "c"])

        let sortedDesc = kk_list_sortedByDescending(
            source,
            unsafeBitCast(sortBySelfStringValue, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        #expect(listElements(sortedDesc).map(runtimeStringValue) == ["c", "b", "a"])
    }

    @Test
    func testMutableListSortByStringKeyMutatesInPlace() {
        // Use different string values to ensure different handles for proper sorting
        let strA = makeRuntimeStringRaw("a")
        let strB = makeRuntimeStringRaw("b")
        let strC = makeRuntimeStringRaw("c")
        let source = makeList([strB, strA, strC])
        _ = kk_mutable_list_sortBy(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(source).map(runtimeStringValue) == ["a", "b", "c"])

        _ = kk_mutable_list_sortByDescending(source, unsafeBitCast(sortBySelfStringValue, to: Int.self), 0, nil as UnsafeMutablePointer<Int>?)
        #expect(listElements(source).map(runtimeStringValue) == ["c", "b", "a"])
    }

    @Test
    func testMutableListShuffleAndReverse() {
        // Test shuffle
        let source = makeList([1, 2, 3, 4, 5])
        let originalElements = listElements(source)

        _ = kk_mutable_list_shuffle(source)
        let shuffledElements = listElements(source)

        // Should have same elements but different order (most likely)
        #expect(shuffledElements.count == originalElements.count)
        #expect(Set(shuffledElements) == Set(originalElements))

        // Test reverse
        _ = kk_mutable_list_reverse(source)
        let reversedElements = listElements(source)

        // Should be the reverse of shuffled
        #expect(reversedElements == shuffledElements.reversed())

        // Test with empty list
        let emptyList = makeList([])
        _ = kk_mutable_list_shuffle(emptyList)
        #expect(listElements(emptyList) == [])

        _ = kk_mutable_list_reverse(emptyList)
        #expect(listElements(emptyList) == [])

        // Test with single element
        let singleList = makeList([42])
        _ = kk_mutable_list_shuffle(singleList)
        #expect(listElements(singleList) == [42])

        _ = kk_mutable_list_reverse(singleList)
        #expect(listElements(singleList) == [42])

        // Test with duplicate elements
        let duplicateList = makeList([5, 2, 5, 2, 5])
        _ = kk_mutable_list_reverse(duplicateList)
        #expect(listElements(duplicateList) == [5, 2, 5, 2, 5].reversed())
    }

    @Test
    func testIterableAnyShortCircuitsAcrossCollectionKindsAndNoArgOverload() {
        let listSource = makeList([1, 2, 3, 4])

        gHOFState.reset()
        #expect(kk_iterable_any(listSource, unsafeBitCast(anyGtTwoCounting, to: Int.self), 0, nil) == 1)
        #expect(gHOFState.callsSnapshot() == 3)

        let setSource = kk_set_of(makeArray([1, 2]), 2)
        gHOFState.reset()
        #expect(kk_iterable_any(setSource, unsafeBitCast(anyGtTwoCounting, to: Int.self), 0, nil) == 0)
        #expect(gHOFState.callsSnapshot() == 2)

        #expect(kk_iterable_any(listSource, 0, 0, nil) == 1)
        #expect(kk_iterable_any(makeList([]), 0, 0, nil) == 0)
    }

    @Test
    func testIterableAnyPropagatesThrowingLambda() {
        let source = makeList([1])
        var thrown = 0

        let result = kk_iterable_any(source, unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown)

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testIterableAllShortCircuitsAcrossCollectionKinds() {
        let listSource = makeList([1, 2, 3, 4])

        gHOFState.reset()
        #expect(kk_iterable_all(listSource, unsafeBitCast(allLtThreeCounting, to: Int.self), 0, nil) == 0)
        #expect(gHOFState.callsSnapshot() == 3)

        let setSource = kk_set_of(makeArray([1, 2]), 2)
        gHOFState.reset()
        #expect(kk_iterable_all(setSource, unsafeBitCast(allLtThreeCounting, to: Int.self), 0, nil) == 1)
        #expect(gHOFState.callsSnapshot() == 2)

        gHOFState.reset()
        #expect(kk_iterable_all(makeList([]), unsafeBitCast(allLtThreeCounting, to: Int.self), 0, nil) == 1)
        #expect(gHOFState.callsSnapshot() == 0)
    }

    @Test
    func testIterableAllPropagatesThrowingLambda() {
        let source = makeList([1])
        var thrown = 0

        let result = kk_iterable_all(source, unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown)

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testCountFirstLastFindAndEmptyFailures() {
        let source = makeList([1, 2, 3, 4])

        #expect(kk_list_first(source, 0, 0, nil) == 1)
        #expect(kk_list_last(source, 0, 0, nil) == 4)
        #expect(kk_list_first(source, unsafeBitCast(firstGreaterThanTwo, to: Int.self), 0, nil) == 3)
        #expect(kk_list_last(source, unsafeBitCast(lastLessThanThree, to: Int.self), 0, nil) == 2)

        var thrown = 0
        #expect(kk_list_first(makeList([]), 0, 0, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)

        thrown = 0
        #expect(kk_list_last(makeList([]), 0, 0, &thrown) == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupByPreservesKeyAndBucketOrder() {
        let source = makeList([3, 1, 4, 2, 5])
        let grouped = kk_list_groupBy(source, unsafeBitCast(groupByParity, to: Int.self), 0, nil)

        #expect(mapKeys(grouped) == [1, 0])
        #expect(listElements(kk_map_get(grouped, 1)) == [3, 1, 5])
        #expect(listElements(kk_map_get(grouped, 0)) == [4, 2])
    }

    @Test
    func testGroupByUsesValueEqualityForStringKeys() {
        let source = makeList([1, 2, 3, 4])
        let grouped = kk_list_groupBy(source, unsafeBitCast(groupingByStringKey, to: Int.self), 0, nil)

        #expect(mapKeys(grouped).map(runtimeStringValue) == ["odd", "even"])
        #expect(listElements(kk_map_get(grouped, runtimeStringRaw("odd"))) == [1, 3])
        #expect(listElements(kk_map_get(grouped, runtimeStringRaw("even"))) == [2, 4])
    }

    @Test
    func testGroupByTransformUsesValueEqualityForStringKeys() {
        let source = makeList([1, 2, 3, 4])
        let grouped = kk_list_groupByTransform(
            source,
            unsafeBitCast(groupingByStringKey, to: Int.self), 0,
            unsafeBitCast(mapTimesTwo, to: Int.self), 0,
            nil
        )

        #expect(mapKeys(grouped).map(runtimeStringValue) == ["odd", "even"])
        #expect(listElements(kk_map_get(grouped, runtimeStringRaw("odd"))) == [2, 6])
        #expect(listElements(kk_map_get(grouped, runtimeStringRaw("even"))) == [4, 8])
    }

    @Test
    func testMapForEachFilterAndMapUsePairEntries() {
        let keys = makeArray([1, 2, 3])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        _ = kk_map_forEach(map, unsafeBitCast(accumulateEntryScore, to: Int.self), 0, nil)
        #expect(gHOFState.sumSnapshot() == 123)

        var thrown = 0
        #expect(kk_map_get(map, 2) == 21)
        let defaulted = kk_map_withDefault(map, unsafeBitCast(mapTimesTwo, to: Int.self), 0)
        #expect(kk_map_implicit_default(defaulted, 9, &thrown) == 18)
        #expect(thrown == 0)
        #expect(kk_map_implicit_default(map, 9, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)

        let mapped = kk_map_map(map, unsafeBitCast(mapEntrySum, to: Int.self), 0, nil)
        #expect(listElements(mapped) == [11, 23, 35])

        let filtered = kk_map_filter(map, unsafeBitCast(keepEvenValueEntries, to: Int.self), 0, nil)
        #expect(mapKeys(filtered) == [1, 3])
        #expect(kk_map_get(filtered, 1) == 10)
        #expect(kk_map_get(filtered, 3) == 32)

        let filteredValues = kk_map_filterValues(map, unsafeBitCast(countEven, to: Int.self), 0, nil)
        #expect(mapKeys(filteredValues) == [1, 3])
        #expect(kk_map_get(filteredValues, 1) == 10)
        #expect(kk_map_get(filteredValues, 3) == 32)
    }

    @Test
    func testMapFilterKeysPassesOnlyKeysToPredicate() {
        let keys = makeArray([1, 2, 3])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        let filtered = kk_map_filterKeys(map, unsafeBitCast(keepOddMapKeys, to: Int.self), 0, nil)

        #expect(mapKeys(filtered) == [1, 3])
        #expect(kk_map_get(filtered, 1) == 10)
        #expect(kk_map_get(filtered, 3) == 32)
    }

    @Test
    func testMapValuesAndMapKeysUsePairEntries() {
        let keys = makeArray([1, 2, 1])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        let mappedValues = kk_map_mapValues(map, unsafeBitCast(mapEntryValueTimesTen, to: Int.self), 0, nil)
        #expect(mapKeys(mappedValues) == [1, 2])
        #expect(kk_map_get(mappedValues, 1) == 320)
        #expect(kk_map_get(mappedValues, 2) == 210)

        let mappedKeys = kk_map_mapKeys(map, unsafeBitCast(mapEntryKeyPlusHundred, to: Int.self), 0, nil)
        #expect(mapKeys(mappedKeys) == [101, 102])
        #expect(kk_map_get(mappedKeys, 101) == 32)
        #expect(kk_map_get(mappedKeys, 102) == 21)
    }

    @Test
    func testCollectionToListCopiesListAndSetElements() {
        let listSource = makeList([1, 2, 3])
        let listCopy = kk_collection_toList(listSource)
        #expect(listElements(listCopy) == [1, 2, 3])
        #expect(listElements(listSource) == [1, 2, 3])

        let setSource = registerRuntimeObject(RuntimeSetBox(elements: [3, 1, 2]))
        #expect(listElements(kk_collection_toList(setSource)) == [3, 1, 2])
    }

    @Test
    func testMapKeysToMutatesDestinationAndReturnsIt() {
        let keys = makeArray([1, 2])
        let values = makeArray([10, 21])
        let map = kk_map_of(keys, values, 2)
        let dest = makeMutableMap(keys: [10, 0], values: [900, 1])

        var thrown = 0
        let result = kk_map_mapKeysTo(
            map,
            dest,
            unsafeBitCast(mapEntryKeyTimesTen, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == dest)
        #expect(mapKeys(dest) == [10, 0, 20])
        #expect(kk_map_get(dest, 10) == 10)
        #expect(kk_map_get(dest, 0) == 1)
        #expect(kk_map_get(dest, 20) == 21)
    }

    @Test
    func testMapValuesToMutatesDestinationAndReturnsIt() {
        let keys = makeArray([1, 2])
        let values = makeArray([10, 21])
        let map = kk_map_of(keys, values, 2)
        let dest = makeMutableMap(keys: [0], values: [5])

        var thrown = 0
        let result = kk_map_mapValuesTo(
            map,
            dest,
            unsafeBitCast(mapEntryValuePlusOne, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == dest)
        #expect(mapKeys(dest) == [0, 1, 2])
        #expect(kk_map_get(dest, 0) == 5)
        #expect(kk_map_get(dest, 1) == 11)
        #expect(kk_map_get(dest, 2) == 22)
    }

    @Test
    func testMapEntriesMaterializesKeyValuePairs() {
        let keys = makeArray([1, 2, 1])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        let entries = setElements(kk_map_entries(map))
        #expect(entries.count == 2)
        #expect(entries.map { kk_pair_first($0) } == mapKeys(map))
        #expect(entries.map { kk_pair_second($0) } == mapValues(map))
    }

    @Test
    func testMapKeysAndValuesMaterializeCollections() {
        let keys = makeArray([1, 2, 1])
        let values = makeArray([10, 21, 32])
        let map = kk_map_of(keys, values, 3)

        #expect(setElements(kk_map_keys(map)) == [1, 2])
        #expect(listElements(kk_map_values(map)) == [32, 21])
    }

    @Test
    func testHashMapIsEmptyReflectsMutations() {
        let map = kk_hash_map_of(0, 0, 0)
        var thrown = 0
        _ = kk_mutable_map_put(map, 1, 10, &thrown)

        #expect(thrown == 0)
        #expect(kk_unbox_bool(kk_map_is_empty(map)) == 0)
    }

    @Test
    func testMapOfPairsNormalizesLinkedFactorySpreadEntries() {
        // KSP-954: linkedMapOf(*pairs) lowers to __kk_map_of_pairs with the
        // spread varargs packed into a single Pair array.
        let pairs = makeArray([
            kk_pair_new(1, 10),
            kk_pair_new(2, 20),
            kk_pair_new(1, 30),
        ])
        let map = kk_map_of_pairs(pairs, 3)

        #expect(mapKeys(map) == [1, 2])
        #expect(mapValues(map) == [30, 20])
    }

    @Test
    func testMapPlusNormalizesMismatchedEntriesBeforeUpdate() {
        let corruptedMap = registerRuntimeObject(RuntimeMapBox(keys: [1, 2, 3], values: [10, 20]))
        let updated = kk_map_plus(corruptedMap, kk_pair_new(3, 99))

        #expect(mapKeys(updated) == [1, 2, 3])
        #expect(mapValues(updated) == [10, 20, 99])
    }

    @Test
    func testMapMinusNormalizesMismatchedEntriesBeforeRemoval() {
        let corruptedMap = registerRuntimeObject(RuntimeMapBox(keys: [1, 2, 3], values: [10, 20]))
        let updated = kk_map_minus(corruptedMap, 2)

        #expect(mapKeys(updated) == [1])
        #expect(mapValues(updated) == [10])
    }

    @Test
    func testMapImplicitDefaultPropagatesThrowingDefaultLambda() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        let defaulted = kk_map_withDefault(map, unsafeBitCast(throwForMapDefault, to: Int.self), 0)

        gHOFState.reset()
        var thrown = 0
        let result = kk_map_implicit_default(defaulted, 1, &thrown)

        #expect(gHOFState.callsSnapshot() == 1)
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMutableMapPutAllNormalizesCorruptedTargetEntryArrays() {
        let target = registerRuntimeObject(RuntimeMapBox(keys: [1, 2], values: [10]))
        let source = registerRuntimeObject(RuntimeMapBox(keys: [2, 3], values: [20, 30]))

        _ = kk_mutable_map_putAll(target, source)

        #expect(mapKeys(target) == [1, 2, 3])
        #expect(mapValues(target) == [10, 20, 30])
    }

    @Test
    func testMutableSetAddAllAcceptsSetInput() {
        let target = registerRuntimeObject(RuntimeSetBox(elements: [1, 2]))
        let source = registerRuntimeObject(RuntimeSetBox(elements: [2, 3, 4]))

        let modified = kk_mutable_set_addAll(target, source)

        #expect(kk_unbox_bool(modified) == 1)
        #expect(setElements(target) == [1, 2, 3, 4])
    }

    @Test
    func testMutableCollectionAddHandlesListAndSetTargets() {
        let listTarget = makeList([1, 2])

        #expect(kk_unbox_bool(kk_mutable_collection_add(listTarget, 3)) == 1)
        #expect(listElements(listTarget) == [1, 2, 3])

        let setTarget = registerRuntimeObject(RuntimeSetBox(elements: [1, 2]))

        #expect(kk_unbox_bool(kk_mutable_collection_add(setTarget, 2)) == 0)
        #expect(kk_unbox_bool(kk_mutable_collection_add(setTarget, 3)) == 1)
        #expect(setElements(setTarget) == [1, 2, 3])
    }

    @Test
    func testMutableCollectionRemoveAndClearHandleListAndSetTargets() {
        let listTarget = makeList([1, 2, 3])

        #expect(kk_unbox_bool(kk_mutable_collection_remove(listTarget, 2)) == 1)
        #expect(kk_unbox_bool(kk_mutable_collection_remove(listTarget, 9)) == 0)
        #expect(listElements(listTarget) == [1, 3])
        #expect(kk_mutable_collection_clear(listTarget) == 0)
        #expect(listElements(listTarget) == [])

        let setTarget = registerRuntimeObject(RuntimeSetBox(elements: [1, 2]))

        #expect(kk_unbox_bool(kk_mutable_collection_remove(setTarget, 1)) == 1)
        #expect(kk_unbox_bool(kk_mutable_collection_remove(setTarget, 1)) == 0)
        #expect(setElements(setTarget) == [2])
        #expect(kk_mutable_collection_clear(setTarget) == 0)
        #expect(setElements(setTarget) == [])
    }

    @Test
    func testMutableCollectionBulkRemovalHandlesListAndSetTargets() {
        let listTarget = makeList([1, 2, 3, 2])

        #expect(kk_unbox_bool(kk_mutable_collection_removeAll(listTarget, makeList([2]))) == 1)
        #expect(listElements(listTarget) == [1, 3])
        #expect(kk_unbox_bool(kk_mutable_collection_retainAll(listTarget, makeList([3, 4]))) == 1)
        #expect(listElements(listTarget) == [3])
        #expect(kk_unbox_bool(kk_mutable_collection_retainAll(listTarget, makeList([3, 4]))) == 0)

        let setTarget = registerRuntimeObject(RuntimeSetBox(elements: [1, 2, 3]))

        #expect(kk_unbox_bool(kk_mutable_collection_removeAll(setTarget, makeList([1]))) == 1)
        #expect(setElements(setTarget) == [2, 3])
        #expect(kk_unbox_bool(kk_mutable_collection_retainAll(setTarget, makeList([3]))) == 1)
        #expect(setElements(setTarget) == [3])
        #expect(kk_unbox_bool(kk_mutable_collection_retainAll(setTarget, makeList([3]))) == 0)
    }

    @Test
    func testCollectionAndIterableToMutableListCopyElements() {
        let listSource = makeList([1, 2, 3])
        let collectionCopy = kk_collection_toMutableList(listSource)

        #expect(listElements(collectionCopy) == [1, 2, 3])
        #expect(kk_unbox_bool(kk_mutable_list_add(collectionCopy, 4, nil)) == 1)
        #expect(listElements(listSource) == [1, 2, 3])
        #expect(listElements(collectionCopy) == [1, 2, 3, 4])

        let setSource = registerRuntimeObject(RuntimeSetBox(elements: [3, 1, 2]))
        let iterableCopy = kk_collection_toMutableList(setSource)

        #expect(listElements(iterableCopy) == [3, 1, 2])
        #expect(kk_unbox_bool(kk_mutable_list_add(iterableCopy, 9, nil)) == 1)
        #expect(setElements(setSource) == [3, 1, 2])
        #expect(listElements(iterableCopy) == [3, 1, 2, 9])
    }

    @Test
    func testIterableToMutableSetDeduplicatesAndCopiesElements() {
        let listSource = makeList([3, 1, 2, 1])
        let listCopy = kk_iterable_toMutableSet(listSource)

        #expect(setElements(listCopy) == [3, 1, 2])
        #expect(kk_unbox_bool(kk_mutable_set_add(listCopy, 9, nil)) == 1)
        #expect(listElements(listSource) == [3, 1, 2, 1])
        #expect(setElements(listCopy) == [3, 1, 2, 9])

        let setSource = registerRuntimeObject(RuntimeSetBox(elements: [2, 3, 2, 1]))
        let setCopy = kk_iterable_toMutableSet(setSource)

        #expect(setElements(setCopy) == [2, 3, 1])
        #expect(kk_unbox_bool(kk_mutable_set_add(setCopy, 4, nil)) == 1)
        #expect(setElements(setSource) == [2, 3, 2, 1])
        #expect(setElements(setCopy) == [2, 3, 1, 4])
    }

    @Test
    func testCollectionToTypedArrayCopiesListAndSetElements() {
        let listSource = makeList([1, 2, 3])
        let listArray = kk_collection_toTypedArray(listSource)

        #expect(arrayElements(listArray) == [1, 2, 3])
        runtimeArrayBox(from: listArray)?.elements[0] = 9
        #expect(listElements(listSource) == [1, 2, 3])
        #expect(arrayElements(listArray) == [9, 2, 3])

        let setSource = registerRuntimeObject(RuntimeSetBox(elements: [3, 1, 2]))

        #expect(arrayElements(kk_collection_toTypedArray(setSource)) == [3, 1, 2])
    }

    @Test
    func testBoolAbiForCollectionHelpersReturnsRaw() {
        let source = makeList([1, 2, 3])
        #expect(kk_unbox_bool(kk_list_is_empty(source)) == 0)
        #expect(kk_unbox_bool(kk_list_is_empty(makeList([]))) == 1)

        let set = kk_set_of(makeArray([1, 2, 3]), 3)
        #expect(kk_unbox_bool(kk_set_contains(set, 2)) == 1)
        #expect(kk_unbox_bool(kk_set_contains(set, 9)) == 0)

        let keys = makeArray([1, 2])
        let values = makeArray([10, 20])
        let map = kk_map_of(keys, values, 2)
        #expect(kk_unbox_bool(kk_map_is_empty(map)) == 0)
        #expect(kk_unbox_bool(kk_map_is_empty(kk_map_of(0, 0, 0))) == 1)
    }

    @Test
    func testListUnzipSplitsPairElementsIntoLists() {
        let source = makeList([
            kk_pair_new(1, 10),
            kk_pair_new(2, 20),
            kk_pair_new(3, 30),
        ])

        let result = kk_list_unzip(source)
        let first = kk_pair_first(result)
        let second = kk_pair_second(result)

        #expect(listElements(first) == [1, 2, 3])
        #expect(listElements(second) == [10, 20, 30])
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
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

    private func mapValues(_ mapRaw: Int) -> [Int] {
        runtimeMapBox(from: mapRaw)?.values ?? []
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

    @Test
    func testListAssociateBuildsMapAndOverwritesDuplicateKeys() {
        let source = makeList([1, 2, 3])

        let result = kk_list_associate(
            source,
            unsafeBitCast(associateParityTimesTen, to: Int.self), 0, nil
        )

        #expect(mapKeys(result) == [1, 0])
        #expect(kk_map_get(result, 1) == 30)
        #expect(kk_map_get(result, 0) == 20)
    }

    @Test
    func testListAssociatePropagatesThrowingLambda() {
        let source = makeList([1])
        var thrown = 0

        let result = kk_list_associate(
            source,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testAssociateByToBasic() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil
        )
        // Returns same destination handle
        #expect(result == dest)
        // Keys are lambda results (value*2), values are elements
        #expect(mapKeys(result) == [2, 4, 6])
    }

    @Test
    func testAssociateByToDuplicateKeysLastWriteWins() {
        // Elements 1 and 3 both have key = parity 1; 2 has key = parity 0
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Last-write-wins: key 1 -> last elem with odd parity is 3, key 0 -> 2
        #expect(mapKeys(result) == [1, 0])
        #expect(kk_map_get(result, 1) == 3)
        #expect(kk_map_get(result, 0) == 2)
    }

    @Test
    func testListAssociateByBuildsMapAndOverwritesDuplicateKeys() {
        let source = makeList([1, 2, 3])

        let result = kk_list_associateBy(
            source,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )

        #expect(mapKeys(result) == [1, 0])
        #expect(kk_map_get(result, 1) == 3)
        #expect(kk_map_get(result, 0) == 2)
    }

    @Test
    func testListAssociateByTransformBuildsMapAndOverwritesDuplicateKeys() {
        let source = makeList([1, 2, 3])

        let result = kk_list_associateByTransform(
            source,
            unsafeBitCast(groupByParity, to: Int.self), 0,
            unsafeBitCast(valueTimesTen, to: Int.self), 0,
            nil
        )

        #expect(mapKeys(result) == [1, 0])
        #expect(kk_map_get(result, 1) == 30)
        #expect(kk_map_get(result, 0) == 20)
    }

    @Test
    func testListAssociateByPropagatesThrowingLambda() {
        let source = makeList([1])
        var thrown = 0

        let result = kk_list_associateBy(
            source,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testAssociateByToPrePopulatedDestination() {
        // Pre-populate destination with key=100 -> value=999
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [100], values: [999]))
        let source = makeList([5, 10])

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(mapTimesTwo, to: Int.self), 0, nil
        )
        // Existing entry preserved, new entries added
        #expect(result == dest)
        #expect(kk_map_get(result, 100) == 999)
        #expect(mapKeys(result).contains(10))  // key for elem 5
        #expect(mapKeys(result).contains(20))  // key for elem 10
    }

    @Test
    func testListAssociateWithBuildsMapValues() {
        let source = makeList([1, 2, 3])

        let result = kk_list_associateWith(
            source,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )

        #expect(mapKeys(result) == [1, 2, 3])
        #expect(kk_map_get(result, 1) == 10)
        #expect(kk_map_get(result, 2) == 20)
        #expect(kk_map_get(result, 3) == 30)
    }

    @Test
    func testListAssociateWithPropagatesThrowingLambda() {
        let source = makeList([1])
        var thrown = 0

        let result = kk_list_associateWith(
            source,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testAssociateWithToBasic() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        // Keys are elements, values are lambda results (elem*10)
        #expect(result == dest)
        #expect(kk_map_get(result, 1) == 10)
        #expect(kk_map_get(result, 2) == 20)
        #expect(kk_map_get(result, 3) == 30)
    }

    @Test
    func testAssociateWithToDuplicateKeysLastWriteWins() {
        let source = makeList([1, 1, 2])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        // Duplicate key 1: last write wins (both map to 10, so same value)
        #expect(mapKeys(result) == [1, 2])
        #expect(kk_map_get(result, 1) == 10)
        #expect(kk_map_get(result, 2) == 20)
    }

    @Test
    func testAssociateWithToPrePopulatedDestination() {
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [100], values: [999]))
        let source = makeList([5])

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(valueTimesTen, to: Int.self), 0, nil
        )
        #expect(result == dest)
        #expect(kk_map_get(result, 100) == 999)
        #expect(kk_map_get(result, 5) == 50)
    }

    @Test
    func testGroupByToBasic() {
        let source = makeList([3, 1, 4, 2, 5])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(groupByParity, to: Int.self), 0, nil
        )
        // Same destination handle returned
        #expect(result == dest)
        // Odd elements (parity 1) grouped, even elements (parity 0) grouped
        #expect(mapKeys(result) == [1, 0])
        #expect(listElements(kk_map_get(result, 1)) == [3, 1, 5])
        #expect(listElements(kk_map_get(result, 0)) == [4, 2])
    }

    @Test
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
        #expect(result == dest)
        #expect(listElements(kk_map_get(result, 1)) == [100, 3, 5])
    }

    @Test
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
        #expect(listElements(kk_map_get(result, 0)) == [10, 2])
        #expect(listElements(kk_map_get(result, 1)) == [1])
    }

    @Test
    func testMinByReturnsElementWithSmallestSelectorAndThrowsOnEmpty() {
        var thrown = 0

        let minResult = kk_list_minBy(
            makeList([5, 2, 3]),
            unsafeBitCast(countEven, to: Int.self),
            0,
            &thrown
        )
        #expect(minResult == 5)
        #expect(thrown == 0)

        let emptyResult = kk_list_minBy(
            makeList([]),
            unsafeBitCast(countEven, to: Int.self),
            0,
            &thrown
        )
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testMinReturnsSmallestElementAndThrowsOnEmpty() {
        var thrown = 0

        let minResult = kk_list_min(makeList([3, 1, 4, 2]), &thrown)
        #expect(minResult == 1)
        #expect(thrown == 0)

        let emptyResult = kk_list_min(makeList([]), &thrown)
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    // MARK: - Throwing lambda tests for *To functions

    @Test
    func testAssociateByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_associateByTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testAssociateWithToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_associateWithTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testGroupByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let source = makeList([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_list_groupByTo(
            source, dest,
            unsafeBitCast(throwingHOFLambda, to: Int.self), 0, &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

}
#endif
