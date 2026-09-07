#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendNumericBoundariesTests {

    @Test
    func testNumericBoundaryUnsignedCompanionConstants() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE)
            println(UInt.MIN_VALUE)
            println(UInt.SIZE_BITS)
            println(UInt.SIZE_BYTES)
            println(ULong.MAX_VALUE)
            println(ULong.MIN_VALUE)
            println(ULong.SIZE_BITS)
            println(ULong.SIZE_BYTES)
            println(UByte.MAX_VALUE)
            println(UByte.MIN_VALUE)
            println(UByte.SIZE_BITS)
            println(UByte.SIZE_BYTES)
            println(UShort.MAX_VALUE)
            println(UShort.MIN_VALUE)
            println(UShort.SIZE_BITS)
            println(UShort.SIZE_BYTES)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUnsignedConstants",
            expected: """
            4294967295
            0
            32
            4
            18446744073709551615
            0
            64
            8
            255
            0
            8
            1
            65535
            0
            16
            2
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryUIntCompanionSourceBacked() throws {
        let source = """
        fun main() {
            val directMax: UInt = UInt.MAX_VALUE
            val directMin: UInt = UInt.MIN_VALUE
            val receiverMax: UInt = UInt.Companion.MAX_VALUE
            val receiverMin: UInt = UInt.Companion.MIN_VALUE
            println(directMax)
            println(directMin)
            println(receiverMax)
            println(receiverMin)
            println(UInt.MAX_VALUE + 1u)
            println(UInt.MIN_VALUE - 1u)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUIntCompanionSourceBacked",
            expected: """
            4294967295
            0
            4294967295
            0
            0
            4294967295
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryConversionTruncation() throws {
        let source = """
        fun main() {
            println(200.toByte())
            println(255.toByte())
            println(256.toByte())
            println(1000.toByte())
            println(40000.toShort())
            println(70000.toShort())
            println(65536.toShort())
            println(4294967296L.toInt())
            println(4294967297L.toInt())
            println(Long.MAX_VALUE.toInt())
            println(Long.MIN_VALUE.toInt())
            println((-1).toLong())
            println(Int.MIN_VALUE.toLong())
            val b: Byte = -1
            println(b.toInt())
            val s: Short = -1
            println(s.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryConversionTruncation",
            expected: """
            -56
            -1
            0
            -24
            -25536
            4464
            0
            0
            1
            -1
            0
            -1
            -2147483648
            -1
            -1
            """ + "\n"
        )
    }

    @Test
    func testCharNumericConversionsPreserveCodeUnitSemantics() throws {
        let source = """
        fun main() {
            val high = '\\uD800'
            val max = '\\uFFFF'
            println(high.toByte())
            println(high.toShort())
            println(high.toInt())
            println(high.toLong())
            println(max.code)
            println(max.code.toUInt())
            println(max.code.toULong())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CharNumericConversionCodeUnits",
            expected: """
            0
            -10240
            55296
            55296
            65535
            65535
            65535
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryFloatToInt() throws {
        let source = """
        fun main() {
            println(Double.NaN.toInt())
            println(Double.POSITIVE_INFINITY.toInt())
            println(Double.NEGATIVE_INFINITY.toInt())
            println(1e20.toInt())
            println((-1e20).toInt())
            println(3.99.toInt())
            println((-3.99).toInt())
            println(Double.NaN.toLong())
            println(Double.POSITIVE_INFINITY.toLong())
            println(Double.NEGATIVE_INFINITY.toLong())
            println(1e30.toLong())
            println((-1e30).toLong())
            println(Float.NaN.toInt())
            println(Float.POSITIVE_INFINITY.toInt())
            println(1e20f.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryFloatToInt",
            expected: """
            0
            2147483647
            -2147483648
            2147483647
            -2147483648
            3
            -3
            0
            9223372036854775807
            -9223372036854775808
            9223372036854775807
            -9223372036854775808
            0
            2147483647
            2147483647
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryFloatDoubleBundledConversions() throws {
        let source = """
        fun main() {
            println(Double.NaN.toInt())
            println(Double.POSITIVE_INFINITY.toLong())
            println((-0.5).toInt())
            println(Float.NaN.toInt())
            println(Float.POSITIVE_INFINITY.toLong())
            println(3.99f.toDouble())
            println(65536.0.toChar().code)
            println(65536.0f.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryFloatDoubleBundledConversions",
            expected: """
            0
            9223372036854775807
            0
            0
            9223372036854775807
            3.990000009536743
            0
            0
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryUIntArithmeticWraps() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE + 1u)
            println(0u - 1u)
            println(UInt.MAX_VALUE * 2u)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUIntOverflow",
            expected: """
            0
            4294967295
            4294967294
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryUnsignedNarrowingConversions() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE.toByte())
            println(UInt.MAX_VALUE.toShort())
            println(ULong.MAX_VALUE.toByte())
            println(ULong.MAX_VALUE.toShort())
            println(UByte.MAX_VALUE.toByte())
            println(UByte.MAX_VALUE.toShort())
            println(UShort.MAX_VALUE.toByte())
            println(UShort.MAX_VALUE.toShort())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUnsignedNarrowingConversions",
            expected: """
            -1
            -1
            -1
            -1
            -1
            255
            -1
            -1
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundarySignedUnsignedReinterpretation() throws {
        // Regression for kk_int_to_uint / kk_long_to_uint / kk_uint_to_int /
        // kk_ulong_to_int: these used to be identity functions, so a negative
        // signed source (or an unsigned source >= 2^31) kept its original
        // Int64 payload instead of reinterpreting bits for the target type.
        let source = """
        fun main() {
            val n: Long = -1L
            println(n.toUInt())
            println(n.toUInt() == 4294967295u)
            println((-1).toUInt())
            println((-1).toLong().toUInt())
            println((n and 0xffffffffL).toInt().toUInt())
            println(4294967295u.toInt())
            println(2147483648u.toInt())
            println(4294967296uL.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundarySignedUnsignedReinterpretation",
            expected: """
            4294967295
            true
            4294967295
            4294967295
            4294967295
            -1
            -2147483648
            0
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryIntToCharTruncates() throws {
        let source = """
        fun main() {
            println(65601.toChar().code)
            println(70000.toChar().code)
            println(65536.toChar().code)
            println(131072.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryIntToChar",
            expected: """
            65
            4464
            0
            0
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryIntSourceBackedConversions() throws {
        let source = """
        fun main() {
            val value: Int = 16777217
            println(value.toDouble() == 16777217.0)
            println(value.toChar().code)
            println((-1).toUInt())
            println(Int.MIN_VALUE.toShort())
            val nullable: Int? = value
            println(nullable?.toDouble())
            println(nullable?.toChar()?.code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryIntSourceBackedConversions",
            expected: """
            true
            1
            4294967295
            0
            1.6777217E7
            1
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryLongSourceBackedCharAndConversions() throws {
        let source = """
        @Suppress("DEPRECATION")
        fun main() {
            println(Long.MAX_VALUE.toDouble())
            println(Long.MAX_VALUE.toInt())
            println(Long.MIN_VALUE.toInt())
            println(Long.MAX_VALUE.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryLongSourceBackedConversions",
            expected: """
            9.223372036854776E18
            -1
            0
            65535
            """ + "\n"
        )
    }

    @Test
    func testNumericBoundaryCharArithmeticBasics() throws {
        let source = """
        fun main() {
            println('A'.code)
            println('0'.code)
            println('Z' + 1)
            println('B' - 1)
            println('Z' - 'A')
            println('9' - '0')
            println(65.toChar())
            println(65.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryCharArithmeticBasics",
            expected: """
            65
            48
            [
            A
            25
            9
            A
            65
            """ + "\n"
        )
    }
}
#endif
