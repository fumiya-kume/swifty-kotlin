@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCollectionWindowedTransformEdgeCases() throws {
        let source = """
        fun main() {
            val numbers: Iterable<Int> = listOf(1, 2, 3, 4, 5)

            val defaultStep = numbers.windowed(3) { window ->
                window.sum()
            }
            println(defaultStep)

            val explicitStep = numbers.windowed(3, 2) { window ->
                window.sum()
            }
            println(explicitStep)

            val partialWindows = numbers.windowed(3, 2, true) { window ->
                window.sum()
            }
            println(partialWindows)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionWindowedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [6, 9, 12]
                [6, 12]
                [6, 12, 5]
                """ + "\n"
            )
        }
    }
}
