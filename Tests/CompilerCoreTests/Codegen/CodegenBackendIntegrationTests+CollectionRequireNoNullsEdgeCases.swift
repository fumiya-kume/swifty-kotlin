@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRequireNoNullsChecksIterableReceivers() throws {
        let source = """
        fun main() {
            val values: Iterable<String?> = listOf("a", "b")
            val checked: Iterable<String> = values.requireNoNulls()
            println(checked.toList())
            println(listOf("x", null).requireNoNulls())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRequireNoNullsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            do {
                _ = try CommandRunner.run(executable: outputBase, arguments: [])
                XCTFail("Expected requireNoNulls to fail on a null element")
            } catch let CommandRunnerError.nonZeroExit(failed) {
                let normalizedStdout = failed.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                XCTAssertEqual(
                    normalizedStdout,
                    """
                    [a, b]
                    """ + "\n"
                )
                XCTAssertNotEqual(failed.exitCode, 0)
                XCTAssertTrue(failed.stderr.contains("Unhandled top-level exception"))
            }
        }
    }
}
