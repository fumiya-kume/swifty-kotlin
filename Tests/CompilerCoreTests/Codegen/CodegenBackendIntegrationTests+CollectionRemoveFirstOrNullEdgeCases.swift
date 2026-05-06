@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveFirstOrNullMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRemoveFirstOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                10
                [20]
                20
                []
                -1
                []
                """ + "\n"
            )
        }
    }
}
