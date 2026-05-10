import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1, 4, 5, 6).indexOfLast { it % 2 == 0 })
            println(listOf(1, 3, 5).indexOfLast { it % 2 == 0 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListIndexOfLastRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n-1\n")
        }
    }
}
