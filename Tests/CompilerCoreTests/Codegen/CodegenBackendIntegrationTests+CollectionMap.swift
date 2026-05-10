@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMapUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val offset = 5
            val shifted = values.map { it + offset }
            println(shifted)
            println(shifted.size)

            val words = listOf("a", "bb").map { it + "!" }
            println(words)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[6, 7, 8]\n3\n[a!, bb!]\n")
        }
    }
}
