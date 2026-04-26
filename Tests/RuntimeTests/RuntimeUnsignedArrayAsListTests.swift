import Foundation
@testable import Runtime
import XCTest

final class RuntimeUnsignedArrayAsListTests: IsolatedRuntimeXCTestCase {
    private func makeRuntimeArray(_ elements: [Int]) -> Int {
        let box = RuntimeArrayBox(length: elements.count)
        box.elements = elements
        return registerRuntimeObject(box)
    }

    private func listElements(from raw: Int) -> [Int] {
        runtimeListBox(from: raw)?.elements ?? []
    }

    private func arrayElements(from raw: Int) -> [Int] {
        runtimeArrayBox(from: raw)?.elements ?? []
    }

    func testUnsignedPrimitiveArrayCopyOfRangeCopiesElements() {
        let ubyteRaw = makeRuntimeArray([1, 2, 3, 4])
        XCTAssertEqual(arrayElements(from: kk_array_copyOfRange(ubyteRaw, 1, 3)), [2, 3])

        let ushortRaw = makeRuntimeArray([10, 20, 30, 40])
        XCTAssertEqual(arrayElements(from: kk_array_copyOfRange(ushortRaw, 0, 2)), [10, 20])

        let uintRaw = makeRuntimeArray([100, 200, 300])
        XCTAssertEqual(arrayElements(from: kk_array_copyOfRange(uintRaw, 1, 3)), [200, 300])

        let ulongRaw = makeRuntimeArray([1000, 2000, 3000])
        XCTAssertEqual(arrayElements(from: kk_array_copyOfRange(ulongRaw, 0, 1)), [1000])
    }

    func testUnsignedPrimitiveArraySignedViewsShareBackingStorage() {
        let ubyteRaw = makeRuntimeArray([1, 2])
        let byteRaw = kk_uByteArray_asByteArray(ubyteRaw)
        XCTAssertEqual(byteRaw, ubyteRaw)
        runtimeArrayBox(from: byteRaw)?.elements[1] = 127
        XCTAssertEqual(arrayElements(from: ubyteRaw), [1, 127])

        let ushortRaw = makeRuntimeArray([10, 20])
        let shortRaw = kk_uShortArray_asShortArray(ushortRaw)
        XCTAssertEqual(shortRaw, ushortRaw)
        runtimeArrayBox(from: shortRaw)?.elements[0] = 32_767
        XCTAssertEqual(arrayElements(from: ushortRaw), [32_767, 20])

        let uintRaw = makeRuntimeArray([100, 200])
        let intRaw = kk_uIntArray_asIntArray(uintRaw)
        XCTAssertEqual(intRaw, uintRaw)
        runtimeArrayBox(from: intRaw)?.elements[1] = 900
        XCTAssertEqual(arrayElements(from: uintRaw), [100, 900])

        let ulongRaw = makeRuntimeArray([1000, 2000])
        let longRaw = kk_uLongArray_asLongArray(ulongRaw)
        XCTAssertEqual(longRaw, ulongRaw)
        runtimeArrayBox(from: longRaw)?.elements[0] = 9_000
        XCTAssertEqual(arrayElements(from: ulongRaw), [9_000, 2000])
    }

    func testUByteArrayAsListViewReflectsMutations() {
        let arrayRaw = makeRuntimeArray([1, 2, 3])
        let listRaw = kk_uByteArray_asList(arrayRaw)

        XCTAssertEqual(listElements(from: listRaw), [1, 2, 3])

        guard let arrayBox = runtimeArrayBox(from: arrayRaw) else {
            XCTFail("Expected a runtime array box.")
            return
        }
        arrayBox.elements[1] = 9

        XCTAssertEqual(listElements(from: listRaw), [1, 9, 3])
    }

    func testUShortArrayAsListViewReflectsMutations() {
        let arrayRaw = makeRuntimeArray([10, 20, 30])
        let listRaw = kk_uShortArray_asList(arrayRaw)

        XCTAssertEqual(listElements(from: listRaw), [10, 20, 30])

        guard let arrayBox = runtimeArrayBox(from: arrayRaw) else {
            XCTFail("Expected a runtime array box.")
            return
        }
        arrayBox.elements[1] = 90

        XCTAssertEqual(listElements(from: listRaw), [10, 90, 30])
    }

    func testULongArrayAsListViewReflectsMutations() {
        let arrayRaw = makeRuntimeArray([1000, 2000, 3000])
        let listRaw = kk_uLongArray_asList(arrayRaw)

        XCTAssertEqual(listElements(from: listRaw), [1000, 2000, 3000])

        guard let arrayBox = runtimeArrayBox(from: arrayRaw) else {
            XCTFail("Expected a runtime array box.")
            return
        }
        arrayBox.elements[1] = 9000

        XCTAssertEqual(listElements(from: listRaw), [1000, 9000, 3000])
    }

    func testUnsignedPrimitiveArrayToTypedArrayCopiesElements() {
        let ubyteRaw = makeRuntimeArray([1, 2, 3])
        let ubyteCopy = kk_array_copyOf(ubyteRaw)
        XCTAssertNotEqual(ubyteCopy, ubyteRaw)
        XCTAssertEqual(arrayElements(from: ubyteCopy), [1, 2, 3])

        let ushortRaw = makeRuntimeArray([10, 20, 30])
        let ushortCopy = kk_array_copyOf(ushortRaw)
        XCTAssertNotEqual(ushortCopy, ushortRaw)
        XCTAssertEqual(arrayElements(from: ushortCopy), [10, 20, 30])

        let uintRaw = makeRuntimeArray([100, 200])
        let uintCopy = kk_array_copyOf(uintRaw)
        runtimeArrayBox(from: uintCopy)?.elements[1] = 900
        XCTAssertEqual(arrayElements(from: uintRaw), [100, 200])
        XCTAssertEqual(arrayElements(from: uintCopy), [100, 900])

        let ulongRaw = makeRuntimeArray([1000, 2000])
        let ulongCopy = kk_array_copyOf(ulongRaw)
        runtimeArrayBox(from: ulongCopy)?.elements[0] = 9000
        XCTAssertEqual(arrayElements(from: ulongRaw), [1000, 2000])
        XCTAssertEqual(arrayElements(from: ulongCopy), [9000, 2000])
    }
}
