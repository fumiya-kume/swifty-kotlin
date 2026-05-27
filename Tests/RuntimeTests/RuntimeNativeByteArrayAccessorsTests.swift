@testable import Runtime
import XCTest

final class RuntimeNativeByteArrayAccessorsTests: XCTestCase {
    private func makeByteArray(_ bytes: [Int]) -> Int {
        let array = kk_array_new(bytes.count)
        for (index, byte) in bytes.enumerated() {
            _ = kk_array_set(array, index, byte, nil)
        }
        return array
    }

    func testSignedByteArrayLoadsUseLittleEndianLayout() {
        let array = makeByteArray([0x80, 0xFF, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12])

        XCTAssertEqual(kk_native_byteArray_getByteAt(array, 0), -128)
        XCTAssertEqual(kk_native_byteArray_getShortAt(array, 0), -128)
        XCTAssertEqual(kk_native_byteArray_getShortAt(array, 2), 0x1234)
        XCTAssertEqual(kk_native_byteArray_getIntAt(array, 4), 0x12345678)
    }

    func testSignedLongByteArrayLoad() {
        let positive = makeByteArray([0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
        let negative = makeByteArray([0, 0, 0, 0, 0, 0, 0, 0x80])

        XCTAssertEqual(kk_native_byteArray_getLongAt(positive, 0), 0x1122334455667788)
        XCTAssertEqual(kk_native_byteArray_getLongAt(negative, 0), Int.min)
    }
}
