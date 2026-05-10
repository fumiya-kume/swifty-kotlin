@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printScans(values: List<Int>) {
            println(values.scan(10) { acc, value -> acc + value })
        }

        fun main() {
            printScans(listOf(1, 2, 3))
            println(listOf<Int>().scan(7) { acc, value -> acc + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionScanEdgeCases",
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
