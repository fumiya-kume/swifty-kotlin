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
