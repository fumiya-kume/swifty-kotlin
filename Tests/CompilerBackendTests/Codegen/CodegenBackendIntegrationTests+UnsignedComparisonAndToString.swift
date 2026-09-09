#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression coverage for a ULong sign-misinterpretation bug found while
/// working on KSP-466 (kotlin.random.Random.nextULong()): any ULong with the
/// high bit set (>= 2^63) was compared and stringified as if it were a
/// signed Int64, e.g. `17663719463477156090uL >= 0uL` returned `false` and
/// `.toString()` printed the negative signed reinterpretation (or, at the
/// 2^63 boundary, the literal string "null"). UInt does not exhibit the bug
/// because it is always zero-extended into the shared 64-bit container.

@Suite
struct CodegenBackendUnsignedComparisonAndToStringTests {

    @Test
    func testUnsignedComparisonHighBitSetULong() throws {
        let source = """
        fun main() {
            val small: ULong = 5uL
            val big: ULong = 17663719463477156090uL
            println(small >= 0uL)
            println(big >= 0uL)
            println(big > small)
            println(big >= small)
            println(small < big)
            println(small <= big)
            println(big < small)
            println(big <= small)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonHighBitSetULong",
            expected: """
            true
            true
            true
            true
            true
            true
            false
            false
            """ + "\n"
        )
    }

    @Test
    func testUnsignedCompareHelperBothHighBits() throws {
        let source = """
        package kotlin

        fun main() {
            println(ulongCompare(Long.MIN_VALUE, -1L))
            println(ulongCompare(-1L, Long.MIN_VALUE))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedCompareHelperBothHighBits",
            expected: """
            -1
            1
            """ + "\n"
        )
    }

    @Test
    func testUnsignedComparisonULongMaxValueBoundary() throws {
        let source = """
        fun main() {
            println(ULong.MAX_VALUE >= 0uL)
            println(ULong.MAX_VALUE > 0uL)
            println(0uL < ULong.MAX_VALUE)
            println(ULong.MAX_VALUE >= ULong.MAX_VALUE)
            println(ULong.MAX_VALUE <= ULong.MAX_VALUE)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonULongMaxValueBoundary",
            expected: """
            true
            true
            true
            true
            true
            """ + "\n"
        )
    }

    @Test
    func testUnsignedToStringHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big.toString())
            println(ULong.MAX_VALUE.toString())
            // 2^63 shares its raw bit pattern with the compiler's null
            // sentinel (Int.min); toString() must still render the real
            // unsigned value rather than the literal string "null".
            val boundary: ULong = 9223372036854775808uL
            println(boundary.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedToStringHighBitSetULong",
            expected: """
            17663719463477156090
            18446744073709551615
            9223372036854775808
            """ + "\n"
        )
    }

    @Test
    func testUnsignedStringTemplateHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println("value=$big")
            println("concat=" + big)

            val nullableBig: ULong? = big
            println("nullable=$nullableBig")
            val nullableNone: ULong? = null
            println("isNull=$nullableNone")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedStringTemplateHighBitSetULong",
            expected: """
            value=17663719463477156090
            concat=17663719463477156090
            nullable=17663719463477156090
            isNull=null
            """ + "\n"
        )
    }

    @Test
    func testUnsignedComparisonAndToStringUIntUnaffected() throws {
        // UInt is zero-extended into the shared 64-bit container, so it never
        // exhibited this bug — this test locks in that the fix leaves it correct.
        let source = """
        fun main() {
            val small: UInt = 5u
            val big: UInt = UInt.MAX_VALUE
            println(small >= 0u)
            println(big >= 0u)
            println(big > small)
            println(big.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonAndToStringUIntUnaffected",
            expected: """
            true
            true
            true
            4294967295
            """ + "\n"
        )
    }

    // The ULong tag fix above was implemented by consolidating a duplicated
    // tag-computation switch (computeAnyFallbackTag) that data class
    // toString() synthesis and println(dataClass) rewriting each had their
    // own incomplete copy of — the old copies only mapped Boolean/String and
    // fell back to the raw-integer tag for everything else, so Float/Double
    // properties printed their bit pattern and Char properties printed their
    // codepoint instead of the character. Consolidating onto one function
    // fixes those too; lock in that non-null case here.
    @Test
    func testDataClassToStringFloatDoubleCharProperties() throws {
        let source = """
        data class Point(val x: Float, val y: Double, val label: Char)
        fun main() {
            val p = Point(1.5f, 2.75, 'A')
            println(p.toString())
            println(p)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringFloatDoubleCharProperties",
            expected: """
            Point(x=1.5, y=2.75, label=A)
            Point(x=1.5, y=2.75, label=A)
            """ + "\n"
        )
    }

    // Nullable Float?/Double?/Char? properties: a real value renders correctly
    // (not the boxed pointer or raw bit pattern) and a genuinely null value
    // renders as "null" (not a garbage value), through both the toString()
    // synthesis path (which added a KIR-level null guard) and the
    // println(dataClass) path (which uses kk_any_to_string_nullable instead,
    // since that pass cannot safely add new KIR labels).
    @Test
    func testDataClassToStringNullableFloatDoubleCharProperties() throws {
        let source = """
        data class NullablePoint(val x: Float?, val y: Double?, val label: Char?)
        fun main() {
            val real = NullablePoint(1.5f, 2.75, 'A')
            println(real.toString())
            println(real)

            val allNull = NullablePoint(null, null, null)
            println(allNull.toString())
            println(allNull)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringNullableFloatDoubleCharProperties",
            expected: """
            NullablePoint(x=1.5, y=2.75, label=A)
            NullablePoint(x=1.5, y=2.75, label=A)
            NullablePoint(x=null, y=null, label=null)
            NullablePoint(x=null, y=null, label=null)
            """ + "\n"
        )
    }
}
#endif
