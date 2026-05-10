@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMapIndexedNotNullToUsesRuntimeHelper() throws {
        let source = """
        fun maybeWord(index: Int, value: String): String? = if (index % 2 == 0) value + index else null

        fun main() {
            val dest = mutableListOf("seed")
            val returned = listOf("a", "bb", "ccc").mapIndexedNotNullTo(dest) { index, value ->
                maybeWord(index, value)
            }
            println(dest)
            println(returned)
            println(dest.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMapIndexedNotNullToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("Link failed with diagnostics: \(diagnostics)")
                throw error
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, a0, ccc2]\n[seed, a0, ccc2]\n3\n")
        }
    }
}
