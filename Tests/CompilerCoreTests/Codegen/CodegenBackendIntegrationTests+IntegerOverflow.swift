@testable import CompilerCore
import Foundation
import XCTest

/// Behavioral parity tests for Kotlin's 32-bit `Int` arithmetic semantics.
///
/// Reference: Kotlin language spec / `kotlin.Int` API docs. `Int` is a 32-bit
/// signed integer whose arithmetic operators wrap around using two's
/// complement, and whose shift operators (`shl`, `shr`, `ushr`) use only the
/// low five bits of the shift distance. These tests compile and run real
/// programs and assert the documented results, guarding ``IntegerNarrowingPass``.
extension CodegenBackendIntegrationTests {
    private func assertProgramOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected, file: file, line: line)
        }
    }

    /// `Int` arithmetic overflows with two's-complement wraparound.
    func testCodegenIntArithmeticWrapsAt32Bits() throws {
        let source = """
        fun main() {
            println(Int.MAX_VALUE + 1)
            println(Int.MIN_VALUE - 1)
            println(Int.MAX_VALUE * 2)
            println(100000 * 100000)
            println(-Int.MIN_VALUE)
            println(Int.MIN_VALUE / -1)
            println(Int.MIN_VALUE % -1)
        }
        """
        try assertProgramOutput(
            source,
            moduleName: "IntOverflowArithmetic",
            expected: """
            -2147483648
            2147483647
            -2
            1410065408
            -2147483648
            -2147483648
            0
            """ + "\n"
        )
    }

    /// Overflow also holds when the operands are runtime values rather than
    /// compile-time constants (exercises the codegen path, not constant folding).
    func testCodegenIntArithmeticWrapsForRuntimeValues() throws {
        let source = """
        fun addOne(x: Int): Int = x + 1
        fun square(x: Int): Int = x * x
        fun negate(x: Int): Int = -x

        fun main() {
            println(addOne(Int.MAX_VALUE))
            println(square(100000))
            println(negate(Int.MIN_VALUE))
            var acc = 1
            for (i in 0 until 31) {
                acc *= 2
            }
            println(acc)
        }
        """
        try assertProgramOutput(
            source,
            moduleName: "IntOverflowRuntime",
            expected: """
            -2147483648
            1410065408
            -2147483648
            -2147483648
            """ + "\n"
        )
    }

    /// `Int` shift operators mask the shift distance to its low five bits and
    /// keep results within 32 bits.
    func testCodegenIntShiftSemantics() throws {
        let source = """
        fun main() {
            println(1 shl 31)
            println(1 shl 32)
            println(1 shl 33)
            println(-1 ushr 28)
            println(-1 ushr 0)
            println(-8 shr 1)
            println(256 shr 4)
            println(Int.MIN_VALUE shr 31)
            println(Int.MIN_VALUE ushr 31)
        }
        """
        try assertProgramOutput(
            source,
            moduleName: "IntShiftSemantics",
            expected: """
            -2147483648
            1
            2
            15
            -1
            -4
            16
            -1
            1
            """ + "\n"
        )
    }

    /// `Int` bitwise operators produce 32-bit results.
    func testCodegenIntBitwiseSemantics() throws {
        let source = """
        fun main() {
            println(0xFF and 0x0F)
            println(0xF0 or 0x0F)
            println(0b1010 xor 0b0110)
            println(0.inv())
            println(255.inv())
        }
        """
        try assertProgramOutput(
            source,
            moduleName: "IntBitwiseSemantics",
            expected: """
            15
            255
            12
            -1
            -256
            """ + "\n"
        )
    }

    /// Regression guard: `Long` arithmetic and shifts stay 64-bit and must not
    /// be narrowed by ``IntegerNarrowingPass``.
    func testCodegenLongArithmeticStays64Bit() throws {
        let source = """
        fun main() {
            println(2147483647L + 1L)
            println(1000000000L * 1000000000L)
            println(1L shl 40)
            println(Long.MAX_VALUE)
            val i = 2000000000
            val l = 3000000000L
            println(i + l)
        }
        """
        try assertProgramOutput(
            source,
            moduleName: "LongArithmetic64Bit",
            expected: """
            2147483648
            1000000000000000000
            1099511627776
            9223372036854775807
            5000000000
            """ + "\n"
        )
    }
}
