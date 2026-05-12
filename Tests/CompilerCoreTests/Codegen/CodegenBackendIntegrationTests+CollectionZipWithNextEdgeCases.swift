@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionZipWithNextOverloads() throws {
        let source = """
        fun main() {
            val values = listOf(1, 3, 6, 10)
            println(values.zipWithNext())
            println(values.zipWithNext { left, right -> right - left })
            println(listOf(1).zipWithNext())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionZipWithNextOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[(1, 3), (3, 6), (6, 10)]\n[2, 3, 4]\n[]\n")
        }
    }
}
