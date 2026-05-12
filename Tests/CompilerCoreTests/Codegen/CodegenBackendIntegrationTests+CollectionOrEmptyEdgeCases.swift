@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOrEmptyHandlesNullableListAndMapReceivers() throws {
        let source = """
        fun main() {
            val missingList: List<Int>? = null
            val presentList: List<Int>? = listOf(1, 2, 3)
            val missingMap: Map<String, Int>? = null
            val presentMap: Map<String, Int>? = mapOf("a" to 1, "b" to 2)

            println(missingList.orEmpty())
            println(presentList.orEmpty())
            println(missingMap.orEmpty().count())
            println(presentMap.orEmpty().count())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionOrEmptyEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[]\n[1, 2, 3]\n0\n2\n")
        }
    }
}
