#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeRegexNamedGroupTests {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func makeRegex(_ pattern: String) -> Int {
        withFlatString(pattern) { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
    }

    private func find(regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func groupIndex(_ matchRaw: Int, named name: String) -> Int {
        withFlatString(name) { data, length, byteCount, hash in
            __kk_match_result_group_index_of_name_flat(matchRaw, data, length, byteCount, hash)
        }
    }

    private func hasNamedGroup(_ matchRaw: Int, named name: String) -> Bool {
        Array(name.utf8).withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            let nameRaw = Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(name.utf8.count)))
            return __kk_match_result_has_named_group(matchRaw, nameRaw) != 0
        }
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    @Test
    func testNamedGroupsExposeValuesByName() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")

        let lhsIndex = groupIndex(matchRaw, named: "lhs")
        let rhsIndex = groupIndex(matchRaw, named: "rhs")

        #expect(lhsIndex == 1)
        #expect(rhsIndex == 2)
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, lhsIndex)) == "ab")
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, rhsIndex)) == "cd")
    }

    @Test
    func testMissingNamedGroupReturnsNegativeIndex() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")

        #expect(groupIndex(matchRaw, named: "missing") == -1)
    }

    @Test
    func testDeclaredUnmatchedNamedGroupIsDistinguishedFromMissingGroup() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<optional>a)?")
        let matchRaw = find(regexRaw: regexRaw, input: "")

        #expect(hasNamedGroup(matchRaw, named: "optional"))
        #expect(!hasNamedGroup(matchRaw, named: "missing"))
        #expect(groupIndex(matchRaw, named: "optional") == -1)
    }

    @Test
    func testNamedGroupIndicesForMultipleNames() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})")
        let matchRaw = find(regexRaw: regexRaw, input: "on 2024-05-06.")

        #expect(runtimeString(__kk_match_result_group_value(matchRaw, groupIndex(matchRaw, named: "year"))) == "2024")
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, groupIndex(matchRaw, named: "month"))) == "05")
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, groupIndex(matchRaw, named: "day"))) == "06")
    }

    @Test
    func testPatternBridgeRoundTripsUnnamedPattern() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(\\d+)-(\\d+)")
        let matchRaw = find(regexRaw: regexRaw, input: "12-34")

        #expect(runtimeString(__kk_regex_pattern(regexRaw)) == "(\\d+)-(\\d+)")
        #expect(groupIndex(matchRaw, named: "year") == -1)
    }
}
#endif
