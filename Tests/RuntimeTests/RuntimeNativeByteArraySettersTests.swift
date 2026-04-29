@testable import Runtime
import XCTest

final class RuntimeNativeByteArraySettersTests: IsolatedRuntimeXCTestCase {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    func testSignedByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 8)

        XCTAssertEqual(kk_native_byteArray_setByteAt(array, 0, -1), 0)
        XCTAssertEqual(kk_native_byteArray_getByteAt(array, 0), -1)
        XCTAssertEqual(kk_native_byteArray_getUByteAt(array, 0), 0xFF)

        XCTAssertEqual(kk_native_byteArray_setShortAt(array, 0, 0x1234), 0)
        XCTAssertEqual(kk_native_byteArray_getShortAt(array, 0), 0x1234)
        XCTAssertEqual(kk_array_get(array, 0, nil), 0x34)
        XCTAssertEqual(kk_array_get(array, 1, nil), 0x12)

        XCTAssertEqual(kk_native_byteArray_setIntAt(array, 0, 0x12345678), 0)
        XCTAssertEqual(kk_native_byteArray_getIntAt(array, 0), 0x12345678)

        XCTAssertEqual(kk_native_byteArray_setLongAt(array, 0, 0x1122334455667788), 0)
        XCTAssertEqual(kk_native_byteArray_getLongAt(array, 0), 0x1122334455667788)
    }

    func testSignedLongByteArrayStorePreservesBitPattern() {
        let array = makeByteArray(length: 8)

        XCTAssertEqual(kk_native_byteArray_setLongAt(array, 0, Int.min), 0)
        XCTAssertEqual(kk_native_byteArray_getLongAt(array, 0), Int.min)
    }
}
