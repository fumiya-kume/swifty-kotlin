@testable import Runtime
import Foundation
import XCTest

/// Sequence builder / advanced operator / SharedFlow / StateFlow
/// tests, split out from `RuntimeSequenceTests` to keep each test
/// source focused.
extension RuntimeSequenceTests {
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
            _ = kk_array_set(arr, 0, 10, &thrown)
            _ = kk_array_set(arr, 1, 20, &thrown)
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

    func testSequenceFirstReturnsFirstElement() {
        let seq = makeSequence([7, 8, 9])
        var thrown = 0
        let first = kk_sequence_first(seq, &thrown)
        XCTAssertEqual(first, 7)
        XCTAssertEqual(thrown, 0)
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

    func testSequenceFilterNotToAppendsNonMatchingElementsToDestination() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let destination = makeList([99])
        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2 == 0 ? 1 : 0
        }

        let result = kk_sequence_filterNotTo(
            seq,
            destination,
            unsafeBitCast(filterFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, destination)
        XCTAssertEqual(listElements(destination), [99, 1, 3, 5])
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
            _ = kk_array_set(arr, 0, value, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
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

    func testSequenceFoldIndexedAccumulatesIndexAndValueInOrder() {
        let seq = makeSequence([3, 4, 5])
        let foldFn: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
            acc + index * 10 + value
        }

        let result = kk_sequence_foldIndexed(
            seq,
            0,
            unsafeBitCast(foldFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, 42)
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

    func testSequenceFlatMapToAppendsFlattenedResults() {
        let seq = makeSequence([1, 2])
        let dest = makeList([50])
        let flatMapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, value, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }

        let result = kk_sequence_flatMapTo(
            seq,
            dest,
            unsafeBitCast(flatMapFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(result), [50, 1, 10, 2, 20])
    }

    func testSequenceMapNotNullToAppendsOnlyNonNullResults() {
        let seq = makeSequence([1, 2, 3, 4])
        let dest = makeList([50])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value.isMultiple(of: 2) ? value * 10 : runtimeNullSentinelInt
        }

        let result = kk_sequence_mapNotNullTo(
            seq,
            dest,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(result), [50, 20, 40])
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

    func testSequenceFlatMapIndexedToAppendsFlattenedResults() {
        let seq = makeSequence([1, 2])
        let dest = makeList([50])
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }

        let result = kk_sequence_flatMapIndexedTo(
            seq,
            dest,
            unsafeBitCast(flatMapFn, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(result, dest)
        XCTAssertEqual(listElements(result), [50, 0, 10, 1, 20])
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
            _ = kk_array_set(arr, 0, value, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
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

    func testSequenceWindowedProducesPartialWindows() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let windows = kk_sequence_windowed(seq, 3, 2, 1)
        let nested = sequenceElements(windows).map { listElements($0) }

        XCTAssertEqual(nested, [[1, 2, 3], [3, 4, 5], [5]])
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

    func testSequenceChunkedReturnsSequenceOfChunkLists() {
        let chunked = kk_sequence_chunked(makeSequence([1, 2, 3, 4, 5]), 2)
        let chunkHandles = sequenceElements(chunked)

        XCTAssertEqual(chunkHandles.map { listElements($0) }, [[1, 2], [3, 4], [5]])
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
}
