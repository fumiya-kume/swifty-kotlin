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
                caught
                """
                + "\n"
            )
        }
    }
}
