@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListLastOrNullUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val ints = listOf(1, 2, 3)
            println(ints.lastOrNull() ?: -1)

            val emptyInts = emptyList<Int>()
            println(emptyInts.lastOrNull() ?: -1)

            val words = listOf("alpha", "beta")
            println(words.lastOrNull() ?: "missing")

            val emptyWords = emptyList<String>()
            println(emptyWords.lastOrNull() ?: "missing")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionLastOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n-1\nbeta\nmissing\n")
        }
    }
}
