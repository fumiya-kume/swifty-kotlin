@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveLastMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20, 30)
            println(values.removeLast())
            println(values)
            val typed: MutableList<Int> = mutableListOf(40, 50)
            println(typed.removeLast())
            println(typed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRemoveLastEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                30
                [10, 20]
                50
                [40]
                """ + "\n"
            )
        }
    }
}
