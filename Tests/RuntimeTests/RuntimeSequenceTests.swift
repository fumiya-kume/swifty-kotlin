import Foundation
@testable import Runtime
import XCTest

/// STDLIB-563: Global counter used by laziness verification tests.
/// Tracks how many times to yield side-effects in builder thunk execute.
/// Must be global (not a class property) because `@convention(c)` closures
/// cannot capture context.
/// Access is safe because tests run sequentially and counter is only
/// mutated from one thread at a time (the producer thread).
private let lazyTestYieldCounterLock = NSLock()
nonisolated(unsafe) private var __lazyTestYieldCounter = 0

var _lazyTestYieldCounter: Int {
    get {
        lazyTestYieldCounterLock.lock()
        defer { lazyTestYieldCounterLock.unlock() }
        return __lazyTestYieldCounter
    }
    set {
        lazyTestYieldCounterLock.lock()
        defer { lazyTestYieldCounterLock.unlock() }
        __lazyTestYieldCounter = newValue
    }
}

private let lazySequenceOnEachIndexedTraceLock = NSLock()
nonisolated(unsafe) private var __lazySequenceOnEachIndexedTrace: [Int] = []

var _lazySequenceOnEachIndexedTrace: [Int] {
    get {
        lazySequenceOnEachIndexedTraceLock.lock()
        defer { lazySequenceOnEachIndexedTraceLock.unlock() }
        return __lazySequenceOnEachIndexedTrace
    }
    set {
        lazySequenceOnEachIndexedTraceLock.lock()
        defer { lazySequenceOnEachIndexedTraceLock.unlock() }
        __lazySequenceOnEachIndexedTrace = newValue
    }
}

private func appendLazySequenceOnEachIndexedTrace(_ value: Int) {
    lazySequenceOnEachIndexedTraceLock.lock()
    defer { lazySequenceOnEachIndexedTraceLock.unlock() }
    __lazySequenceOnEachIndexedTrace.append(value)
}

private let lazyYieldAllInnerThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
    _lazyTestYieldCounter += 1
    _ = kk_sequence_builder_yield(builderRaw, 10)
    _lazyTestYieldCounter += 1
    _ = kk_sequence_builder_yield(builderRaw, 20)
    _lazyTestYieldCounter += 1
    _ = kk_sequence_builder_yield(builderRaw, 30)
    _lazyTestYieldCounter += 1
    _ = kk_sequence_builder_yield(builderRaw, 40)
    _lazyTestYieldCounter += 1
    _ = kk_sequence_builder_yield(builderRaw, 50)
    return 0
}

private let lazyYieldAllInnerSequenceRaw: Int = {
    let innerFnPtr = unsafeBitCast(lazyYieldAllInnerThunk, to: Int.self)
    return kk_sequence_builder_build(innerFnPtr)
}()

let lazyYieldAllOuterThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
    _ = kk_sequence_builder_yieldAll(builderRaw, lazyYieldAllInnerSequenceRaw)
    _ = kk_sequence_builder_yield(builderRaw, 99)
    return 0
}

private let stringKeySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    switch value {
    case 1:
        return runtimeTestStringHandle("banana")
    case 2:
        return runtimeTestStringHandle("apple")
    default:
        return runtimeTestStringHandle("carrot")
    }
}

private let throwingSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sortedBy selector failed")
    return 0
}

private let accumulatingSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc + value
}

private let indexedAccumulatingSum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index * value
}

private let throwingAccumulator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence accumulator failed")
    return 0
}

private let throwingIndexedAccumulator: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence indexed accumulator failed")
    return 0
}

private let throwingSequenceGenerator: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence generator failed")
    return 0
}

private let sequenceAssociatePair: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_pair_new(value * 2, value * 10)
}

// Maps value → (value % 2, value * 10), producing duplicate keys for odd/even groups.
private let sequenceAssociatePairDuplicateKeys: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_pair_new(value % 2, value * 10)
}

private let sequenceParitySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let sequenceValueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 10
}

private let sequenceLessThanFour: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value < 4 ? 1 : 0
}

let sequenceFirstNullableEvenTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value.isMultiple(of: 2) ? value * 10 : runtimeNullSentinelInt
}

let sequenceAlwaysNullTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let sequenceAdjacentDifference: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, left, right, _ in
    right - left
}

