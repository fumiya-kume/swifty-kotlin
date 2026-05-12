@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveLastOrNullMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20)
            println(values.removeLastOrNull() ?: -1)
            println(values)
            println(values.removeLastOrNull() ?: -1)
            println(values)
            println(values.removeLastOrNull() ?: -1)
            println(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRemoveLastOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                20
                [10]
                10
                []
                -1
                []
                """ + "\n"
            )
        }
    }
}
