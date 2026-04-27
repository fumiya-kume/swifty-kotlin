import Foundation
@testable import Runtime
import XCTest

// MARK: - Trampoline wrappers
// Local @convention(c) closures that delegate to the @_cdecl runtime functions.
// We must NOT pass @_cdecl functions directly to comparatorPtr() because Swift
// would re-export the C symbol in this module, causing duplicate symbol linker errors.

private let thenByTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_then_by_trampoline(closureRaw, a, b, outThrown)
}

private let thenByDescendingTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_then_by_descending_trampoline(closureRaw, a, b, outThrown)
}

private let thenDescendingTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_then_descending_trampoline(closureRaw, a, b, outThrown)
}

private let thenComparatorTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_then_comparator_trampoline(closureRaw, a, b, outThrown)
}

private let nullsFirstTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_nulls_first_trampoline(closureRaw, a, b, outThrown)
}

private let primitiveComparatorTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_from_selector_primitive_trampoline(closureRaw, a, b, outThrown)
}

private let selectorComparatorTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_from_selector_trampoline(closureRaw, a, b, outThrown)
}

private let primitiveComparatorDescendingTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_from_selector_primitive_descending_trampoline(closureRaw, a, b, outThrown)
}

// MARK: - Test lambdas

private let selectIdentity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value
}

private let selectModTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 10
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

private let comparatorObjectCompare: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, a, b, _ in
    guard let receiverPtr = UnsafeMutableRawPointer(bitPattern: receiver) else {
        return 0
    }
    guard let box = tryCast(receiverPtr, to: RuntimeObjectBox.self) else {
        return 0
    }
    let mode = box.elements.first ?? 0
    if mode == 0 {
        if a < b { return -1 }
        if a > b { return 1 }
        return 0
    }
    if a < b { return 1 }
    if a > b { return -1 }
    return 0
}

// MARK: - Helpers

