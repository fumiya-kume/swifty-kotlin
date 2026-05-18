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

    private func makeParallelStream(_ elements: [Int]) -> Int {
        kk_parallel_stream_from_collection(kk_sequence_from_list(makeList(elements)), kk_parallel_pool_new(2))
    }

    private func sequenceElements(_ sequenceRaw: Int) -> [Int] {
        let listRaw = kk_sequence_to_list(sequenceRaw, nil)
        return runtimeListBox(from: listRaw)?.elements ?? []
    }

    func testStreamAsSequenceConvertsStreamLikeHandles() {
        XCTAssertEqual(sequenceElements(kk_stream_asSequence(makeParallelStream([1, 2, 3]))), [1, 2, 3])
        XCTAssertEqual(sequenceElements(kk_int_stream_asSequence(makeParallelStream([4, 5]))), [4, 5])
        XCTAssertEqual(sequenceElements(kk_long_stream_asSequence(makeParallelStream([6, 7]))), [6, 7])
        XCTAssertEqual(sequenceElements(kk_double_stream_asSequence(makeParallelStream([8, 9]))), [8, 9])
    }
}
