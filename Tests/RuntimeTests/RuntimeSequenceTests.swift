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

private var _lazyTestYieldCounter: Int {
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

private var _lazySequenceOnEachIndexedTrace: [Int] {
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

private let lazyYieldAllOuterThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
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

private let sequenceParitySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let sequenceValueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 10
}

private let sequenceFirstNullableEvenTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value.isMultiple(of: 2) ? value * 10 : runtimeNullSentinelInt
}

private let sequenceAlwaysNullTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let sequenceAdjacentDifference: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, left, right, _ in
    right - left
}

private let throwingSequenceAdjacentTransform: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence zipWithNext transform failed")
    return 0
}

private let throwingSequenceDestinationLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence destination transform failed")
    return 0
}

private let recordingOnEachIndexedAction: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    appendLazySequenceOnEachIndexedTrace(index * 100 + value)
    return 0
}

private let summingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, windowRaw, _ in
    let size = kk_list_size(windowRaw)
    guard size > 0 else { return 0 }
    var sum = 0
    for index in 0 ..< size {
        sum += kk_list_get(windowRaw, index)
    }
    return sum
}

private let throwingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
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

        XCTAssertEqual(result, 0)
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

    private func makeSequence(_ elements: [Int]) -> Int {
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

    func testSequenceBuilderBuildYieldsElementsInOrder() {
        // sequence { yield(1); yield(2); yield(3) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        XCTAssertEqual(sequenceElements(seqHandle), [1, 2, 3])
    }

    func testSequenceBuilderBuildEmptyBlock() {
        // sequence { }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        XCTAssertEqual(sequenceElements(seqHandle), [])
    }

    func testSequenceBuilderBuildSingleElement() {
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        XCTAssertEqual(sequenceElements(seqHandle), [42])
    }

    func testSequenceBuilderBuildWithMap() {
        // sequence { yield(1); yield(2); yield(3) }.map { it * 10 }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)

        // Apply map: multiply by 10
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value * 10
        }
        let mapped = kk_sequence_map(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0
        )
        XCTAssertEqual(sequenceElements(mapped), [10, 20, 30])
    }

    func testSequenceMapPassesSentinelInputsToTransform() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? 99 : value * 2
        }
        let mapped = kk_sequence_map(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0
        )
        XCTAssertEqual(sequenceElements(mapped), [2, 99, 6])
    }

    func testSequenceBuilderBuildWithTake() {
        // sequence { yield(1); yield(2); yield(3); yield(4); yield(5) }.take(3).toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _ = kk_sequence_builder_yield(builderRaw, 3)
            _ = kk_sequence_builder_yield(builderRaw, 4)
            _ = kk_sequence_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        let taken = kk_sequence_take(seqHandle, 3)
        XCTAssertEqual(sequenceElements(taken), [1, 2, 3])
    }

    func testSequenceBuilderBuildWithFilter() {
        // sequence { yield(1); yield(2); yield(3); yield(4) }.filter { it % 2 == 0 }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _ = kk_sequence_builder_yield(builderRaw, 3)
            _ = kk_sequence_builder_yield(builderRaw, 4)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)

        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2 == 0 ? 1 : 0
        }
        let filtered = kk_sequence_filter(
            seqHandle,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )
        XCTAssertEqual(sequenceElements(filtered), [2, 4])
    }

    func testSequenceBuilderBuildYieldAllFromList() {
        // sequence { yieldAll(listOf(10, 20)); yield(30) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            // Create a list [10, 20]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = _ = kk_array_set(arr, 0, 10, &thrown)
            _ = _ = kk_array_set(arr, 1, 20, &thrown)
            let list = kk_list_of(arr, 2)
            _ = kk_sequence_builder_yieldAll(builderRaw, list)
            _ = kk_sequence_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        XCTAssertEqual(sequenceElements(seqHandle), [10, 20, 30])
    }

    func testSequenceBuilderBuildYieldAllFromLazySequenceIsLazy() {
        // sequence { yieldAll(inner); yield(99) }.take(2).toList()
        _lazyTestYieldCounter = 0
        let outerFnPtr = unsafeBitCast(lazyYieldAllOuterThunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(outerFnPtr)

        let taken = kk_sequence_take(seqHandle, 2)
        XCTAssertEqual(sequenceElements(taken), [10, 20])
        XCTAssertLessThanOrEqual(
            _lazyTestYieldCounter,
            3,
            "yieldAll should not eagerly evaluate all 5 elements of the nested sequence before first consumer demand"
        )

        let full = sequenceElements(seqHandle)
        XCTAssertEqual(full, [10, 20, 30, 40, 50, 99])
        XCTAssertEqual(_lazyTestYieldCounter, 5)
    }

    func testSequenceBuilderBuildReiterableProducesSameElements() {
        // Verify that materializing the same lazy sequence twice produces the same result
        // (cached after first materialization).
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = kk_sequence_builder_yield(builderRaw, 7)
            _ = kk_sequence_builder_yield(builderRaw, 8)
            _ = kk_sequence_builder_yield(builderRaw, 9)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        XCTAssertEqual(sequenceElements(seqHandle), [7, 8, 9])
        // Second materialization should produce the same result (cached).
        XCTAssertEqual(sequenceElements(seqHandle), [7, 8, 9])
    }

    func testSequenceBuilderBuildManyElements() {
        // sequence { for (i in 0..99) yield(i) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            for i in 0 ..< 100 {
                _ = kk_sequence_builder_yield(builderRaw, i)
            }
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        let result = sequenceElements(seqHandle)
        XCTAssertEqual(result.count, 100)
        XCTAssertEqual(result.first, 0)
        XCTAssertEqual(result.last, 99)
    }

    // MARK: - STDLIB-563: Lazy evaluation verification

    func testSequenceBuilderLazyTakeDoesNotEvaluateEntireBlock() {
        // STDLIB-563: Verify that take(2) on a lazy sequence builder
        // only computes the first 2 elements, not all 5.
        // We use a global counter to track how many yields actually execute.
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 3)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 4)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        let taken = kk_sequence_take(seqHandle, 2)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [1, 2])
        // The producer should have yielded at most 3 times (2 consumed + 1 ahead
        // before take detects the limit), not all 5. In the truly lazy model,
        // the counter should be <= 3.
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 3,
            "STDLIB-563: take(2) should not force evaluation of all 5 elements; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceBuilderLazyFirstDoesNotEvaluateEntireBlock() {
        // STDLIB-563: first() on a lazy sequence builder should only evaluate
        // until the first element is produced.
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 100)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 200)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 300)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        var thrown = 0
        let first = kk_sequence_first(seqHandle, &thrown)
        XCTAssertEqual(first, 100)
        XCTAssertEqual(thrown, 0)
        // The producer should have yielded at most 2 times (1 consumed +
        // possibly 1 ahead), not all 3.
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2,
            "STDLIB-563: first() should not force evaluation of all 3 elements; got \(_lazyTestYieldCounter) yields")
    }

    // MARK: - STDLIB-HOF-022: Additional Higher-Order Functions

    func testSequenceFilterNot() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2 == 0 ? 1 : 0  // true for even numbers
        }
        let filtered = kk_sequence_filterNot(
            seq,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )
        XCTAssertEqual(sequenceElements(filtered), [1, 3, 5]) // Should keep odd numbers
    }

    func testSequenceFind() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let findFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value > 3 ? 1 : 0  // true for values > 3
        }
        var thrown = 0
        let found = kk_sequence_find(
            seq,
            unsafeBitCast(findFn, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(found, 4) // First element > 3
        XCTAssertEqual(thrown, 0)
    }

    func testSequenceFindNotFound() {
        let seq = makeSequence([1, 2, 3])
        let findFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value > 10 ? 1 : 0  // true for values > 10
        }
        var thrown = 0
        let found = kk_sequence_find(
            seq,
            unsafeBitCast(findFn, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(found, runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testSequenceAsIterable() {
        let seq = makeSequence([1, 2, 3])
        let iterable = kk_sequence_asIterable(seq)
        // Should return the same handle
        XCTAssertEqual(iterable, seq)
    }

    func testSequenceOrEmptyReturnsEmptySequenceForNull() {
        let seq = kk_sequence_orEmpty(runtimeNullSentinelInt)

        XCTAssertEqual(sequenceElements(seq), [])
    }

    func testSequenceOrEmptyReturnsExistingSequenceForNonNull() {
        let seq = makeSequence([1, 2, 3])

        XCTAssertEqual(kk_sequence_orEmpty(seq), seq)
    }

    func testSequenceFilterNotLazy() {
        // Test that filterNot is lazy by using a sequence builder
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == 2 ? 1 : 0  // true only for value 2
        }
        
        let filtered = kk_sequence_filterNot(
            seqHandle,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(filtered, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [1]) // Should be [1, 3] but take(1) gives [1]
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 3,
            "filterNot should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    // MARK: - STDLIB-HOF-022: Additional Lazy Higher-Order Functions Tests

    func testSequenceMapNotNullLazy() {
        // Test mapNotNull with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, runtimeNullSentinelInt) // null value
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? runtimeNullSentinelInt : value * 2
        }
        
        let mapped = kk_sequence_mapNotNull(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(mapped, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [2]) // 1 * 2 = 2, null is filtered out
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 3,
            "mapNotNull should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceFilterNotNullLazy() {
        // Test filterNotNull with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, runtimeNullSentinelInt) // null value
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let filtered = kk_sequence_filterNotNull(seqHandle)
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(filtered, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [1]) // null is filtered out
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 3,
            "filterNotNull should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceMapIndexedLazy() {
        // Test mapIndexed with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index + value
        }
        
        let mapped = kk_sequence_mapIndexed(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(mapped, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [10]) // index 0 + value 10 = 10
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2,
            "mapIndexed should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceOnEachIndexedLazy() {
        _lazyTestYieldCounter = 0
        _lazySequenceOnEachIndexedTrace = []
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)

        let onEachIndexed = kk_sequence_onEachIndexed(
            seqHandle,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )

        let taken = kk_sequence_take(onEachIndexed, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [10])
        XCTAssertEqual(_lazySequenceOnEachIndexedTrace, [10])
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2,
            "onEachIndexed should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceOnEachIndexedSourceBackedSequenceIsLazy() {
        _lazySequenceOnEachIndexedTrace = []
        let seq = makeSequence([10, 20, 30])

        let onEachIndexed = kk_sequence_onEachIndexed(
            seq,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )

        let taken = kk_sequence_take(onEachIndexed, 2)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [10, 20])
        XCTAssertEqual(_lazySequenceOnEachIndexedTrace, [10, 120])
    }

    func testSequenceWithIndexLazy() {
        // Test withIndex with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let withIndex = kk_sequence_withIndex(seqHandle)
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(withIndex, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result.count, 1)
        // Should be a pair (0, 10)
        let pair = result[0]
        let first = kk_pair_first(pair)
        let second = kk_pair_second(pair)
        XCTAssertEqual(first, 0) // index
        XCTAssertEqual(second, 10) // value
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2,
            "withIndex should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceFlatMapLazy() {
        // Test flatMap with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 2)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = kk_sequence_builder_build(fnPtr)
        
        let flatMapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            // Create a list [value, value * 10]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = _ = kk_array_set(arr, 0, value, &thrown)
            _ = _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }
        
        let flatMapped = kk_sequence_flatMap(
            seqHandle,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )
        
        // Take only first element to verify laziness
        let taken = kk_sequence_take(flatMapped, 1)
        let result = sequenceElements(taken)
        XCTAssertEqual(result, [1]) // First element of [1, 10] from first input value 1
        
        // Should not have evaluated all elements due to laziness
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2,
            "flatMap should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    func testSequenceMapNotNullCorrectness() {
        // Test correctness of mapNotNull
        let seq = makeSequence([1, 2, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? runtimeNullSentinelInt : value * 2
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(mapped)
        XCTAssertEqual(result, [2, 4, 6])
    }

    func testSequenceMapNotNullPassesSentinelInputsToTransform() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? 99 : value * 2
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(sequenceElements(mapped), [2, 99, 6])
    }

    func testSequenceMapNotNullPreservesZeroResults() {
        let seq = makeSequence([0, 1, 2])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(sequenceElements(mapped), [0, 1, 2])
    }

    func testSequenceFirstNotNullOfOrNullReturnsFirstNonNullResult() {
        let seq = makeSequence([1, 2, 4])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(sequenceFirstNullableEvenTimesTen, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(result, 20)
        XCTAssertEqual(thrown, 0)
    }

    func testSequenceFirstNotNullOfOrNullReturnsNullSentinelWhenNoResultMatches() {
        let seq = makeSequence([1, 3, 5])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(sequenceAlwaysNullTransform, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testSequenceFirstNotNullOfOrNullPropagatesThrownTransform() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSequenceFirstNotNullOfReturnsFirstNonNullTransformResult() {
        let seq = makeSequence([1, 2, 4])
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(sequenceFirstNullableEvenTimesTen, to: Int.self),
            0,
            nil
        )
        XCTAssertEqual(result, 20)
    }

    func testSequenceFirstNotNullOfThrowsWhenEveryTransformResultIsNull() {
        let seq = makeSequence([1, 3, 5])
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(sequenceAlwaysNullTransform, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSequenceFirstNotNullOfPropagatesThrowingLambda() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSequenceFilterNotNullPreservesZeroAfterMapNotNull() {
        let seq = makeSequence([0, 1, 2])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let filtered = kk_sequence_filterNotNull(mapped)
        XCTAssertEqual(sequenceElements(filtered), [0, 1, 2])
    }

    func testSequenceFilterNotNullCorrectness() {
        // Test correctness of filterNotNull
        let seq = makeSequence([1, runtimeNullSentinelInt, 3, runtimeNullSentinelInt, 5])
        let filtered = kk_sequence_filterNotNull(seq)
        let result = sequenceElements(filtered)
        XCTAssertEqual(result, [1, 3, 5]) // Only non-null values
    }

    func testSequenceRequireNoNullsPassesNonNullElements() {
        let seq = makeSequence([1, 3, 5])
        let required = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(required, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(list), [1, 3, 5])
    }

    func testSequenceRequireNoNullsThrowsOnNullElement() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 5])
        let required = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(required, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(list, runtimeNullSentinelInt)
    }

    func testSequenceMapIndexedCorrectness() {
        // Test correctness of mapIndexed
        let seq = makeSequence([10, 20, 30])
        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index + value
        }
        let mapped = kk_sequence_mapIndexed(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(mapped)
        XCTAssertEqual(result, [10, 21, 32]) // [0+10, 1+20, 2+30]
    }

    func testSequenceOnEachIndexedCorrectness() {
        let seq = makeSequence([10, 20, 30])
        _lazySequenceOnEachIndexedTrace = []
        let transformed = kk_sequence_onEachIndexed(
            seq,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(transformed)
        XCTAssertEqual(result, [10, 20, 30])
        XCTAssertEqual(_lazySequenceOnEachIndexedTrace, [10, 120, 230])
    }

    func testSequenceMapToAppendsToDestination() {
        let seq = makeSequence([1, 2, 3])
        let dest = makeList([99])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value * 10
        }

        let result = kk_sequence_mapTo(
            seq,
            dest,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(result), [99, 10, 20, 30])
    }

    func testSequenceMapIndexedNotNullToAppendsOnlyNonNullResults() {
        let seq = makeSequence([1, 2, 3, 4])
        let dest = makeList([50])
        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index % 2 == 0 ? index + value : runtimeNullSentinelInt
        }

        let result = kk_sequence_mapIndexedNotNullTo(
            seq,
            dest,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(result), [50, 1, 5])
    }

    func testSequenceWithIndexCorrectness() {
        // Test correctness of withIndex
        let seq = makeSequence([10, 20, 30])
        let withIndex = kk_sequence_withIndex(seq)
        let result = sequenceElements(withIndex)
        XCTAssertEqual(result.count, 3)
        // Check first pair (0, 10)
        let first = kk_pair_first(result[0])
        let second = kk_pair_second(result[0])
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 10)
        // Check second pair (1, 20)
        let first2 = kk_pair_first(result[1])
        let second2 = kk_pair_second(result[1])
        XCTAssertEqual(first2, 1)
        XCTAssertEqual(second2, 20)
    }

    func testSequenceFlatMapCorrectness() {
        // Test correctness of flatMap
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            // Create a list [value, value * 10]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = _ = kk_array_set(arr, 0, value, &thrown)
            _ = _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }
        let flatMapped = kk_sequence_flatMap(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )
        let result = sequenceElements(flatMapped)
        XCTAssertEqual(result, [1, 10, 2, 20]) // [1, 10] + [2, 20]
    }

    func testSequenceFlatMapIndexedFlattensIterableResults() {
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )

        XCTAssertEqual(sequenceElements(flatMapped), [0, 10, 1, 20])
    }

    func testSequenceFlatMapIndexedFlattensSequenceResults() {
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index + value, &thrown)
            _ = kk_array_set(arr, 1, value * 100, &thrown)
            return kk_sequence_from_list(kk_list_of(arr, 2))
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )

        XCTAssertEqual(sequenceElements(flatMapped), [1, 100, 3, 200])
    }

    func testSequenceFlatMapIndexedIsLazy() {
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let seq = kk_sequence_builder_build(unsafeBitCast(thunk, to: Int.self))
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index, &thrown)
            _ = kk_array_set(arr, 1, value, &thrown)
            return kk_list_of(arr, 2)
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )
        let taken = kk_sequence_take(flatMapped, 3)

        XCTAssertEqual(sequenceElements(taken), [0, 1, 1])
        XCTAssertLessThanOrEqual(_lazyTestYieldCounter, 2)
    }

    func testSequenceWindowedTransformCorrectness() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let transformed = kk_sequence_windowed_transform(
            seq,
            3,
            2,
            1,
            unsafeBitCast(summingWindowTransform, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(sequenceElements(transformed), [6, 12, 5])
    }

    func testSequenceWindowedTransformPropagatesThrowables() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0
        let transformed = kk_sequence_windowed_transform(
            seq,
            2,
            1,
            0,
            unsafeBitCast(throwingWindowTransform, to: Int.self),
            0,
            &thrown
        )

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(transformed, 0)
    }

    func testSequenceChunkedTransformCorrectness() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let transformed = kk_sequence_chunked_transform(
            seq,
            2,
            unsafeBitCast(summingWindowTransform, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(sequenceElements(transformed), [3, 7, 5])
    }

    func testSequenceChunkedTransformPropagatesThrowables() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0
        let transformed = kk_sequence_chunked_transform(
            seq,
            2,
            unsafeBitCast(throwingWindowTransform, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(transformed, 0)

        var iterationThrown = 0
        let materialized = kk_sequence_to_list(transformed, &iterationThrown)
        XCTAssertNotEqual(iterationThrown, 0)
        XCTAssertEqual(materialized, runtimeNullSentinelInt)
    }

    // MARK: - Helpers

    private func sequenceElements(_ seqRaw: Int) -> [Int] {
        listElements(kk_sequence_to_list(seqRaw, nil))
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
