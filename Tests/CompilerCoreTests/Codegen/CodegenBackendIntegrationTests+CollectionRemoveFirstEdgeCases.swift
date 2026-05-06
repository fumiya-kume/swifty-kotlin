@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveFirstMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20, 30)
            println(values.removeFirst())
            println(values)
            val typed: MutableList<Int> = mutableListOf(40, 50)
            println(typed.removeFirst())
            println(typed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRemoveFirstEdgeCases",
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
                [20, 30]
                40
                [50]
                """ + "\n"
            )
        }
    }
}
