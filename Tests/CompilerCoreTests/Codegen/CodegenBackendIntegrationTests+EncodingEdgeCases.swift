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

            val asciiRange = "abcdef".encodeToByteArray()
            println(asciiRange.decodeToString(1, 4))
            println(asciiRange.decodeToString(1, 4, true))

            val malformed = byteArrayOf((-1).toByte())
            println(malformed.decodeToString(0, 1, false).length)
            try {
                println(malformed.decodeToString(0, 1, true))
            } catch (e: Throwable) {
                println("strict")
            }
            try {
                println(asciiRange.decodeToString(-1, 2, false))
            } catch (e: Throwable) {
                println("range")
            }

            val ascii = "ABC".encodeToByteArray()
            println(String(ascii, Charsets.US_ASCII))

            val hex = 255.toHexString()
            println(hex)
            println(hex.hexToInt())
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
                bcd
                bcd
                3
                strict
                range
                ABC
                000000ff
                255
                caught
                """
                + "\n"
            )
        }
    }
}
