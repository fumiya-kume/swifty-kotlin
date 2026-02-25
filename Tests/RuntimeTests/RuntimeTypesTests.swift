import XCTest
@testable import Runtime

final class RuntimeTypesTests: XCTestCase {

    // MARK: - RuntimeStringBox

    func testRuntimeStringBoxStoresValue() {
        let box = RuntimeStringBox("hello")
        XCTAssertEqual(box.value, "hello")
    }

    func testRuntimeStringBoxStoresEmptyString() {
        let box = RuntimeStringBox("")
        XCTAssertEqual(box.value, "")
    }

    func testRuntimeStringBoxStoresUnicodeString() {
        let box = RuntimeStringBox("こんにちは")
        XCTAssertEqual(box.value, "こんにちは")
    }

    // MARK: - RuntimeThrowableBox

    func testRuntimeThrowableBoxStoresMessage() {
        let box = RuntimeThrowableBox(message: "Something went wrong")
        XCTAssertEqual(box.message, "Something went wrong")
    }

    func testRuntimeThrowableBoxStoresEmptyMessage() {
        let box = RuntimeThrowableBox(message: "")
        XCTAssertEqual(box.message, "")
    }

    // MARK: - RuntimeArrayBox

    func testRuntimeArrayBoxCreatesZeroFilledArray() {
        let box = RuntimeArrayBox(length: 5)
        XCTAssertEqual(box.elements.count, 5)
        XCTAssertTrue(box.elements.allSatisfy { $0 == 0 })
    }

    func testRuntimeArrayBoxWithZeroLengthCreatesEmptyArray() {
        let box = RuntimeArrayBox(length: 0)
        XCTAssertTrue(box.elements.isEmpty)
    }

    func testRuntimeArrayBoxWithNegativeLengthCreatesEmptyArray() {
        let box = RuntimeArrayBox(length: -10)
        XCTAssertTrue(box.elements.isEmpty)
    }

    func testRuntimeArrayBoxIsMutable() {
        let box = RuntimeArrayBox(length: 3)
        box.elements[1] = 42
        XCTAssertEqual(box.elements[1], 42)
    }

    // MARK: - RuntimeIntBox

    func testRuntimeIntBoxStoresPositiveValue() {
        let box = RuntimeIntBox(42)
        XCTAssertEqual(box.value, 42)
    }

    func testRuntimeIntBoxStoresNegativeValue() {
        let box = RuntimeIntBox(-100)
        XCTAssertEqual(box.value, -100)
    }

    func testRuntimeIntBoxStoresZero() {
        let box = RuntimeIntBox(0)
        XCTAssertEqual(box.value, 0)
    }

    // MARK: - RuntimeBoolBox

    func testRuntimeBoolBoxStoresTrue() {
        let box = RuntimeBoolBox(true)
        XCTAssertTrue(box.value)
    }

    func testRuntimeBoolBoxStoresFalse() {
        let box = RuntimeBoolBox(false)
        XCTAssertFalse(box.value)
    }

    // MARK: - LazyThreadSafetyMode

    func testLazyThreadSafetyModeSynchronizedRawValueIsOne() {
        XCTAssertEqual(LazyThreadSafetyMode.synchronized.rawValue, 1)
    }

    func testLazyThreadSafetyModeNoneRawValueIsZero() {
        XCTAssertEqual(LazyThreadSafetyMode.none.rawValue, 0)
    }

    func testLazyThreadSafetyModeInitFromRawValue() {
        XCTAssertEqual(LazyThreadSafetyMode(rawValue: 1), .synchronized)
        XCTAssertEqual(LazyThreadSafetyMode(rawValue: 0), LazyThreadSafetyMode.none)
    }

    // MARK: - RuntimeObservableBox

    func testRuntimeObservableBoxStoresInitialValue() {
        let box = RuntimeObservableBox(initialValue: 42, callbackFnPtr: 0)
        XCTAssertEqual(box.currentValue, 42)
    }

    func testRuntimeObservableBoxStoresCallbackPointer() {
        let ptr = 12345
        let box = RuntimeObservableBox(initialValue: 0, callbackFnPtr: ptr)
        XCTAssertEqual(box.callbackFnPtr, ptr)
    }

    func testRuntimeObservableBoxCurrentValueIsMutable() {
        let box = RuntimeObservableBox(initialValue: 0, callbackFnPtr: 0)
        box.currentValue = 99
        XCTAssertEqual(box.currentValue, 99)
    }

    // MARK: - RuntimeVetoableBox

    func testRuntimeVetoableBoxStoresInitialValue() {
        let box = RuntimeVetoableBox(initialValue: 7, callbackFnPtr: 0)
        XCTAssertEqual(box.currentValue, 7)
    }

    func testRuntimeVetoableBoxStoresCallbackPointer() {
        let ptr = 67890
        let box = RuntimeVetoableBox(initialValue: 0, callbackFnPtr: ptr)
        XCTAssertEqual(box.callbackFnPtr, ptr)
    }

    func testRuntimeVetoableBoxCurrentValueIsMutable() {
        let box = RuntimeVetoableBox(initialValue: 0, callbackFnPtr: 0)
        box.currentValue = 55
        XCTAssertEqual(box.currentValue, 55)
    }
}
