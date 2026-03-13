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

        XCTAssertEqual(extractString(from: renderedRaw), "[1:2:3]")
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
