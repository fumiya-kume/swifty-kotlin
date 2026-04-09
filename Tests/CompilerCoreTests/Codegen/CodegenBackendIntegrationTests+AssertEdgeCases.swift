@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesAssertEdgeCases() throws {
        let source = """
        fun main() {
            var counter = 0

            require(true) { counter += 1; "require should not run" }
            check(true) { counter += 10; "check should not run" }
            println(counter)

            try {
                require(false) { "bad-arg" }
            } catch (e: Throwable) {
                println(e.message)
            }

            try {
                check(false) { "bad-state" }
            } catch (e: Throwable) {
                println(e.message)
            }

            try {
                error("boom")
            } catch (e: Throwable) {
                println(e.message)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "AssertEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0
                bad-arg
                bad-state
                boom
                """
            )
        }
    }
}
