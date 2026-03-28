@testable import Runtime
import XCTest

final class RuntimeRegexNamedGroupTests: XCTestCase {
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

    func testNamedGroupsExposeValuesByName() {
        let regexRaw = kk_regex_create(makeRuntimeString("(?<lhs>ab)(?<rhs>cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))
        let groupsRaw = kk_match_result_groups(matchRaw)

        let lhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("lhs"))
        let rhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("rhs"))

        XCTAssertNotEqual(lhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertNotEqual(rhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_group_value(lhsGroupRaw)), "ab")
        XCTAssertEqual(runtimeString(kk_match_group_value(rhsGroupRaw)), "cd")
    }

    func testMissingNamedGroupReturnsNullSentinel() {
        let regexRaw = kk_regex_create(makeRuntimeString("(?<lhs>ab)(?<rhs>cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))
        let groupsRaw = kk_match_result_groups(matchRaw)

        let missing = kk_match_group_collection_get(groupsRaw, makeRuntimeString("missing"))
        XCTAssertEqual(missing, runtimeNullSentinelInt)
    }
}
