#if canImport(Testing)
@testable import CompilerBackend
import Testing

/// KSP-1195: BitSet's source-backed implementation reaches executable code without runtime bridges.
@Suite
struct CodegenBackendBitSetTests {
    @Test
    func testBitSetOperationsExecuteThroughBundledKotlinSource() throws {
        let source = """
        @file:OptIn(kotlin.native.ObsoleteNativeApi::class)

        import kotlin.native.BitSet

        fun main() {
            val bits = BitSet(2)
            bits.set(1)
            bits.set(2, 4)
            bits.flip(3..4)
            bits.flip(64)
            bits.set(130)
            bits.clear(64)
            println(bits.toString())
            println(bits.size)
            println(bits.lastTrueIndex)
            println(bits.nextSetBit())
            println(bits.nextClearBit())
            println(bits.previousSetBit(200))
            println(bits.previousClearBit(3))
            println(bits.previousBit(4, true))
            println(bits[130])
            println(bits.isEmpty)

            val mask = BitSet(131)
            mask.set(4)
            mask.set(130)
            bits.and(mask)
            val extra = BitSet(200)
            extra.set(150)
            bits.or(extra)
            bits.xor(extra)
            val remove = BitSet(131)
            remove.set(130)
            bits.andNot(remove)
            println(bits.toString())
            println(bits.intersects(remove))
            val same = BitSet(200)
            same.set(4)
            println(bits.equals(same))
            println(bits.hashCode() == same.hashCode())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BitSetOperations",
            expected: """
            [1|2|4|130]
            131
            130
            1
            0
            130
            3
            4
            true
            false
            [4]
            false
            true
            true
            """ + "\n"
        )
    }
}
#endif
