@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningReduceUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printReductions(values: List<Int>) {
            println(values.runningReduce { acc, value -> acc + value })
        }

        fun main() {
            printReductions(listOf(1, 2, 3))
            println(listOf<Int>().runningReduce { acc, value -> acc + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRunningReduceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 3, 6]
                []
                """ + "\n"
            )
        }
    }
}
