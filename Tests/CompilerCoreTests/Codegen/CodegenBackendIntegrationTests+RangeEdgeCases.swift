@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRangeEdgeCases() throws {
        let source = """
        fun main() {
            println((1 until 5).toList())
            println((5 downTo 1 step 2).toList())
            println((1..0).toList())

            println(3.coerceIn(1, 5))
            println(0.coerceIn(1, 5))
            println(9.coerceIn(1, 5))

            println(3.coerceAtLeast(5))
            println(8.coerceAtMost(5))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RangeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2, 3, 4]
                [5, 3, 1]
                []
                3
                1
                5
                5
                5
                """
            )
        }
    }
}
