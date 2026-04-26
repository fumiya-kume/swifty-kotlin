@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesBase64EncodeDecodeEdgeCases() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val bytes = "foo".encodeToByteArray()
            val encoded = Base64.Default.encode(bytes)
            println(encoded)
            println(Base64.Default.decode(encoded).decodeToString())
            println(Base64.UrlSafe.encode("\\u083e".encodeToByteArray()))
            println(Base64.Mime.decode("Zm9v\\r\\nYmFy").decodeToString())
            println(Base64.PemMime.decode("Zm9v\\r\\nYmFy").decodeToString())
            val encodedBytes = Base64.Default.encodeToByteArray(bytes)
            println(Base64.Default.encode(Base64.Default.decodeFromByteArray(encodedBytes)))
            println(Base64.UrlSafe.encode(Base64.UrlSafe.decodeFromByteArray(Base64.UrlSafe.encodeToByteArray("\\u083e".encodeToByteArray()))))
            println(Base64.Default.encode(Base64.Mime.decodeFromByteArray("Zm9v\\r\\nYmFy".encodeToByteArray())))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "Base64EdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                Zm9v
                foo
                4KC-
                foobar
                foobar
                Zm9v
                4KC-
                Zm9vYmFy
                """ + "\n"
            )
        }
    }
}
