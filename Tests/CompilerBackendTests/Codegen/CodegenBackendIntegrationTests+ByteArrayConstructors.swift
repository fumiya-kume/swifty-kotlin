#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendByteArrayConstructorTests {
    @Test
    func testByteArrayConstructorsExecuteWithKotlinSemantics() throws {
        let source = """
        fun main() {
            val sized = ByteArray(3)
            println(sized.size)
            println(sized[0])

            val initialized = ByteArray(4) { (it + 1).toByte() }
            println(initialized.size)
            println(initialized[0])
            println(initialized[3])
            println(ByteArray(0) { 42 }.size)

            try {
                ByteArray(-1) { 0.toByte() }
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("negative")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ByteArrayConstructors",
            expected: "3\n0\n4\n1\n4\n0\nnegative\n"
        )
    }
}
#endif
