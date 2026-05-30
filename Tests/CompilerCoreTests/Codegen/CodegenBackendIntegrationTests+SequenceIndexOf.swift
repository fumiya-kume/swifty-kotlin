import XCTest
@testable import CompilerCore

// STDLIB-SEQ-FN-048: Sequence.indexOf
extension CodegenBackendIntegrationTests {
    func testCodegenSequenceIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 10, 30)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(99))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceIndexOfRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n1\n-1\n")
        }
    }
}
