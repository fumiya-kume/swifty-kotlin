@testable import Runtime
import XCTest

final class RuntimeStringBuilderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // STDLIB-TEXT-FN-024: insert
    func testInsertObjInsertsValueAtIndexAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ac"))
        let value = makeRuntimeString("b")

        let returned = kk_string_builder_insert_obj(builder, 1, value)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeAppendsSubstringSliceAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
        let value = makeRuntimeString("WORLD")

        let returned = kk_string_builder_appendRange_obj(builder, value, 1, 4)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "helloORL")
    }

    func testAppendRangeFromEmptyRangeAppendsNothing() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
        let value = makeRuntimeString("XYZ")

        let returned = kk_string_builder_appendRange_obj(builder, value, 2, 2)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtBeginningPrependsValue() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("bc"))
        let value = makeRuntimeString("a")

        _ = kk_string_builder_insert_obj(builder, 0, value)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtEndAppendsValue() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ab"))
        let value = makeRuntimeString("c")

        _ = kk_string_builder_insert_obj(builder, 2, value)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testDeleteAtRemovesCharacterAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))

        let returned = kk_string_builder_deleteAt(builder, 1)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "ac")
    }

    func testDeleteRangeRemovesRangeAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abcdef"))

        let returned = kk_string_builder_deleteRange(builder, 1, 4)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aef")
    }

    func testInsertRangeInsertsValueSliceAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ab"))
        let value = makeRuntimeString("WXYZ")

        let returned = kk_string_builder_insertRange_obj(builder, 1, value, 1, 3)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYb")
    }

    func testSetRangeReplacesRangeAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abcd"))
        let value = makeRuntimeString("XYZ")

        let returned = kk_string_builder_setRange(builder, 1, 3, value)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYZd")
    }

    // STDLIB-TEXT-FN-064: operator fun set(index, value) — backed by kk_string_builder_setCharAt
    func testSetCharAtReplacesCharacterAtIndex() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))

        let returned = kk_string_builder_setCharAt(builder, 1, kk_box_char(Int(Unicode.Scalar("X").value)))

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXc")
    }

    func testSetCharAtFirstIndexReplacesCharacter() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))

        _ = kk_string_builder_setCharAt(builder, 0, kk_box_char(Int(Unicode.Scalar("H").value)))

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "Hello")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
