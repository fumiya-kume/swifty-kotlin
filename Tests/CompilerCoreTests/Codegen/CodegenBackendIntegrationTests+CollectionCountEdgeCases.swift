@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionCountEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4)
            println(values.count())
            println(values.count { it % 2 == 0 })

            val array = arrayOf(1, 2, 3, 4)
            println(array.count())
            println(array.count { it > 2 })

            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(map.count())
            println(map.count { it.value >= 2 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionCountEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "4\n2\n4\n2\n3\n2\n")
        }
    }
}
