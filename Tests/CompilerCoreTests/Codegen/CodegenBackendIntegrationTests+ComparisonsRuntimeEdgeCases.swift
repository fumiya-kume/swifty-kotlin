@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "apple", "fig")
            val byLength = compareBy<String> { it.length }

            println(words.maxWithOrNull(byLength))
            println(words.minWithOrNull(byLength))

            val empty = emptyList<String>()
            println(empty.maxWithOrNull(byLength))
            println(empty.minWithOrNull(byLength))

            try {
                println(empty.maxWith(byLength))
            } catch (e: Throwable) {
                println("maxWith-empty")
            }

            try {
                println(empty.minWith(byLength))
            } catch (e: Throwable) {
                println("minWith-empty")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparisonsRuntimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                apple
                fig
                null
                null
                maxWith-empty
                minWith-empty
                """
            )
        }
    }
}
