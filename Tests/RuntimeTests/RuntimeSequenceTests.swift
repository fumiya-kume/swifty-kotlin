import Foundation
@testable import Runtime
import XCTest

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

private let throwingAccumulator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence accumulator failed")
    return 0
}

private let throwingSequenceGenerator: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence generator failed")
    return 0
}

private func runtimeTestStringHandle(_ value: String) -> Int {
    let bytes = Array(value.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
        let raw = kk_string_from_utf8(baseAddress, Int32(bytes.count))
        return Int(bitPattern: raw)
    }
}

final class RuntimeSequenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testSortedByUsesRuntimeValueComparisonForSelectorKeys() {
        let source = makeSequence([1, 2, 3])
        let sorted = kk_sequence_sortedBy(
            source,
            unsafeBitCast(stringKeySelector, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(listElements(kk_sequence_to_list(sorted)), [2, 1, 3])
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
        XCTAssertEqual(listElements(kk_sequence_to_list(sorted)), [])
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

    private func makeSequence(_ elements: [Int]) -> Int {
        kk_sequence_from_list(makeList(elements))
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
        let asList = kk_sequence_to_list(combined)
        XCTAssertEqual(listElements(asList), [1, 2, 3, 4])
    }

    func testMinusResultIsSequence() {
        // Verify the result of minus can be chained with other sequence operations
        let seq = makeSequence([1, 2, 3])
        let reduced = kk_sequence_minus(seq, 2)
        let asList = kk_sequence_to_list(reduced)
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

    // MARK: - Helpers

    private func sequenceElements(_ seqRaw: Int) -> [Int] {
        listElements(kk_sequence_to_list(seqRaw))
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
}
