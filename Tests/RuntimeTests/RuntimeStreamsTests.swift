@testable import Runtime
import XCTest

final class RuntimeStreamsTests: IsolatedRuntimeXCTestCase {
    private func makeArray(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(array, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    private func makeList(_ elements: [Int]) -> Int {
        kk_list_of(makeArray(elements), elements.count)
    }

    private func makeSequence(_ elements: [Int]) -> Int {
        kk_sequence_from_list(makeList(elements))
    }

    private func makeParallelStream(_ elements: [Int]) -> Int {
        kk_parallel_stream_from_collection(makeSequence(elements), kk_parallel_pool_new(2))
    }

    private func sequenceElements(_ sequenceRaw: Int) -> [Int] {
        let listRaw = kk_sequence_to_list(sequenceRaw, nil)
        return runtimeListBox(from: listRaw)?.elements ?? []
    }

    private func streamElements(_ streamRaw: Int) -> [Int] {
        let listRaw = kk_parallel_stream_to_list(streamRaw)
        return runtimeListBox(from: listRaw)?.elements ?? []
    }

    func testStreamAsSequenceConvertsStreamLikeHandles() {
        XCTAssertEqual(sequenceElements(kk_stream_asSequence(makeParallelStream([1, 2, 3]))), [1, 2, 3])
        XCTAssertEqual(sequenceElements(kk_int_stream_asSequence(makeParallelStream([4, 5]))), [4, 5])
        XCTAssertEqual(sequenceElements(kk_long_stream_asSequence(makeParallelStream([6, 7]))), [6, 7])
        XCTAssertEqual(sequenceElements(kk_double_stream_asSequence(makeParallelStream([8, 9]))), [8, 9])
    }

    func testLongStreamToListConvertsStreamLikeHandles() {
        let listRaw = kk_long_stream_toList(makeParallelStream([6, 7, 8]))

        XCTAssertEqual(runtimeListBox(from: listRaw)?.elements, [6, 7, 8])
    }

    func testSequenceAsStreamConvertsSequenceHandles() {
        let streamRaw = kk_sequence_asStream(makeSequence([10, 20, 30]))

        XCTAssertEqual(streamElements(streamRaw), [10, 20, 30])
        XCTAssertEqual(sequenceElements(kk_stream_asSequence(streamRaw)), [10, 20, 30])
    }

    func testDoubleStreamToListConvertsStreamLikeHandles() {
        let listRaw = kk_double_stream_toList(makeParallelStream([8, 9, 10]))

        XCTAssertEqual(runtimeListBox(from: listRaw)?.elements, [8, 9, 10])
    }
}