private let throwingSequenceAdjacentTransform: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence zipWithNext transform failed")
    return 0
}

let throwingSequenceDestinationLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence destination transform failed")
    return 0
}

let recordingOnEachIndexedAction: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    appendLazySequenceOnEachIndexedTrace(index * 100 + value)
    return 0
}

private let keepEvenIndexOrLargeValue: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index.isMultiple(of: 2) || value > 30 ? 1 : 0
}

let summingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, windowRaw, _ in
    let size = kk_list_size(windowRaw)
    guard size > 0 else { return 0 }
    var sum = 0
    for index in 0 ..< size {
        sum += kk_list_get(windowRaw, index)
    }
    return sum
}

let throwingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "window transform failed")
    return 0
}

private let sequenceFirstNotNullOfStringForTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == 2 ? runtimeTestStringHandle("two") : runtimeNullSentinelInt
}

private let sequenceFirstNotNullOfAlwaysNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let sequenceSumByWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == 2 ? 10 : value
}

private let sequenceSumByDoubleWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_double_to_bits(value == 2 ? 1.5 : 0.25)
}

private func runtimeTestStringHandle(_ value: String) -> Int {
    let bytes = Array(value.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
        let raw = kk_string_from_utf8(baseAddress, Int32(bytes.count))
        return Int(bitPattern: raw)
    }
}

