@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveAllMutatesListsAndSets() throws {
        let source = """
        fun main() {
            val numbers = mutableListOf(1, 2, 3, 4)
            println(numbers.removeAll(listOf(2, 4)))
            println(numbers)
            println(numbers.removeAll(setOf(9)))
            println(numbers)

            val values = mutableSetOf(1, 2, 3, 4)
            println(values.removeAll(listOf(1, 4)))
            println(values)
            println(values.removeAll(setOf(9)))
            println(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRemoveAllEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                [1, 3]
                false
                [1, 3]
                true
                [2, 3]
                false
                [2, 3]
                """ + "\n"
            )
        }
    }
}
