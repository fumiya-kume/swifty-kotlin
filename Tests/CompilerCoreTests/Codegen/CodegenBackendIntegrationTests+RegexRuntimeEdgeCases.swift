@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRegexRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val named = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val match = named.find("2025-04")
            println(match?.groups?.get("year")?.value)
            println(match?.groups?.get("month")?.value)

            try {
                Regex("(")
                println("unexpected-regex")
            } catch (e: Throwable) {
                println("invalid-pattern")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RegexRuntimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2025
                04
                invalid-pattern
                """
            )
        }
    }
}
