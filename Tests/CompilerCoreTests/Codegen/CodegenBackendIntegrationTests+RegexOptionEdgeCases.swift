@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRegexOptionEdgeCases() throws {
        let source = """
        fun main() {
            val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
            println(ignoreCase.containsMatchIn("HeLLo"))

            val dotDefault = Regex("a.b")
            val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
            println(dotDefault.containsMatchIn("a\\nb"))
            println(dotAll.containsMatchIn("a\\nb"))

            val combined = Regex(
                "^hello.world$",
                setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL, RegexOption.MULTILINE)
            )
            println(combined.containsMatchIn("HELLO\\nWORLD"))
            println(combined.matchEntire("hello\\nworld")?.value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RegexOptionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                false
                true
                true
                hello
                world
                """ + "\n"
            )
        }
    }
}
