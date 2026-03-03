@testable import Runtime
import XCTest

final class RuntimeBoxingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - kk_box_int / kk_unbox_int

    func testBoxAndUnboxIntRoundTrip() {
        let boxed = kk_box_int(42)
        let unboxed = kk_unbox_int(boxed)
        XCTAssertEqual(unboxed, 42)
    }

    func testBoxIntNullSentinelPassesThrough() {
        let sentinel = Int(Int64.min)
        let result = kk_box_int(sentinel)
        XCTAssertEqual(result, sentinel)
    }

    func testUnboxIntNullSentinelReturnsZero() {
        let sentinel = Int(Int64.min)
        let result = kk_unbox_int(sentinel)
        XCTAssertEqual(result, 0)
    }

    func testUnboxIntNonBoxedValueReturnsValueUnchanged() {
        // A small integer that was never boxed should pass through
        let result = kk_unbox_int(7)
        XCTAssertEqual(result, 7)
    }

    func testBoxIntNegativeValue() {
        let boxed = kk_box_int(-100)
        let unboxed = kk_unbox_int(boxed)
        XCTAssertEqual(unboxed, -100)
    }

    func testBoxIntZero() {
        let boxed = kk_box_int(0)
        let unboxed = kk_unbox_int(boxed)
        XCTAssertEqual(unboxed, 0)
    }

    // MARK: - kk_box_bool / kk_unbox_bool

    func testBoxAndUnboxBoolTrueRoundTrip() {
        let boxed = kk_box_bool(1)
        let unboxed = kk_unbox_bool(boxed)
        XCTAssertEqual(unboxed, 1)
    }

    func testBoxAndUnboxBoolFalseRoundTrip() {
        let boxed = kk_box_bool(0)
        let unboxed = kk_unbox_bool(boxed)
        XCTAssertEqual(unboxed, 0)
    }

    func testBoxBoolNullSentinelPassesThrough() {
        let sentinel = Int(Int64.min)
        let result = kk_box_bool(sentinel)
        XCTAssertEqual(result, sentinel)
    }

    func testUnboxBoolNullSentinelReturnsZero() {
        let sentinel = Int(Int64.min)
        let result = kk_unbox_bool(sentinel)
        XCTAssertEqual(result, 0)
    }

    func testUnboxBoolNonBoxedNonZeroReturnsOne() {
        // A non-zero non-boxed value should return 1 (truthy)
        let result = kk_unbox_bool(42)
        XCTAssertEqual(result, 1)
    }

    func testUnboxBoolNonBoxedZeroReturnsZero() {
        // Unboxing 0 that was never boxed returns 0 (nil pointer guard path)
        let result = kk_unbox_bool(0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Multiple boxes

    func testMultipleBoxedIntsAreIndependent() {
        let boxed1 = kk_box_int(10)
        let boxed2 = kk_box_int(20)
        XCTAssertEqual(kk_unbox_int(boxed1), 10)
        XCTAssertEqual(kk_unbox_int(boxed2), 20)
    }
}
