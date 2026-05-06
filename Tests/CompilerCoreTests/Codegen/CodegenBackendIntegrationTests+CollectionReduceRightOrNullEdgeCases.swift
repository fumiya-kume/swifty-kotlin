@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceRightOrNullReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightOrNull { value, acc -> value - value + acc - acc + 7 } ?: -1)
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightOrNull { value, acc -> value - value + acc - acc + 7 } ?: -1)
            val emptyValues: Iterable<Int> = emptySet<Int>()
            println(emptyValues.reduceRightOrNull { value, acc -> value + acc } ?: -1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionReduceRightOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "7\n7\n-1\n")
        }
    }
}
