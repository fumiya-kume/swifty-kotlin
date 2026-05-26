@testable import Runtime
import XCTest

final class RuntimeNativeUnsignedByteArraySettersTests: XCTestCase {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    func testUnsignedByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 8)

        XCTAssertEqual(kk_native_byteArray_setUByteAt(array, 0, 0xFF), 0)
        XCTAssertEqual(kk_native_byteArray_getUByteAt(array, 0), 0xFF)
        XCTAssertEqual(kk_native_byteArray_getByteAt(array, 0), -1)

        XCTAssertEqual(kk_native_byteArray_setUShortAt(array, 0, 0xABCD), 0)
        XCTAssertEqual(kk_native_byteArray_getUShortAt(array, 0), 0xABCD)

        XCTAssertEqual(kk_native_byteArray_setUIntAt(array, 0, 0x87654321), 0)
        XCTAssertEqual(kk_native_byteArray_getUIntAt(array, 0), 0x87654321)

        XCTAssertEqual(kk_native_byteArray_setULongAt(array, 0, 0x1122334455667788), 0)
        XCTAssertEqual(kk_native_byteArray_getULongAt(array, 0), 0x1122334455667788)
    }

    func testUnsignedLongByteArrayStorePreservesBitPattern() {
        let array = makeByteArray(length: 8)

        XCTAssertEqual(kk_native_byteArray_setULongAt(array, 0, -1), 0)
        XCTAssertEqual(kk_native_byteArray_getULongAt(array, 0), -1)
    }
}
