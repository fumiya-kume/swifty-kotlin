@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionNoneEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.none())
            println(values.none { it > 3 })
            println(values.none { it == 2 })

            val emptyValues = emptyList<Int>()
            println(emptyValues.none())

            val array = arrayOf(1, 2, 3)
            println(array.none())
            println(array.none { it < 0 })

            val map = mapOf("a" to 1, "b" to 2)
            println(map.none { it.value > 2 })
            println(map.none { it.key == "a" })

            val set = setOf(1, 2, 3)
            println(set.none())
            println(set.none { it == 4 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionNoneEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "false\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\nfalse\ntrue\n")
        }
    }
}
