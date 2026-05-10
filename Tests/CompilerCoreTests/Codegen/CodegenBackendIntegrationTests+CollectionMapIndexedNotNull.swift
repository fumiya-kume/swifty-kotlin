@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMapIndexedNotNullUsesRuntimeHelper() throws {
        let source = """
        fun maybeWord(index: Int, value: String): String? = if (index % 2 == 0) value + index else null
        fun maybeInt(index: Int, value: Int): Int? = if (index + value > 2) index + value else null

        fun main() {
            val words = listOf("a", "bb", "ccc").mapIndexedNotNull { index, value -> maybeWord(index, value) }
            println(words)
            println(words.size)

            val numbers = listOf(0, 1, 2).mapIndexedNotNull { index, value -> maybeInt(index, value) }
            println(numbers)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionMapIndexedNotNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[a0, ccc2]\n2\n[4]\n")
        }
    }
}
