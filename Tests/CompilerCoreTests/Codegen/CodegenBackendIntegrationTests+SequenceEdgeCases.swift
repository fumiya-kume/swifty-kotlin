@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesSequenceEdgeCases() throws {
        let source = """
        fun main() {
            val generated = generateSequence(1) { current -> if (current >= 3) null else current + 1 }
            println(generated.take(2).toList())

            val filtered = sequenceOf(1, 2, 3, 4)
                .map { it * 2 }
                .filter { it % 4 == 0 }

            println(filtered.take(1).toList())
            println(filtered.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2]
                [4]
                [4, 8]
                """
                + "\n"
            )
        }
    }
}
