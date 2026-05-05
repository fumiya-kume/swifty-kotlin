@testable import Runtime
import XCTest

private let isEvenForIndexOfLast: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

final class RuntimeCollectionIndexOfLastTests: XCTestCase {
    func testListIndexOfLastFindsPredicateMatchAndMissingElement() {
        let mixed = registerRuntimeObject(RuntimeListBox(elements: [1, 4, 5, 6]))
        let odds = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 5]))
        let predicate = unsafeBitCast(isEvenForIndexOfLast, to: Int.self)

        XCTAssertEqual(kk_list_indexOfLast(mixed, predicate, 0, nil), 3)
        XCTAssertEqual(kk_list_indexOfLast(odds, predicate, 0, nil), -1)
    }
}
