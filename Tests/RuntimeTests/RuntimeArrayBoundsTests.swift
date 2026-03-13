@testable import Runtime
import XCTest

final class RuntimeArrayBoundsTests: IsolatedRuntimeXCTestCase {
    private func makeMutableList(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            XCTAssertEqual(kk_array_set(array, index, element, &thrown), element)
            XCTAssertEqual(thrown, 0)
        }
        return kk_list_to_mutable_list(kk_list_of(array, elements.count))
    }

    func testArrayGetAndSetInBounds() {
        let array = kk_array_new(2)
        XCTAssertNotEqual(array, 0)

        var outThrown = -1
        XCTAssertEqual(kk_array_set(array, 1, 42, &outThrown), 42)
        XCTAssertEqual(outThrown, 0)

        outThrown = -1
        XCTAssertEqual(kk_array_get(array, 1, &outThrown), 42)
        XCTAssertEqual(outThrown, 0)
    }

    func testArrayOutOfBoundsSetsThrownChannel() {
        let array = kk_array_new(1)
        XCTAssertNotEqual(array, 0)

        var outThrown = 0
        XCTAssertEqual(kk_array_get(array, 5, &outThrown), 0)
        XCTAssertNotEqual(outThrown, 0)
    }

    func testMutableListAddAtUsesThrownChannelForBoundsErrors() {
        let list = makeMutableList([10, 20])
        var outThrown = -1

        XCTAssertEqual(kk_mutable_list_add_at(list, 1, 15, &outThrown), 0)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(runtimeListBox(from: list)?.elements, [10, 15, 20])

        outThrown = -1
        XCTAssertEqual(kk_mutable_list_add_at(list, 99, 30, &outThrown), 0)
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(runtimeListBox(from: list)?.elements, [10, 15, 20])
    }

    func testMutableListSetUsesThrownChannelForBoundsErrors() {
        let list = makeMutableList([10, runtimeNullSentinelInt, 30])
        var outThrown = -1

        XCTAssertEqual(kk_mutable_list_set(list, 1, 25, &outThrown), runtimeNullSentinelInt)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(runtimeListBox(from: list)?.elements, [10, 25, 30])

        outThrown = -1
        XCTAssertEqual(kk_mutable_list_set(list, 99, 40, &outThrown), 0)
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(runtimeListBox(from: list)?.elements, [10, 25, 30])
    }
}
