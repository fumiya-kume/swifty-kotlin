@testable import Runtime
import XCTest

final class RuntimeTestFrameworkTests: XCTestCase {
    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func assertThrownMessage(
        _ thrown: Int,
        contains fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            XCTFail("Expected a RuntimeThrowableBox", file: file, line: line)
            return
        }
        XCTAssertTrue(throwable.message.hasPrefix("AssertionError:"), file: file, line: line)
        XCTAssertTrue(throwable.message.contains(fragment), file: file, line: line)
    }

    func testAssertEqualsPassesAndFails() {
        var thrown = 0
        _ = kk_test_assertEquals(kk_box_int(1), kk_box_int(1), &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_test_assertEquals(kk_box_int(1), kk_box_int(2), &thrown)
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "Expected <1> but was <2>.")
    }

    func testAssertEqualsHandlesStrings() {
        var thrown = 0
        let first = makeRuntimeString("hello")
        let second = makeRuntimeString("he" + "llo")
        _ = kk_test_assertEquals(first, second, &thrown)
        XCTAssertEqual(thrown, 0)
    }

    func testAssertTruePassesAndFails() {
        var thrown = 0
        _ = kk_test_assertTrue(kk_box_bool(1), &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_test_assertTrue(0, &thrown)
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "Expected value to be true.")
    }

    func testAssertTrueMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertTrue_message(0, makeRuntimeString("custom truth message"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "custom truth message")
    }

    func testAssertNullPassesAndFails() {
        var thrown = 0
        _ = kk_test_assertNull(runtimeNullSentinelInt, &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_test_assertNull(kk_box_int(1), &thrown)
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "Expected value to be null")
    }

    func testAssertNullMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertNull_message(kk_box_int(1), makeRuntimeString("custom null message"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "custom null message")
    }

    func testAssertEqualsMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertEquals_message(
            kk_box_int(1),
            kk_box_int(2),
            makeRuntimeString("custom equality message"),
            &thrown
        )
        XCTAssertNotEqual(thrown, 0)
        assertThrownMessage(thrown, contains: "custom equality message")
    }
}
