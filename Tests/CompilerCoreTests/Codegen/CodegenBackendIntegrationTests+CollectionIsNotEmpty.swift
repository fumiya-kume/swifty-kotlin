import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIsNotEmptyUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1).isNotEmpty())
            println(emptyList<Int>().isNotEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListIsNotEmptyRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\n")
        }
    }
}
