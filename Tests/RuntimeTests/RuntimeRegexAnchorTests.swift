@testable import Runtime
import XCTest

final class RuntimeRegexAnchorTests: XCTestCase {
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

    func testAnchoredMatchEntireRequiresWholeString() {
        let regexRaw = kk_regex_create(makeRuntimeString("^abc$"))
        let full = kk_regex_matchEntire(regexRaw, makeRuntimeString("abc"))
        let partial = kk_regex_matchEntire(regexRaw, makeRuntimeString("zabc"))

        XCTAssertNotEqual(full, runtimeNullSentinelInt)
        XCTAssertEqual(partial, runtimeNullSentinelInt)
    }

    func testWordBoundaryPatternFindsWholeWordOnly() {
        let regexRaw = kk_regex_create(makeRuntimeString("\\bcat\\b"))
        let match = kk_regex_find(regexRaw, makeRuntimeString("a cat naps"))
        let noMatch = kk_regex_find(regexRaw, makeRuntimeString("concatenate"))

        XCTAssertNotEqual(match, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(match)), "cat")
        XCTAssertEqual(noMatch, runtimeNullSentinelInt)
    }

    func testLookaheadPatternMatchesExpectedPrefix() {
        let regexRaw = kk_regex_create(makeRuntimeString("foo(?=bar)"))
        let match = kk_regex_find(regexRaw, makeRuntimeString("foobar"))
        let noMatch = kk_regex_find(regexRaw, makeRuntimeString("foobaz"))

        XCTAssertNotEqual(match, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(match)), "foo")
        XCTAssertEqual(noMatch, runtimeNullSentinelInt)
    }
}
