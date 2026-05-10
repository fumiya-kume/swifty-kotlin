@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionShuffledPreservesElementsForListReceivers() throws {
        let source = """
        import kotlin.random.Random

        fun printShuffled(values: List<Int>) {
            println(values.shuffled().sorted())
            println(values.shuffled(Random(42)).sorted())
        }

        fun main() {
            printShuffled(listOf(3, 1, 2))
            println(listOf(6, 4, 5).shuffled().sorted())
            println(listOf<Int>().shuffled())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionShuffledEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2, 3]
                [1, 2, 3]
                [4, 5, 6]
                []
                """ + "\n"
            )
        }
    }
}
