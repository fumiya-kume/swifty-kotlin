@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionPlusHandlesListAndMapVariants() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2)
            println(values + 3)
            println(values + listOf(4, 5))

            val map = mapOf("a" to 1)
            val added = map + ("b" to 2)
            val overwritten = added + ("a" to 9)
            println(added)
            println(overwritten)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionPlusEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n[1, 2, 4, 5]\n{a=1, b=2}\n{a=9, b=2}\n")
        }
    }
}
