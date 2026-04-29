@testable import Runtime
import XCTest

final class RuntimeNativePrimitiveByteArraySettersTests: IsolatedRuntimeXCTestCase {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    func testPrimitiveByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 14)

        XCTAssertEqual(kk_native_byteArray_setCharAt(array, 0, 0x1234), 0)
        XCTAssertEqual(kk_native_byteArray_getCharAt(array, 0), 0x1234)
        XCTAssertEqual(kk_array_get(array, 0, nil), 0x34)
        XCTAssertEqual(kk_array_get(array, 1, nil), 0x12)

        XCTAssertEqual(kk_native_byteArray_setFloatAt(array, 2, kk_float_to_bits(Float(1.5))), 0)
        XCTAssertEqual(kk_native_byteArray_getFloatAt(array, 2), kk_float_to_bits(Float(1.5)))

        XCTAssertEqual(kk_native_byteArray_setDoubleAt(array, 6, kk_double_to_bits(-2.25)), 0)
        XCTAssertEqual(kk_native_byteArray_getDoubleAt(array, 6), kk_double_to_bits(-2.25))
    }
}
