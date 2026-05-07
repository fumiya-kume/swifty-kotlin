@testable import Runtime
import XCTest

private let isEvenForIndexOfFirst: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

final class RuntimeCollectionIndexOfFirstTests: XCTestCase {
    func testListIndexOfFirstFindsPredicateMatchAndMissingElement() {
        let mixed = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 4, 6]))
        let odds = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 5]))
        let predicate = unsafeBitCast(isEvenForIndexOfFirst, to: Int.self)

        XCTAssertEqual(kk_list_indexOfFirst(mixed, predicate, 0, nil), 2)
        XCTAssertEqual(kk_list_indexOfFirst(odds, predicate, 0, nil), -1)
    }
}
