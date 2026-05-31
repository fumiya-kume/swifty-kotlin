@testable import CompilerCore
import Foundation
import XCTest

// TEST-NUM-017: End-to-end parity tests for numeric boundary behavior, derived from
// kotlinc 2.3.10 diff cases (Scripts/diff_cases/*). These lock in the behaviors that
// already match Kotlin: narrowing conversions, float->int boundaries, Char arithmetic,
// and the unsigned companion constants added in this batch. The currently-divergent
// behaviors (32/64-bit integer overflow, shift masking, Int.toChar truncation) are
// tracked in TODO.md (TEST-NUM-017) and captured as KSWIFTK_DIFF_IGNORE diff cases.
extension CodegenBackendIntegrationTests {
    private func assertProgramStdout(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected)
        }
    }

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
        try assertProgramStdout(
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
        try assertProgramStdout(
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
        try assertProgramStdout(
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
        try assertProgramStdout(
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
