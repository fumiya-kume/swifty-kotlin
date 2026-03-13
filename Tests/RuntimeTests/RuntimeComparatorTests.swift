import Foundation
@testable import Runtime
import XCTest

// MARK: - Test lambdas

private let selectIdentity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value
}


private let throwingSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 1
    return 0
}

private let comparatorNatural: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    if a < b { return -1 }
    if a > b { return 1 }
    return 0
}

private let comparatorByModTen: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    let ka = a % 10
    let kb = b % 10
    if ka < kb { return -1 }
    if ka > kb { return 1 }
    return 0
}

private let comparatorReversed: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    if a < b { return 1 }
    if a > b { return -1 }
    return 0
}

private let throwingComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = 1
    return 0
}

// MARK: - Helpers

private func selectorPtr(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func comparatorPtr(_ fn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func makeList(_ elements: [Int]) -> Int {
    let box = RuntimeListBox(elements: elements)
    return registerRuntimeObject(box)
}

private func listElements(_ listRaw: Int) -> [Int] {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw) else { return [] }
    guard let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
    return box.elements
}

// MARK: - Tests

final class RuntimeComparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - compareBy ascending

    func testComparatorFromSelectorAscending() {
        let closureRaw = kk_comparator_from_selector(selectorPtr(selectIdentity), 0)
        // 3 < 7
        let result = kk_comparator_from_selector_trampoline(closureRaw, 3, 7, nil)
        XCTAssertLessThan(result, 0)
        // 7 > 3
        let result2 = kk_comparator_from_selector_trampoline(closureRaw, 7, 3, nil)
        XCTAssertGreaterThan(result2, 0)
        // equal
        let result3 = kk_comparator_from_selector_trampoline(closureRaw, 5, 5, nil)
        XCTAssertEqual(result3, 0)
    }

    // MARK: - compareByDescending

    func testComparatorFromSelectorDescending() {
        let closureRaw = kk_comparator_from_selector_descending(selectorPtr(selectIdentity), 0)
        var thrown = 0
        // descending: 3 vs 7 should be positive (3 comes after 7)
        let result = kk_comparator_from_selector_descending_trampoline(closureRaw, 3, 7, &thrown)
        XCTAssertGreaterThan(result, 0)
        XCTAssertEqual(thrown, 0)
        // descending: 7 vs 3 should be negative
        let result2 = kk_comparator_from_selector_descending_trampoline(closureRaw, 7, 3, &thrown)
        XCTAssertLessThan(result2, 0)
        // equal stays zero
        let result3 = kk_comparator_from_selector_descending_trampoline(closureRaw, 5, 5, &thrown)
        XCTAssertEqual(result3, 0)
    }

    // MARK: - thenBy

    func testComparatorThenBy() {
        // Primary: sort by (value % 10), tie-break by identity ascending
        let closureRaw = kk_comparator_then_by(
            comparatorPtr(comparatorByModTen),
            0,
            selectorPtr(selectIdentity),
            0
        )

        // 13 vs 23: both % 10 == 3, tie-break by value -> 13 < 23
        let result = kk_comparator_then_by_trampoline(closureRaw, 13, 23, nil)
        XCTAssertLessThan(result, 0)

        // 15 vs 23: 5 vs 3 -> 15 > 23 by primary key
        let result2 = kk_comparator_then_by_trampoline(closureRaw, 15, 23, nil)
        XCTAssertGreaterThan(result2, 0)
    }

    // MARK: - reversed

    func testComparatorReversed() {
        let closureRaw = kk_comparator_reversed(
            comparatorPtr(comparatorNatural),
            0
        )
        // reversed: 3 vs 7 should be positive
        let result = kk_comparator_reversed_trampoline(closureRaw, 3, 7, nil)
        XCTAssertGreaterThan(result, 0)
        // reversed: 7 vs 3 should be negative
        let result2 = kk_comparator_reversed_trampoline(closureRaw, 7, 3, nil)
        XCTAssertLessThan(result2, 0)
    }

    // MARK: - naturalOrder / reverseOrder

    func testNaturalOrderTrampoline() {
        XCTAssertLessThan(kk_comparator_natural_order_trampoline(0, 1, 5, nil), 0)
        XCTAssertGreaterThan(kk_comparator_natural_order_trampoline(0, 5, 1, nil), 0)
        XCTAssertEqual(kk_comparator_natural_order_trampoline(0, 3, 3, nil), 0)
    }

    func testReverseOrderTrampoline() {
        XCTAssertGreaterThan(kk_comparator_reverse_order_trampoline(0, 1, 5, nil), 0)
        XCTAssertLessThan(kk_comparator_reverse_order_trampoline(0, 5, 1, nil), 0)
        XCTAssertEqual(kk_comparator_reverse_order_trampoline(0, 3, 3, nil), 0)
    }

    // MARK: - sortedWith E2E

    func testSortedWithComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorNatural),
            0,
            nil
        )
        XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
    }

    func testSortedWithReversedComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorReversed),
            0,
            nil
        )
        XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
    }

    // MARK: - Exception propagation

    func testSelectorThrowPropagatesToTrampoline() {
        let closureRaw = kk_comparator_from_selector(selectorPtr(throwingSelector), 0)
        var thrown = 0
        let result = kk_comparator_from_selector_trampoline(closureRaw, 1, 2, &thrown)
        XCTAssertNotEqual(thrown, 0, "thrown should be set when selector throws")
        XCTAssertEqual(result, 0)
    }

    func testChainedComparatorThrowPropagation() {
        // Use a throwing comparator as primary
        let closureRaw = kk_comparator_then_by(
            comparatorPtr(throwingComparator),
            0,
            selectorPtr(selectIdentity),
            0
        )
        var thrown = 0
        let result = kk_comparator_then_by_trampoline(closureRaw, 1, 2, &thrown)
        XCTAssertNotEqual(thrown, 0, "thrown should propagate from chained comparator")
        XCTAssertEqual(result, 0)
    }

    // MARK: - Edge cases

    func testComparatorTrampolineWithNullClosureRawReturnsZero() {
        // closureRaw=0 means invalid PairBox -> should return 0 safely
        let result = kk_comparator_from_selector_trampoline(0, 1, 2, nil)
        XCTAssertEqual(result, 0)
    }

    func testReversedTrampolineWithNullClosureRawReturnsZero() {
        let result = kk_comparator_reversed_trampoline(0, 1, 2, nil)
        XCTAssertEqual(result, 0)
    }
}
