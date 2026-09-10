#if canImport(Testing)
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendDataClassHashCodeTests {
    @Test
    func testDataClassNumericHashCodeMatchesKotlinThroughDirectAndAnyCalls() throws {
        let source = """
        data class LongHolder(val x: Long)
        data class FloatHolder(val x: Float)
        data class DoubleHolder(val x: Double)
        data class ULongHolder(val x: ULong)

        fun main() {
            val longHolder = LongHolder(1L shl 40)
            val floatHolder = FloatHolder(-2.5f)
            val doubleHolder = DoubleHolder(-2.5)
            val ulongHolder = ULongHolder(1uL shl 40)

            println(longHolder.hashCode())
            val anyLong: Any = longHolder
            println(anyLong.hashCode())

            println(floatHolder.hashCode())
            val anyFloat: Any = floatHolder
            println(anyFloat.hashCode())

            println(doubleHolder.hashCode())
            val anyDouble: Any = doubleHolder
            println(anyDouble.hashCode())

            println(ulongHolder.hashCode())
            val anyULong: Any = ulongHolder
            println(anyULong.hashCode())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DataClassNumericHashCode",
            expected: """
            256
            256
            -1071644672
            -1071644672
            -1073479680
            -1073479680
            256
            256
            """ + "\n"
        )
    }
}
#endif
