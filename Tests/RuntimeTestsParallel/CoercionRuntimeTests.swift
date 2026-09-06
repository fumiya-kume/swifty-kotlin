#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct CoercionRuntimeTests {

    // MARK: - Helpers

    private func doubleToBits(_ value: Double) -> Int { kk_double_to_bits(value) }
    private func floatToBits(_ value: Float) -> Int { kk_float_to_bits(value) }
    private func bitsToDouble(_ bits: Int) -> Double { kk_bits_to_double(bits) }
    private func bitsToFloat(_ bits: Int) -> Float { kk_bits_to_float(bits) }

    // MARK: - Precision Tests

    @Test
    func testFloatToDoublePrecision() {
        let preciseDouble = 1.23456789012345
        let doubleBits = doubleToBits(preciseDouble)
        let floatBits = kk_double_to_float(doubleBits)
        let convertedBackBits = __kk_float_to_double_bits(floatBits)
        let convertedBack = bitsToDouble(convertedBackBits)

        #expect(abs(convertedBack - preciseDouble) > 1e-15)
        #expect(abs(convertedBack - preciseDouble) <= 1e-7)
    }

    @Test
    func testTypeConversionConsistency() {
        let testDouble = 3.141592653589793
        let bits = doubleToBits(testDouble)
        let decoded = bitsToDouble(bits)
        #expect(abs(decoded - testDouble) <= 1e-15)

        let testFloat: Float = 3.1415927
        let floatBits = floatToBits(testFloat)
        let decodedFloat = bitsToFloat(floatBits)
        #expect(abs(decodedFloat - testFloat) <= 1e-7)
    }

    // MARK: - UByte and UShort Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testIntToUByteConversion() {
        #expect(kk_int_to_ubyte(100) == 100)
        #expect(kk_int_to_ubyte(-5) == 251)
        #expect(kk_int_to_ubyte(300) == 44)
        #expect(kk_int_to_ubyte(0) == 0)
        #expect(kk_int_to_ubyte(255) == 255)
    }

    @Test
    func testIntToUShortConversion() {
        #expect(kk_int_to_ushort(1000) == 1000)
        #expect(kk_int_to_ushort(-5) == 65531)
        #expect(kk_int_to_ushort(70000) == 4464)
        #expect(kk_int_to_ushort(0) == 0)
        #expect(kk_int_to_ushort(65535) == 65535)
    }

    @Test
    func testLongToUByteConversion() {
        #expect(kk_long_to_ubyte(100) == 100)
        #expect(kk_long_to_ubyte(-5) == 251)
        #expect(kk_long_to_ubyte(300) == 44)
    }

    @Test
    func testLongToUShortConversion() {
        #expect(kk_long_to_ushort(1000) == 1000)
        #expect(kk_long_to_ushort(-5) == 65531)
        #expect(kk_long_to_ushort(70000) == 4464)
    }

    @Test
    func testUIntToUByteConversion() {
        #expect(kk_uint_to_ubyte(100) == 100)
        #expect(kk_uint_to_ubyte(300) == 44)
        #expect(kk_uint_to_ubyte(0) == 0)
        #expect(kk_uint_to_ubyte(255) == 255)
    }

    // MARK: - Int/UInt 32-bit Reinterpretation Regression Tests
    //
    // kk_int_to_uint / kk_long_to_uint / kk_uint_to_int / kk_ulong_to_int used
    // to be identity functions. That happened to look right whenever the
    // source payload was already a non-negative value the target type could
    // hold as-is, but it left the Int64 payload numerically unchanged for any
    // value that needed an actual bit-pattern reinterpretation, silently
    // producing a wrong (still-negative, or out-of-range) result. Found via
    // `(-1L).toUInt()` while working on HexFormat (KSP-481).

    @Test
    func testIntToUIntConversion() {
        // Negative Int must reinterpret its bit pattern as unsigned, not
        // stay negative.
        #expect(kk_int_to_uint(-1) == Int(UInt32.max))
        #expect(kk_int_to_uint(Int(Int32.min)) == Int(UInt32(Int32.max) + 1))
        #expect(kk_int_to_uint(100) == 100)
        #expect(kk_int_to_uint(0) == 0)
    }

    @Test
    func testLongToUIntConversion() {
        // Narrowing Long -> UInt keeps only the low 32 bits, then reads them
        // as unsigned.
        #expect(kk_long_to_uint(-1) == Int(UInt32.max))
        #expect(kk_long_to_uint(100) == 100)
        // 0x1_0000_0001 truncates to 0x0000_0001.
        #expect(kk_long_to_uint(4294967297) == 1)
    }

    @Test
    func testUIntToIntConversion() {
        // UInt values at or above 2^31 must reinterpret as negative Int.
        #expect(kk_uint_to_int(Int(UInt32.max)) == -1)
        #expect(kk_uint_to_int(2147483648) == Int(Int32.min))
        #expect(kk_uint_to_int(100) == 100)
    }

    @Test
    func testULongToIntConversion() {
        // Narrowing ULong -> Int keeps only the low 32 bits, then reads them
        // as signed.
        #expect(kk_ulong_to_int(Int(UInt32.max)) == -1)
        #expect(kk_ulong_to_int(100) == 100)
        // 2^32 truncates to 0.
        #expect(kk_ulong_to_int(4294967296) == 0)
    }

    @Test
    func testUIntIntRoundTripRegression() {
        // (-1L).toUInt() == 4294967295u must hold both as a value and in
        // equality — this was returning -1 (and comparing false) before the
        // fix.
        #expect(kk_long_to_uint(-1) == kk_int_to_uint(-1))
        #expect(kk_uint_to_int(kk_int_to_uint(-1)) == -1)
    }

    @Test
    func testUIntToUShortConversion() {
        #expect(kk_uint_to_ushort(1000) == 1000)
        #expect(kk_uint_to_ushort(70000) == 4464)
        #expect(kk_uint_to_ushort(0) == 0)
        #expect(kk_uint_to_ushort(65535) == 65535)
    }

    @Test
    func testUByteToIntConversion() {
        #expect(kk_ubyte_to_int(100) == 100)
        #expect(kk_ubyte_to_int(0) == 0)
        #expect(kk_ubyte_to_int(255) == 255)
    }

    @Test
    func testUShortToIntConversion() {
        #expect(kk_ushort_to_int(1000) == 1000)
        #expect(kk_ushort_to_int(0) == 0)
        #expect(kk_ushort_to_int(65535) == 65535)
    }

    @Test
    func testUByteToLongConversion() {
        #expect(kk_ubyte_to_long(100) == 100)
        #expect(kk_ubyte_to_long(0) == 0)
        #expect(kk_ubyte_to_long(255) == 255)
    }

    @Test
    func testUShortToLongConversion() {
        #expect(kk_ushort_to_long(1000) == 1000)
        #expect(kk_ushort_to_long(0) == 0)
        #expect(kk_ushort_to_long(65535) == 65535)
    }

    // MARK: - Char Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testIntToCharConversion() {
        #expect(kk_int_to_char(65) == 65)
        #expect(kk_int_to_char(0x1F600) == 0xF600)
        #expect(kk_int_to_char(-5) == 0xFFFB)
        #expect(kk_int_to_char(0x110000) == 0)
        #expect(kk_int_to_char(0) == 0)
        #expect(kk_int_to_char(0x10FFFF) == 0xFFFF)
    }

    @Test
    func testUIntToCharConversion() {
        #expect(kk_uint_to_char(65) == 65)
        #expect(kk_uint_to_char(0x1F600) == 0xF600)
        #expect(kk_uint_to_char(0x110000) == 0)
    }

    @Test
    func testULongToCharConversion() {
        #expect(kk_ulong_to_char(65) == 65)
        #expect(kk_ulong_to_char(0x1F600) == 0xF600)
        #expect(kk_ulong_to_char(0x110000) == 0)
    }

    @Test
    func testUByteToCharConversion() {
        #expect(kk_ubyte_to_char(65) == 65)
        #expect(kk_ubyte_to_char(255) == 255)
    }

    @Test
    func testUShortToCharConversion() {
        #expect(kk_ushort_to_char(65) == 65)
        #expect(kk_ushort_to_char(0x1F600) == 0x1F600)
        #expect(kk_ushort_to_char(65535) == 65535)
    }

    // MARK: - Additional Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testByteToUIntConversion() {
        #expect(kk_byte_to_uint(100) == 100)
        #expect(kk_byte_to_uint(-5) == 251)
    }

    @Test
    func testShortToUIntConversion() {
        #expect(kk_short_to_uint(1000) == 1000)
        #expect(kk_short_to_uint(-5) == 65531)
    }

    @Test
    func testByteToULongConversion() {
        #expect(kk_byte_to_ulong(100) == 100)
        #expect(kk_byte_to_ulong(-5) == 251)
    }

    @Test
    func testShortToULongConversion() {
        #expect(kk_short_to_ulong(1000) == 1000)
        #expect(kk_short_to_ulong(-5) == 65531)
    }

    @Test
    func testByteToCharConversion() {
        #expect(kk_byte_to_char(65) == 65)
        #expect(kk_byte_to_char(-5) == 0xFFFB)
    }

    @Test
    func testShortToCharConversion() {
        #expect(kk_short_to_char(65) == 65)
        #expect(kk_short_to_char(0x1F600) == 0xF600)
    }

    // MARK: - Cross-Type Conversion Tests

    @Test
    func testCrossTypeUByteConversions() {
        let original = 200
        let asUByte = kk_int_to_ubyte(original)
        let backToInt = kk_ubyte_to_int(asUByte)
        let asLong = kk_ubyte_to_long(asUByte)
        let asUInt = kk_ubyte_to_uint(asUByte)
        let asULong = kk_ubyte_to_ulong(asUByte)
        let asChar = kk_ubyte_to_char(asUByte)

        #expect(backToInt == original)
        #expect(asLong == original)
        #expect(asUInt == original)
        #expect(asULong == original)
        #expect(asChar == original)
    }

    @Test
    func testCrossTypeUShortConversions() {
        let original = 50000
        let asUShort = kk_int_to_ushort(original)
        let backToInt = kk_ushort_to_int(asUShort)
        let asLong = kk_ushort_to_long(asUShort)
        let asUInt = kk_ushort_to_uint(asUShort)
        let asULong = kk_ushort_to_ulong(asUShort)
        let asChar = kk_ushort_to_char(asUShort)

        #expect(backToInt == original)
        #expect(asLong == original)
        #expect(asUInt == original)
        #expect(asULong == original)
        #expect(asChar == original)
    }

}
#endif
