#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1089: verify both source-backed overloads preserve zero initialization
/// and copy the IntArray storage before residual atomic operations use it.
@Suite
struct AtomicIntArraySourceMigrationCodegenTests {
    @Test
    func testAtomicIntArrayConstructorsPreserveAllocationAndCopySemantics() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicIntArray

        fun main() {
            val zeros = AtomicIntArray(3)
            println(zeros.size)
            println(zeros[0])

            val source = intArrayOf(4, 5, 6)
            val copied = AtomicIntArray(source)
            source[0] = 99
            println(copied[0])
            println(copied[1])
            println(copied[2])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AtomicIntArraySourceConstructors",
            expected: "3\n0\n4\n5\n6\n",
            // Compile bundled sources so this test exercises the new overloads
            // instead of the prebuilt stdlib artifact.
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