private func selectorPtr(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func comparatorPtr(_ fn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func primitiveComparatorPtr(_ fn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func makeList(_ elements: [Int]) -> Int {
    let box = RuntimeListBox(elements: elements)
    return registerRuntimeObject(box)
}

private func makeArray(_ elements: [Int]) -> Int {
    let array = kk_array_new(elements.count)
    var thrown = 0
    for (index, element) in elements.enumerated() {
        _ = kk_array_set(array, index, element, &thrown)
    }
    return array
}

private func listElements(_ listRaw: Int) -> [Int] {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw) else { return [] }
    guard let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
    return box.elements
}

private func withComparatorObject(mode: Int, body: (Int) -> Void) {
    let object = kk_object_new(1, 0)
    let payload = UnsafeMutableRawPointer(bitPattern: object)!
    guard let box = tryCast(payload, to: RuntimeObjectBox.self) else {
        return
    }
    box.elements[0] = mode
    _ = kk_object_register_itable_method(object, 0, 0, unsafeBitCast(comparatorObjectCompare, to: Int.self))
    body(object)
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

    func testPrimitiveComparatorFromSelectorAscending() {
        let closureRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        let result = kk_comparator_from_selector_primitive_trampoline(closureRaw, 3, 7, nil)
        XCTAssertLessThan(result, 0)
        XCTAssertGreaterThan(kk_comparator_from_selector_primitive_trampoline(closureRaw, 7, 3, nil), 0)
        XCTAssertEqual(kk_comparator_from_selector_primitive_trampoline(closureRaw, 5, 5, nil), 0)
    }

    func testPrimitiveComparatorFromSelectorDescending() {
        let closureRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        var thrown = 0
        XCTAssertGreaterThan(
            kk_comparator_from_selector_primitive_descending_trampoline(closureRaw, 3, 7, &thrown),
            0
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertLessThan(
            kk_comparator_from_selector_primitive_descending_trampoline(closureRaw, 7, 3, &thrown),
            0
        )
    }

    func testComparatorFromComparatorSelectorDescending() {
        withComparatorObject(mode: 0) { comparatorRaw in
            let closureRaw = kk_comparator_from_comparator_selector_descending(
                comparatorRaw,
                selectorPtr(selectModTen),
                0
            )
            var thrown = 0
            XCTAssertGreaterThan(
                kk_comparator_from_comparator_selector_descending_trampoline(closureRaw, 13, 25, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
            XCTAssertLessThan(
                kk_comparator_from_comparator_selector_descending_trampoline(closureRaw, 25, 13, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(
                kk_comparator_from_comparator_selector_descending_trampoline(closureRaw, 13, 23, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testComparatorFromComparatorSelector() {
        withComparatorObject(mode: 0) { comparatorRaw in
            let closureRaw = kk_comparator_from_comparator_selector(
                comparatorRaw,
                selectorPtr(selectModTen),
                0
            )
            var thrown = 0
            XCTAssertLessThan(
                kk_comparator_from_comparator_selector_trampoline(closureRaw, 13, 25, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
            XCTAssertGreaterThan(
                kk_comparator_from_comparator_selector_trampoline(closureRaw, 25, 13, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(
                kk_comparator_from_comparator_selector_trampoline(closureRaw, 13, 23, &thrown),
                0
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testComparatorFromMultiSelectorsVararg() {
        let selectors = makeArray([
            selectorPtr(selectModTen), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
        ])
        let closureRaw = kk_comparator_from_multi_selectors_vararg(selectors)

        XCTAssertLessThan(kk_comparator_from_multi_selectors_trampoline(closureRaw, 13, 25, nil), 0)
        XCTAssertLessThan(kk_comparator_from_multi_selectors_trampoline(closureRaw, 13, 23, nil), 0)
        XCTAssertEqual(kk_comparator_from_multi_selectors_trampoline(closureRaw, 17, 17, nil), 0)
    }

    func testCompareValuesByVarargSelectors() {
        let selectors = makeArray([
            selectorPtr(selectModTen), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
        ])
        var thrown = 0
        let result = kk_compareValuesByVararg(13, 25, selectors, &thrown)
        XCTAssertEqual(kk_unbox_int(result), -1)
        XCTAssertEqual(thrown, 0)

        let tiedFirstKey = kk_compareValuesByVararg(13, 23, selectors, &thrown)
        XCTAssertEqual(kk_unbox_int(tiedFirstKey), -1)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesByComparatorSelector() {
        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0
            let result = kk_compareValuesByComparator(
                13,
                25,
                comparatorRaw,
                selectorPtr(selectModTen),
                0,
                &thrown
            )
            XCTAssertEqual(kk_unbox_int(result), -1)
            XCTAssertEqual(thrown, 0)
        }
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

    // MARK: - thenDescending

    func testComparatorThenDescending() {
        let closureRaw = kk_comparator_then_descending(
            comparatorPtr(comparatorByModTen),
            0,
            comparatorPtr(comparatorNatural),
            0
        )

        var thrown = 0
        let result = kk_comparator_then_descending_trampoline(closureRaw, 13, 23, &thrown)
        XCTAssertGreaterThan(result, 0)
        XCTAssertEqual(thrown, 0)

        let result2 = kk_comparator_then_descending_trampoline(closureRaw, 15, 23, &thrown)
        XCTAssertGreaterThan(result2, 0)
        XCTAssertEqual(thrown, 0)

        let result3 = kk_comparator_then_descending_trampoline(closureRaw, 23, 13, &thrown)
        XCTAssertLessThan(result3, 0)
    }

    // MARK: - thenComparator

    func testComparatorThenComparator() {
        let closureRaw = kk_comparator_then_comparator(
            comparatorPtr(comparatorByModTen),
            0,
            comparatorPtr(comparatorReversed),
            0
        )

        let result = kk_comparator_then_comparator_trampoline(closureRaw, 13, 23, nil)
        XCTAssertGreaterThan(result, 0)

        let result2 = kk_comparator_then_comparator_trampoline(closureRaw, 15, 23, nil)
        XCTAssertGreaterThan(result2, 0)
    }

    func testComparatorThenByComparatorSelector() {
        let keyComparatorRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        let closureRaw = kk_comparator_then_by_comparator_selector(
            comparatorPtr(comparatorByModTen),
            0,
            keyComparatorRaw,
            selectorPtr(selectIdentity),
            0
        )

        var thrown = 0
        XCTAssertLessThan(kk_comparator_then_by_comparator_selector_trampoline(closureRaw, 13, 23, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThan(kk_comparator_then_by_comparator_selector_trampoline(closureRaw, 23, 13, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThan(kk_comparator_then_by_comparator_selector_trampoline(closureRaw, 15, 23, &thrown), 0)
        XCTAssertEqual(thrown, 0)
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

    func testPrimitiveComparatorReversed() {
        let primitiveClosureRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        let closureRaw = kk_comparator_reversed(
            primitiveComparatorPtr(selectorComparatorTrampoline),
            primitiveClosureRaw
        )

        XCTAssertGreaterThan(kk_comparator_reversed_trampoline(closureRaw, 3, 7, nil), 0)
        XCTAssertLessThan(kk_comparator_reversed_trampoline(closureRaw, 7, 3, nil), 0)
        XCTAssertEqual(kk_comparator_reversed_trampoline(closureRaw, 5, 5, nil), 0)
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

    func testPrimitiveListSortedAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sorted_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
    }

    func testPrimitiveListSortedDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedDescending_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
    }

    func testPrimitiveListSortedByAscending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        XCTAssertEqual(listElements(sorted), [21, 11, 22, 12])
    }

    func testPrimitiveListSortedByDescending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        XCTAssertEqual(listElements(sorted), [22, 12, 21, 11])
    }

    func testPrimitiveListSortedStability() {
        let source = makeList([2, 1, 2, 1, 2])
        let sorted = kk_list_sorted_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [1, 1, 2, 2, 2])
    }

    func testPrimitiveListSortedFloatAndDouble() {
        let floatValues = [
            kk_box_float(Int(truncatingIfNeeded: Float(3.0).bitPattern)),
            kk_box_float(Int(truncatingIfNeeded: Float(1.5).bitPattern)),
            kk_box_float(Int(truncatingIfNeeded: Float(2.0).bitPattern)),
        ]
        let doubleValues = [
            kk_box_double(Int(truncatingIfNeeded: Double(3.0).bitPattern)),
            kk_box_double(Int(truncatingIfNeeded: Double(1.5).bitPattern)),
            kk_box_double(Int(truncatingIfNeeded: Double(2.0).bitPattern)),
        ]

        let floatSorted = kk_list_sorted_primitive(makeList(floatValues), 6)
        let doubleSorted = kk_list_sorted_primitive(makeList(doubleValues), 7)

        XCTAssertEqual(
            listElements(floatSorted).map { kk_unbox_float($0) },
            [Float(1.5).bitPattern, Float(2.0).bitPattern, Float(3.0).bitPattern].map { Int(truncatingIfNeeded: $0) }
        )
        XCTAssertEqual(
            listElements(doubleSorted).map { kk_unbox_double($0) },
            [Double(1.5).bitPattern, Double(2.0).bitPattern, Double(3.0).bitPattern].map { Int(truncatingIfNeeded: $0) }
        )
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

    func testSortedWithComparatorObjectDispatchesThroughVtable() {
        let source = makeList([5, 3, 8, 1, 4])

        withComparatorObject(mode: 0) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
        }

        withComparatorObject(mode: 1) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
        }
    }

    func testArrayBinarySearchCompareWithComparatorObjectAndRange() {
        let source = makeArray([1, 3, 5, 7, 9])

        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0

            let found = kk_array_binarySearch_compare(source, 5, comparatorRaw, 0, 0, 5, &thrown)
            XCTAssertEqual(found, 2)
            XCTAssertEqual(thrown, 0)

            let missing = kk_array_binarySearch_compare(source, 4, comparatorRaw, 0, 0, 5, &thrown)
            XCTAssertEqual(missing, -3)
            XCTAssertEqual(thrown, 0)

            let ranged = kk_array_binarySearch_compare(source, 7, comparatorRaw, 0, 2, 5, &thrown)
            XCTAssertEqual(ranged, 3)
            XCTAssertEqual(thrown, 0)
        }
    }

    func testBinarySearchComparatorWithExplicitRange() {
        let source = makeList([1, 3, 5, 7, 9])
        var thrown = 0

        let found = kk_list_binarySearch_comparator(
            source,
            5,
            comparatorPtr(comparatorNatural),
            0,
            1,
            4,
            &thrown
        )
        XCTAssertEqual(found, 2)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        let missing = kk_list_binarySearch_comparator(
            source,
            6,
            comparatorPtr(comparatorNatural),
            0,
            1,
            4,
            &thrown
        )
        XCTAssertEqual(missing, -4)
        XCTAssertEqual(thrown, 0)
    }

    func testBinarySearchComparatorObjectDispatchesThroughVtable() {
        let ascending = makeList([1, 3, 5, 7, 9])
        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0
            let found = kk_list_binarySearch_comparator(
                ascending,
                7,
                comparatorRaw,
                0,
                0,
                5,
                &thrown
            )
            XCTAssertEqual(found, 3)
            XCTAssertEqual(thrown, 0)
        }

        let descending = makeList([9, 7, 5, 3, 1])
        withComparatorObject(mode: 1) { comparatorRaw in
            var thrown = 0
            let found = kk_list_binarySearch_comparator(
                descending,
                5,
                comparatorRaw,
                0,
                0,
                5,
                &thrown
            )
            XCTAssertEqual(found, 2)
            XCTAssertEqual(thrown, 0)
        }
    }

    func testBinarySearchComparatorRangeValidationThrows() {
        let source = makeList([1, 3, 5, 7, 9])
        var thrown = 0
        let result = kk_list_binarySearch_comparator(
            source,
            5,
            comparatorPtr(comparatorNatural),
            0,
            4,
            2,
            &thrown
        )
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSortedWithPrimitiveComparatorObjectDispatchesThroughITable() {
        let source = makeList([5, 3, 8, 1, 4])
        let comparatorRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
        XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
    }

    func testSortedWithPrimitiveDescendingComparatorObjectDispatchesThroughITable() {
        let source = makeList([5, 3, 8, 1, 4])
        let comparatorRaw = kk_comparator_from_selector_primitive_descending(selectorPtr(selectIdentity), 0, 0)
        let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
        XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
    }

    func testArrayBinarySearchCompareObjectDispatchesThroughVtable() {
        let source = makeArray([1, 3, 4, 9])

        withComparatorObject(mode: 0) { comparatorRaw in
            let hit = kk_array_binarySearch_compare(source, 4, comparatorRaw, 0, 0, 4, nil)
            XCTAssertEqual(hit, 2)

            let miss = kk_array_binarySearch_compare(source, 5, comparatorRaw, 0, 1, 3, nil)
            XCTAssertEqual(miss, -4)
        }
    }

    func testMutableListPrimitiveSortAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        XCTAssertEqual(kk_mutable_list_sort_primitive(source, 0), 0)
        XCTAssertEqual(listElements(source), [1, 3, 4, 5, 8])
    }

    func testMutableListPrimitiveSortDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        XCTAssertEqual(kk_mutable_list_sortDescending_primitive(source, 0), 0)
        XCTAssertEqual(listElements(source), [8, 5, 4, 3, 1])
    }

    func testMutableListPrimitiveSortByAscending() {
        let source = makeList([22, 12, 21, 11])
        XCTAssertEqual(kk_mutable_list_sortBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil), 0)
        XCTAssertEqual(listElements(source), [21, 11, 22, 12])
    }

    func testMutableListPrimitiveSortByDescending() {
        let source = makeList([22, 12, 21, 11])
        XCTAssertEqual(kk_mutable_list_sortByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil), 0)
        XCTAssertEqual(listElements(source), [22, 12, 21, 11])
    }

    func testSortedWithThenByComparator() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        let chain = kk_comparator_then_by(
            comparatorPtr(comparatorByModTen),
            0,
            selectorPtr(selectIdentity),
            0
        )
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(thenByTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [3, 13, 23, 14, 24, 5])
    }

    func testSortedWithThenByDescendingComparator() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        let chain = kk_comparator_then_by_descending(
            comparatorPtr(comparatorByModTen),
            0,
            selectorPtr(selectIdentity),
            0
        )
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(thenByDescendingTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [23, 13, 3, 24, 14, 5])
    }

    func testSortedWithThenDescendingComparator() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        let chain = kk_comparator_then_descending(
            comparatorPtr(comparatorByModTen),
            0,
            comparatorPtr(comparatorNatural),
            0
        )
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(thenDescendingTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [23, 13, 3, 24, 14, 5])
    }

    func testSortedWithThenComparator() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        let chain = kk_comparator_then_comparator(
            comparatorPtr(comparatorByModTen),
            0,
            comparatorPtr(comparatorReversed),
            0
        )
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(thenComparatorTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [23, 13, 3, 24, 14, 5])
    }

    func testSortedWithNullsFirstComparator() {
        let source = makeList([5, runtimeNullSentinelInt, 3, runtimeNullSentinelInt, 4, 1])
        let chain = kk_comparator_nulls_first(comparatorPtr(comparatorNatural), 0)
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(nullsFirstTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [runtimeNullSentinelInt, runtimeNullSentinelInt, 1, 3, 4, 5])
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

    func testThenComparatorThrowPropagation() {
        let closureRaw = kk_comparator_then_comparator(
            comparatorPtr(comparatorNatural),
            0,
            comparatorPtr(throwingComparator),
            0
        )
        var thrown = 0
        let result = kk_comparator_then_comparator_trampoline(closureRaw, 1, 1, &thrown)
        XCTAssertNotEqual(thrown, 0, "thrown should propagate from thenComparator secondary comparator")
        XCTAssertEqual(result, 0)
    }

    func testThenDescendingThrowPropagation() {
        let closureRaw = kk_comparator_then_descending(
            comparatorPtr(comparatorNatural),
            0,
            comparatorPtr(throwingComparator),
            0
        )
        var thrown = 0
        let result = kk_comparator_then_descending_trampoline(closureRaw, 1, 1, &thrown)
        XCTAssertNotEqual(thrown, 0, "thrown should propagate from thenDescending secondary comparator")
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

    func testComparatorNullsFirstTrampoline() {
        let chain = kk_comparator_nulls_first(comparatorPtr(comparatorNatural), 0)
        XCTAssertLessThan(kk_comparator_nulls_first_trampoline(chain, runtimeNullSentinelInt, 5, nil), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_first_trampoline(chain, 5, runtimeNullSentinelInt, nil), 0)
        XCTAssertLessThan(kk_comparator_nulls_first_trampoline(chain, 3, 5, nil), 0)
        XCTAssertEqual(kk_comparator_nulls_first_trampoline(chain, runtimeNullSentinelInt, runtimeNullSentinelInt, nil), 0)
    }

    func testComparatorNullsLastTrampoline() {
        let chain = kk_comparator_nulls_last(comparatorPtr(comparatorNatural), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_last_trampoline(chain, runtimeNullSentinelInt, 5, nil), 0)
        XCTAssertLessThan(kk_comparator_nulls_last_trampoline(chain, 5, runtimeNullSentinelInt, nil), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_last_trampoline(chain, 5, 3, nil), 0)
        XCTAssertEqual(kk_comparator_nulls_last_trampoline(chain, runtimeNullSentinelInt, runtimeNullSentinelInt, nil), 0)
    }

    func testComparatorThenByDescendingTrampoline() {
        let chain = kk_comparator_then_by_descending(
            comparatorPtr(comparatorByModTen),
            0,
            selectorPtr(selectIdentity),
            0
        )
        XCTAssertGreaterThan(kk_comparator_then_by_descending_trampoline(chain, 13, 23, nil), 0)
        XCTAssertLessThan(kk_comparator_then_by_descending_trampoline(chain, 23, 13, nil), 0)
        XCTAssertGreaterThan(kk_comparator_then_by_descending_trampoline(chain, 15, 23, nil), 0)
    }

    func testComparatorThenByDescendingComparatorSelector() {
        let keyComparatorRaw = kk_comparator_from_selector_primitive(selectorPtr(selectIdentity), 0, 0)
        let chain = kk_comparator_then_by_descending_comparator_selector(
            comparatorPtr(comparatorByModTen),
            0,
            keyComparatorRaw,
            selectorPtr(selectIdentity),
            0
        )

        var thrown = 0
        XCTAssertGreaterThan(kk_comparator_then_by_descending_comparator_selector_trampoline(chain, 13, 23, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertLessThan(kk_comparator_then_by_descending_comparator_selector_trampoline(chain, 23, 13, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThan(kk_comparator_then_by_descending_comparator_selector_trampoline(chain, 15, 23, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testComparatorThenDescendingTrampolineWithNullClosureRawReturnsZero() {
        XCTAssertEqual(kk_comparator_then_descending_trampoline(0, 1, 2, nil), 0)
    }
}
