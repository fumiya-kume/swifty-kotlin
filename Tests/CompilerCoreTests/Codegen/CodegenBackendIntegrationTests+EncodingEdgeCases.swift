@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEncodingEdgeCases() throws {
        let source = """
        @OptIn(ExperimentalStdlibApi::class)
        fun main() {
            val original = "こんにちは"
            val encoded = original.encodeToByteArray()
            println(encoded.decodeToString())

            val ascii = "ABC".encodeToByteArray()
            println(String(ascii, Charsets.US_ASCII))

            val hex = 255.toHexString()
            println(hex)
            println(hex.hexToInt())
            println("ffff".hexToShort())
            println("ff".hexToUByte().toInt())
            println("ffffffff".hexToUInt())
            println("ffffffffffffffff".hexToULong())
            val ubytes = "00ff".hexToUByteArray()
            println(ubytes.size)
            println(ubytes[1])
            try {
                println("gg".hexToInt())
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EncodingEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                こんにちは
                ABC
                000000ff
                255
                -1
                255
                4294967295
                18446744073709551615
                2
                255
                caught
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesDecodeToStringRangeEdgeCases() throws {
        let source = """
        fun main() {
            val bytes = "abcdef".encodeToByteArray()
            println(bytes.decodeToString(1, 4))
            println(bytes.decodeToString(0, 6, true))

            val malformed = byteArrayOf((-61).toByte(), 40.toByte())
            println(malformed.decodeToString(0, 2, false).length > 0)
            try {
                println(malformed.decodeToString(0, 2, true))
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DecodeToStringRangeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                bcd
                abcdef
                true
                caught
                """
                + "\n"
            )
        }
    }
}
