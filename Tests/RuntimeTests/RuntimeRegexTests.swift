@testable import Runtime
import XCTest

final class RuntimeRegexTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    private func runtimeListStrings(_ raw: Int) -> [String] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements.map(runtimeString)
    }

    func testMatchResultValueAndGroupValues() {
        let regexRaw = kk_regex_create(makeRuntimeString("(ab)(cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))

        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "abcd")
        XCTAssertEqual(runtimeListStrings(kk_match_result_groupValues(matchRaw)), ["abcd", "ab", "cd"])
    }

    func testMatchGroupCollectionGetAndRange() {
        let regexRaw = kk_regex_create(makeRuntimeString("(?<lhs>ab)(?<rhs>cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))
        let groupsRaw = kk_match_result_groups(matchRaw)
        let lhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("lhs"))
        let rhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("rhs"))

        XCTAssertNotEqual(lhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertNotEqual(rhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_group_value(lhsGroupRaw)), "ab")
        XCTAssertEqual(runtimeString(kk_match_group_value(rhsGroupRaw)), "cd")

        let lhsRangeRaw = kk_match_group_range(lhsGroupRaw)
        let rhsRangeRaw = kk_match_group_range(rhsGroupRaw)

        guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhsRangeRaw),
              let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhsRangeRaw),
              let lhsRange = tryCast(lhsPtr, to: RuntimeRangeBox.self),
              let rhsRange = tryCast(rhsPtr, to: RuntimeRangeBox.self) else {
            return XCTFail("Expected range boxes for named groups")
        }

        XCTAssertEqual(lhsRange.first, 2)
        XCTAssertEqual(lhsRange.last, 3)
        XCTAssertEqual(rhsRange.first, 4)
        XCTAssertEqual(rhsRange.last, 5)
    }
}
