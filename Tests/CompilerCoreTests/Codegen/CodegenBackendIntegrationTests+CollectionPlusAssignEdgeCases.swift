@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionPlusAssignMutatesMutableCollections() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1)
            list += 2
            list += listOf(3, 4)
            println(list)

            val set = mutableSetOf("a")
            set += "b"
            set += setOf("b", "c")
            println(set)

            val map = mutableMapOf("a" to 1)
            map += ("b" to 2)
            map += mapOf("a" to 9, "c" to 3)
            println(map)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionPlusAssignEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4]\n[a, b, c]\n{a=9, b=2, c=3}\n")
        }
    }
}
