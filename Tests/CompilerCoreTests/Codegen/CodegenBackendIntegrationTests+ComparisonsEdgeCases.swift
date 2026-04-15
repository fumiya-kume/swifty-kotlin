@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsEdgeCases() throws {
        let source = """
        fun main() {
            println(compareValues(1, 2))
            println(compareValues(2, 2))
            println(compareValues(3, 2))
            println(compareValues(null, 1))
            println(compareValues(1, null))

            val words = listOf("pear", "apple", "fig")
            println(words.sorted())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparisonsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                -1
                0
                1
                -1
                1
                [apple, fig, pear]
                
                """
            )
        }
    }
}
