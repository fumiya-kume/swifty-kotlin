@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningFoldUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.runningFold(10) { acc, value -> acc + value })
            println(listOf<Int>().runningFold(7) { acc, value -> acc + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRunningFoldEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [10, 11, 13, 16]
                [7]
                """ + "\n"
            )
        }
    }
}
