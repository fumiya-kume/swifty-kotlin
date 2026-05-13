@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanReduceUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printScans(values: List<Int>) {
            println(values.scanReduce { acc, value -> acc + value })
        }

        fun main() {
            printScans(listOf(1, 2, 3))
            println(listOf(4, 5).scanReduce { acc, value -> acc + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionScanReduceEdgeCases",
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
                [4, 9]
                """ + "\n"
            )
        }
    }
}