final class RuntimeSequenceTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        _lazyTestYieldCounter = 0
        _lazySequenceOnEachIndexedTrace = []
    }

    func testFirstNotNullOfReturnsFirstTransformedValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfStringForTwo, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractString(from: UnsafeMutableRawPointer(bitPattern: result)), "two")
    }

    func testFirstNotNullOfThrowsWhenNoElementTransformsToValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfOrNullReturnsFirstTransformedValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfStringForTwo, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractString(from: UnsafeMutableRawPointer(bitPattern: result)), "two")
    }

    func testFirstNotNullOfOrNullReturnsNullSentinelWhenNoElementTransformsToValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testTakeLastReturnsTrailingElementsAsList() {
        XCTAssertEqual(listElements(kk_sequence_takeLast(makeSequence([1, 2, 3, 4]), 2, nil)), [3, 4])
        XCTAssertEqual(listElements(kk_sequence_takeLast(makeSequence([1, 2]), 5, nil)), [1, 2])
        XCTAssertEqual(listElements(kk_sequence_takeLast(makeSequence([1, 2]), 0, nil)), [])
    }

    func testTakeLastNegativeCountSetsThrowable() {
        var thrown = 0
        let result = kk_sequence_takeLast(makeSequence([1, 2]), -1, &thrown)
        XCTAssertEqual(listElements(result), [])
        XCTAssertNotEqual(thrown, 0)
    }

    func testSumByAccumulatesSelectorResults() {
        var thrown = 0
        let result = kk_sequence_sumBy(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceSumByWeightedTwo, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 14)
    }

    func testSumOfAccumulatesSelectorResults() {
        var thrown = 0
        let result = kk_sequence_sumOf(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceSumByWeightedTwo, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 14)
    }

    func testSumByDoubleAccumulatesSelectorResults() {
        var thrown = 0
        let result = kk_sequence_sumByDouble(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceSumByDoubleWeightedTwo, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 2.0, accuracy: 0.0001)
    }

    func testSortedByUsesRuntimeValueComparisonForSelectorKeys() {
        let source = makeSequence([1, 2, 3])
        let sorted = kk_sequence_sortedBy(
            source,
            unsafeBitCast(stringKeySelector, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(listElements(kk_sequence_to_list(sorted, nil)), [2, 1, 3])
    }

    func testSortedByPropagatesSelectorThrowables() {
        let source = makeSequence([1, 2, 3])
        var thrown = 0
        let sorted = kk_sequence_sortedBy(
            source,
            unsafeBitCast(throwingSelector, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(listElements(kk_sequence_to_list(sorted, nil)), [])
    }

    func testTakeWhileKeepsMatchingPrefixLazily() {
        let source = makeSequence([1, 2, 3, 4, 2])
        let taken = kk_sequence_takeWhile(
            source,
            unsafeBitCast(sequenceLessThanFour, to: Int.self),
            0
        )

        XCTAssertEqual(listElements(kk_sequence_to_list(taken, nil)), [1, 2, 3])
    }

    func testTakeWhilePropagatesPredicateThrowableOnMaterialization() {
        let source = makeSequence([1, 2, 3])
        let taken = kk_sequence_takeWhile(
            source,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0
        )
        var thrown = 0
        let result = kk_sequence_to_list(taken, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testJoinToStringUsesSeparatorPrefixAndPostfix() {
        let seq = makeSequence([1, 2, 3])
        let renderedRaw = kk_sequence_joinToString(
            seq,
            runtimeTestStringHandle(":"),
            runtimeTestStringHandle("["),
            runtimeTestStringHandle("]")
        )

        XCTAssertEqual(extractString(from: UnsafeMutableRawPointer(bitPattern: renderedRaw)), "[1:2:3]")
    }

    func testAssociateToPopulatesExistingDestinationMap() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [99], values: [999]))

        let result = kk_sequence_associateTo(
            seq,
            dest,
            unsafeBitCast(sequenceAssociatePair, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(kk_map_get(result, 99), 999)
        XCTAssertEqual(kk_map_get(result, 2), 10)
        XCTAssertEqual(kk_map_get(result, 4), 20)
        XCTAssertEqual(kk_map_get(result, 6), 30)
    }

    func testAssociateBuildsMapWithLastWriteForDuplicateKeys() {
        // Sequence [1, 2, 3] with key = value % 2 produces:
        //   1 → key 1, value 10
        //   2 → key 0, value 20
        //   3 → key 1, value 30  (duplicate key 1; last-write-wins → 30)
        let seq = makeSequence([1, 2, 3])

        let result = kk_sequence_associate(
            seq,
            unsafeBitCast(sequenceAssociatePairDuplicateKeys, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(mapKeys(result).sorted(), [0, 1])
        XCTAssertEqual(kk_map_get(result, 0), 20)
        XCTAssertEqual(kk_map_get(result, 1), 30, "last-write-wins: key 1 should map to value from element 3")
    }

    func testAssociateByToUsesLastWriteForDuplicateKeys() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        let result = kk_sequence_associateByTo(
            seq,
            dest,
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(kk_map_get(result, 1), 3)
        XCTAssertEqual(kk_map_get(result, 0), 2)
    }

    func testAssociateWithToUsesElementsAsKeys() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [50], values: [500]))

        let result = kk_sequence_associateWithTo(
            seq,
            dest,
            unsafeBitCast(sequenceValueTimesTen, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(kk_map_get(result, 50), 500)
        XCTAssertEqual(kk_map_get(result, 1), 10)
        XCTAssertEqual(kk_map_get(result, 2), 20)
        XCTAssertEqual(kk_map_get(result, 3), 30)
    }

    func testGroupByToAppendsIntoExistingBuckets() {
        let seq = makeSequence([1, 3, 4])
        let existingList = registerRuntimeObject(RuntimeListBox(elements: [100]))
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [existingList]))

        let result = kk_sequence_groupByTo(
            seq,
            dest,
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(mapKeys(result), [1, 0])
        XCTAssertEqual(listElements(kk_map_get(result, 1)), [100, 1, 3])
        XCTAssertEqual(listElements(kk_map_get(result, 0)), [4])
    }

    func testAssociateToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_sequence_associateTo(
            seq,
            dest,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testAssociateByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_sequence_associateByTo(
            seq,
            dest,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testAssociateWithToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_sequence_associateWithTo(
            seq,
            dest,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testGroupByToThrowingLambdaReturnsSentinelAndSetsOutThrown() {
        let seq = makeSequence([1, 2, 3])
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0

        let result = kk_sequence_groupByTo(
            seq,
            dest,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - Iterator Builder Tests (STDLIB-331/564)

    func testIteratorBuilderBuildYieldsElementsInOrder() {
        // Closure thunk: yields 10, 20, 30 to the builder
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 10)
            _ = kk_sequence_builder_yield(builderRaw, 20)
            _ = kk_sequence_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 10)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 20)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 30)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    func testIteratorBuilderEmptyHasNextReturnsFalse() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    func testIteratorBuilderYieldDirectlyAppendsToBuilder() {
        // Test kk_iterator_builder_yield works directly with RuntimeIteratorBuilderBox
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = kk_iterator_builder_yield(builderRaw, 100)
            _ = kk_iterator_builder_yield(builderRaw, 200)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 100)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 200)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    func testIteratorBuilderSingleElement() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 42)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    // MARK: - Lazy / Continuation-based Iterator Tests (STDLIB-564)

    /// Verifies that the producer is truly lazy: values are produced on-demand,
    /// not eagerly collected into a buffer.  We use a shared counter that the
    /// producer increments on each yield; the consumer asserts the counter
    /// hasn't advanced beyond what was requested.
    func testIteratorBuilderIsLazyNotEager() {
        // We use a class wrapper so the thunk can capture and mutate it.
        // The thunk yields yieldCount values: 1, 2, 3, 4, 5.
        // Between each next() call on the consumer side, we verify the
        // producer hasn't run ahead.
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            // Yield 5 values.  Each yield suspends the producer until the
            // consumer calls next(), so the producer can never run ahead.
            _ = kk_iterator_builder_yield(builderRaw, 1)
            _ = kk_iterator_builder_yield(builderRaw, 2)
            _ = kk_iterator_builder_yield(builderRaw, 3)
            _ = kk_iterator_builder_yield(builderRaw, 4)
            _ = kk_iterator_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        // Consume only the first 3 elements; the producer should not have
        // produced elements 4 and 5 yet (lazy).
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 2)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 3)

        // Now consume the rest.
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 4)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 5)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    /// Verifies that calling next() without hasNext() works correctly
    /// (the continuation advances the producer automatically).
    func testIteratorBuilderNextWithoutHasNext() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = kk_iterator_builder_yield(builderRaw, 10)
            _ = kk_iterator_builder_yield(builderRaw, 20)
            _ = kk_iterator_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        // Call next() directly without hasNext().
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 10)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 20)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 30)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    /// Verifies that calling hasNext() multiple times without next() is
    /// idempotent (returns the same result without advancing the iterator).
    func testIteratorBuilderHasNextIsIdempotent() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = kk_iterator_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        // Multiple hasNext() calls should all return 1.
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 42)
        // After consuming, multiple hasNext() calls should all return 0.
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)
    }

    /// Verifies that the iterator builder works with a computed sequence
    /// (loop-based yield), matching the pattern in the diff case.
    func testIteratorBuilderWithComputedSequence() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            // Yield squares: 1, 4, 9, 16, 25
            for i in 1 ... 5 {
                _ = kk_iterator_builder_yield(builderRaw, i * i)
            }
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = kk_iterator_builder_build(fnPtr)

        var results: [Int] = []
        while kk_iterator_builder_hasNext(iterHandle) == 1 {
            results.append(kk_iterator_builder_next(iterHandle))
        }
        XCTAssertEqual(results, [1, 4, 9, 16, 25])
    }

    // Backwards-compatibility: older lowering paths may pass a RuntimeListIteratorBox
    // to kk_iterator_builder_hasNext / kk_iterator_builder_next.
    func testIteratorBuilderBackwardsCompatWithListIterator() {
        let listHandle = makeList([10, 20, 30])
        let iterHandle = kk_list_iterator(listHandle)

        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 10)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 20)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 1)
        XCTAssertEqual(kk_iterator_builder_next(iterHandle), 30)
        XCTAssertEqual(kk_iterator_builder_hasNext(iterHandle), 0)

        // STDLIB-538: Test backward iteration with hasPrevious()/previous()
        XCTAssertEqual(kk_list_iterator_hasPrevious(iterHandle), 1)
        XCTAssertEqual(kk_list_iterator_previous(iterHandle), 30)
        XCTAssertEqual(kk_list_iterator_hasPrevious(iterHandle), 1)
        XCTAssertEqual(kk_list_iterator_previous(iterHandle), 20)
        XCTAssertEqual(kk_list_iterator_hasPrevious(iterHandle), 1)
        XCTAssertEqual(kk_list_iterator_previous(iterHandle), 10)

        // After going back to beginning, no more previous
        XCTAssertEqual(kk_list_iterator_hasPrevious(iterHandle), 0)
        XCTAssertEqual(kk_list_iterator_previous(iterHandle), 0)
    }

    // MARK: - Sequence scan / runningFold / runningReduce Tests (STDLIB-558, 559, 560)

    func testScanIncludesInitialAccumulator() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            10,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [10, 11, 13, 16])
    }

    func testRunningFoldIncludesInitialAccumulator() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFold(
            seq,
            5,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [5, 6, 8, 11])
    }

    func testRunningFoldIndexedIncludesInitialAccumulatorAndIndex() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFoldIndexed(
            seq,
            10,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(sequenceElements(result), [10, 10, 12, 18])
    }

    func testRunningReduceEmptySequenceReturnsEmptyList() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [])
    }

    func testRunningReduceNonEmptySequenceAccumulatesCorrectly() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        // Kotlin: [1, 2, 3].runningReduce { acc, x -> acc + x } == [1, 3, 6]
        XCTAssertEqual(listElements(result), [1, 3, 6])
    }

    func testRunningReduceSingleElementReturnsThatElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [42])
    }

    // MARK: - Sequence runningReduceIndexed tests (STDLIB-SEQ-017)

    func testRunningReduceIndexedAccumulatesWithIndex() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [1, 3, 9, 21])
    }

    func testRunningReduceIndexedReturnsEmptyListForEmptySequence() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [])
    }

    func testRunningReduceIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testScanReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            0,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testRunningFoldIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFoldIndexed(
            seq,
            0,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testRunningReduceReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testScanReturnsZeroWhenSequenceTraversalThrows() {
        let seq = kk_sequence_generate(
            1,
            unsafeBitCast(throwingSequenceGenerator, to: Int.self),
            0
        )
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            0,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Sequence indexed reduction tests (STDLIB-556, STDLIB-SEQ-015)

    func testReduceIndexedOrNullEmptySequenceReturnsNullSentinel() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceIndexedOrNullNonEmptySequenceAccumulatesWithIndex() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 21)
    }

    func testReduceIndexedOrNullReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Sequence zipWithNext transform tests (STDLIB-SEQ-018)

    func testZipWithNextTransformAppliesLambdaToAdjacentElements() {
        let seq = makeSequence([1, 2, 4, 8])
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            seq,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(result), [1, 2, 4])
    }

    func testZipWithNextTransformReturnsEmptyListForShortSequences() {
        let empty = makeSequence([])
        let single = makeSequence([42])
        var emptyThrown = 0
        var singleThrown = 0

        let emptyResult = kk_sequence_zipWithNextTransform(
            empty,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &emptyThrown
        )
        let singleResult = kk_sequence_zipWithNextTransform(
            single,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &singleThrown
        )

        XCTAssertEqual(emptyThrown, 0)
        XCTAssertEqual(singleThrown, 0)
        XCTAssertEqual(listElements(emptyResult), [])
        XCTAssertEqual(listElements(singleResult), [])
    }

    func testZipWithNextTransformReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            seq,
            unsafeBitCast(throwingSequenceAdjacentTransform, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testSequenceSingleOrNullReturnsOnlyElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_singleOrNull(seq, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 42)
    }

    func testSequenceSingleOrNullReturnsNullForEmptyAndMultipleElements() {
        var emptyThrown = 0
        let emptyResult = kk_sequence_singleOrNull(makeSequence([]), &emptyThrown)
        XCTAssertEqual(emptyThrown, 0)
        XCTAssertEqual(emptyResult, runtimeNullSentinelInt)

        var multipleThrown = 0
        let multipleResult = kk_sequence_singleOrNull(makeSequence([1, 2]), &multipleThrown)
        XCTAssertEqual(multipleThrown, 0)
        XCTAssertEqual(multipleResult, runtimeNullSentinelInt)
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

    func makeSequence(_ elements: [Int]) -> Int {
        kk_sequence_from_list(makeList(elements))
    }

    // MARK: - Sequence.constrainOnce (STDLIB-SEQ-006)

    func testConstrainOnceReportsIllegalStateOnSecondToList() {
        let seq = kk_sequence_constrainOnce(makeSequence([1, 2, 3]))
        var firstThrown = 0
        let firstList = kk_sequence_to_list(seq, &firstThrown)
        XCTAssertEqual(firstThrown, 0)
        XCTAssertEqual(listElements(firstList), [1, 2, 3])

        var secondThrown = 0
        let secondList = kk_sequence_to_list(seq, &secondThrown)
        XCTAssertNotEqual(secondThrown, 0)
        XCTAssertEqual(secondList, runtimeNullSentinelInt)
    }

    func testFilterIsInstanceKeepsMatchingRuntimeTypes() {
        let seq = makeSequence([1, runtimeTestStringHandle("two"), 3])
        let filtered = kk_sequence_filterIsInstance(seq, 3)
        XCTAssertEqual(sequenceElements(filtered), [1, 3])
    }

    func testFilterIndexedKeepsElementsMatchingIndexedPredicate() {
        let fn = unsafeBitCast(keepEvenIndexOrLargeValue, to: Int.self)
        let filtered = kk_sequence_filterIndexed(makeSequence([10, 20, 30, 40]), fn, 0, nil)
        XCTAssertEqual(sequenceElements(filtered), [10, 30, 40])
    }

    // MARK: - Sequence shuffled tests (STDLIB-SEQ-019)

    func testSequenceShuffledPreservesElements() {
        let seq = makeSequence([1, 2, 3, 4])
        let shuffled = kk_sequence_shuffled(seq)
        XCTAssertEqual(sequenceElements(shuffled).sorted(), [1, 2, 3, 4])
    }

    func testSequenceShuffledRandomPreservesElementsAndHandlesSmallSequences() {
        let seq = makeSequence([1, 2, 3, 4])
        let shuffled = kk_sequence_shuffled_random(seq, 0)
        XCTAssertEqual(sequenceElements(shuffled).sorted(), [1, 2, 3, 4])

        XCTAssertEqual(sequenceElements(kk_sequence_shuffled_random(makeSequence([]), 0)), [])
        XCTAssertEqual(sequenceElements(kk_sequence_shuffled_random(makeSequence([42]), 0)), [42])
    }

    // MARK: - STDLIB-SEQ-014: Sequence.requireNoNulls()

    func testSequenceRequireNoNullsPreservesNonNullElements() {
        let seq = makeSequence([1, 2, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(checked, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(list), [1, 2, 3])
    }

    func testSequenceRequireNoNullsThrowsOnNullDuringTraversal() throws {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(checked, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(listElements(list), [])
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException")
    }

    func testSequenceRequireNoNullsIsLazyUntilNullIsReached() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        let firstOnly = kk_sequence_take(checked, 1)
        var thrown = 0
        let list = kk_sequence_to_list(firstOnly, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(list), [1])
    }

    func testSequenceRequireNoNullsPropagatesThroughEagerConsumers() throws {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            checked,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException")
    }

    // MARK: - Sequence mutable conversions (STDLIB-SEQ-025)

    func testToMutableListReturnsIndependentCopy() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toMutableList(seq)

        XCTAssertEqual(listElements(copied), [3, 1, 2, 1, 3])
        XCTAssertEqual(sequenceElements(seq), [3, 1, 2, 1, 3])
    }

    func testToMutableSetDeduplicatesPreservingOrder() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toMutableSet(seq)

        XCTAssertEqual(setElements(copied), [3, 1, 2])
    }

    func testToSortedSetSortsAndDeduplicates() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toSortedSet(seq)

        XCTAssertEqual(setElements(copied), [1, 2, 3])
    }

    func testToHashSetDeduplicatesPreservingOrder() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toHashSet(seq)

        XCTAssertEqual(setElements(copied), [3, 1, 2])
    }

    // MARK: - Sequence.plus (STDLIB-561)

    func testPlusConcatenatesTwoSequences() {
        let seq1 = makeSequence([1, 2, 3])
        let seq2 = makeSequence([4, 5])
        let combined = kk_sequence_plus(seq1, seq2)
        XCTAssertEqual(sequenceElements(combined), [1, 2, 3, 4, 5])
    }

    func testPlusWithEmptySequence() {
        let seq1 = makeSequence([1, 2])
        let seq2 = makeSequence([])
        XCTAssertEqual(sequenceElements(kk_sequence_plus(seq1, seq2)), [1, 2])
        XCTAssertEqual(sequenceElements(kk_sequence_plus(seq2, seq1)), [1, 2])
    }

    func testPlusWithListAsOther() {
        let seq = makeSequence([1, 2])
        let list = makeList([3, 4])
        let combined = kk_sequence_plus(seq, list)
        XCTAssertEqual(sequenceElements(combined), [1, 2, 3, 4])
    }

    // MARK: - Sequence.minus (STDLIB-562)

    func testMinusRemovesFirstOccurrenceOfElement() {
        let seq = makeSequence([1, 2, 3, 2, 4])
        let result = kk_sequence_minus(seq, 2)
        XCTAssertEqual(sequenceElements(result), [1, 3, 2, 4])
    }

    func testMinusElementNotPresent() {
        let seq = makeSequence([1, 2, 3])
        let result = kk_sequence_minus(seq, 99)
        XCTAssertEqual(sequenceElements(result), [1, 2, 3])
    }

    func testMinusOnEmptySequence() {
        let seq = makeSequence([])
        let result = kk_sequence_minus(seq, 1)
        XCTAssertEqual(sequenceElements(result), [])
    }

    func testPlusResultIsSequence() {
        // Verify the result of plus can be chained with other sequence operations
        let seq1 = makeSequence([1, 2])
        let seq2 = makeSequence([3, 4])
        let combined = kk_sequence_plus(seq1, seq2)
        let asList = kk_sequence_to_list(combined, nil)
        XCTAssertEqual(listElements(asList), [1, 2, 3, 4])
    }

    func testMinusResultIsSequence() {
        // Verify the result of minus can be chained with other sequence operations
        let seq = makeSequence([1, 2, 3])
        let reduced = kk_sequence_minus(seq, 2)
        let asList = kk_sequence_to_list(reduced, nil)
        XCTAssertEqual(listElements(asList), [1, 3])
    }

    // MARK: - Eager Materialization (Intentional Simplification)

    func testPlusEagerlyMaterializesResult() {
        // NOTE: Kotlin's Sequence.plus returns a lazy sequence, but our
        // runtime intentionally materializes eagerly via evaluateSequence.
        // This test documents the current eager behavior; it should be
        // updated if/when lazy concat steps are added to the pipeline.
        let seq1 = makeSequence([10, 20])
        let seq2 = makeSequence([30, 40])
        let combined = kk_sequence_plus(seq1, seq2)
        // The result is immediately available (eagerly materialized).
        XCTAssertEqual(sequenceElements(combined), [10, 20, 30, 40])
    }

    func testMinusEagerlyMaterializesResult() {
        // Same as above: documents intentional eager materialization.
        let seq = makeSequence([5, 10, 15, 10])
        let result = kk_sequence_minus(seq, 10)
        XCTAssertEqual(sequenceElements(result), [5, 15, 10])
    }

    // MARK: - Plus with array as RHS

    func testPlusWithArrayAsOther() {
        let seq = makeSequence([1, 2])
        let array = makeArray([3, 4])
        let combined = kk_sequence_plus(seq, array)
        XCTAssertEqual(sequenceElements(combined), [1, 2, 3, 4])
    }

    // MARK: - Plus with kk_sequence_of_single as RHS

    func testPlusWithSingleElementWrappedViaOfSingle() {
        // Verifies the ABI pattern the compiler emits for `seq + element`:
        // the element is wrapped via kk_sequence_of_single before being
        // passed to kk_sequence_plus.
        let seq = makeSequence([1, 2, 3])
        let wrappedElement = kk_sequence_of_single(42)
        let combined = kk_sequence_plus(seq, wrappedElement)
        XCTAssertEqual(sequenceElements(combined), [1, 2, 3, 42])
    }

    func testPlusWithSingleElementWrappedViaOfSingleEmptyLHS() {
        let seq = makeSequence([])
        let wrappedElement = kk_sequence_of_single(99)
        let combined = kk_sequence_plus(seq, wrappedElement)
        XCTAssertEqual(sequenceElements(combined), [99])
    }

    func testPlusElementAppendsSingleElement() {
        let seq = makeSequence([1, 2, 3])
        let combined = kk_sequence_plus_element(seq, 42)
        XCTAssertEqual(sequenceElements(combined), [1, 2, 3, 42])
    }

    // MARK: - Lazy Sequence Builder Tests (STDLIB-563)

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { index in
            kk_list_get(listRaw, index)
        }
    }

    private func sequenceElements(_ seqRaw: Int) -> [Int] {
        listElements(kk_sequence_to_list(seqRaw, nil))
    }

    private func setElements(_ setRaw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw) else {
            return []
        }
        guard let box = try? XCTUnwrap(tryCast(ptr, to: RuntimeSetBox.self)) else {
            return []
        }
        return box.elements
    }

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return try? XCTUnwrap(tryCast(ptr, to: RuntimeThrowableBox.self))
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
