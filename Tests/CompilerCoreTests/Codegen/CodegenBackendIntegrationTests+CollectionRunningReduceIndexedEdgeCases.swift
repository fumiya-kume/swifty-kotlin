@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningReduceIndexedUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printReductions(values: List<Int>) {
            println(values.runningReduceIndexed { index, acc, value -> acc + index + value })
        }

        fun main() {
            printReductions(listOf(1, 2, 3))
            println(listOf<Int>().runningReduceIndexed { index, acc, value -> acc + index + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRunningReduceIndexedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 4, 9]
                []
                """ + "\n"
            )
        }
    }
}
