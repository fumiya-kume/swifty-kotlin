@testable import Runtime
import XCTest

final class RuntimeNativeUnsignedByteArrayAccessorsTests: XCTestCase {
    private func makeByteArray(_ bytes: [Int]) -> Int {
        let array = kk_array_new(bytes.count)
        for (index, byte) in bytes.enumerated() {
            _ = kk_array_set(array, index, byte, nil)
        }
        return array
    }

    func testUnsignedByteArrayLoadsUseLittleEndianLayout() {
        let array = makeByteArray([0xFF, 0x80, 0x34, 0x12, 0x21, 0x43, 0x65, 0x87])

        XCTAssertEqual(kk_native_byteArray_getUByteAt(array, 0), 0xFF)
        XCTAssertEqual(kk_native_byteArray_getUShortAt(array, 1), 0x3480)
        XCTAssertEqual(kk_native_byteArray_getUIntAt(array, 4), 0x87654321)
    }

    func testUnsignedLongByteArrayLoadPreservesBitPattern() {
        let max = makeByteArray(Array(repeating: 0xFF, count: 8))

        XCTAssertEqual(kk_native_byteArray_getULongAt(max, 0), -1)
    }
}
