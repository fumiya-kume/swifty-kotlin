import Foundation
@testable import Runtime
import XCTest

private let mapIndexedNotNullToEvenIndex: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index.isMultiple(of: 2) ? value + index : runtimeNullSentinelInt
}

final class RuntimeCollectionMapIndexedNotNullToTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testMapIndexedNotNullToAppendsOnlyNonNullResults() {
        let source = makeList([10, 20, 30, 40])
        let destination = makeList([])
        let returned = kk_list_mapIndexedNotNullTo(
            source,
            destination,
            unsafeBitCast(mapIndexedNotNullToEvenIndex, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        XCTAssertEqual(returned, destination)
        XCTAssertEqual(listElements(destination), [10, 32])
    }

    private func makeList(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        runtimeListBox(from: listRaw)?.elements ?? []
    }
}
