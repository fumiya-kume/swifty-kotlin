import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenStringIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println("abcabc".indexOfLast { it == 'b' })
            println("abcabc".indexOfLast { it == 'z' })
            println("hello".indexOfLast { it == 'l' })
            println("".indexOfLast { it == 'a' })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringIndexOfLastRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "4\n-1\n3\n-1\n")
        }
    }
}
