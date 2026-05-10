@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionDistinctByEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            println(values.distinctBy { it % 2 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionDistinctByEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("Link failed for distinctBy: \(diagnostics)")
                throw error
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2]\n")
        }
    }
}
