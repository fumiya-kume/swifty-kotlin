@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesNoWhenBranchMatchedException() throws {
        let source = """
        fun main() {
            try {
                throw NoWhenBranchMatchedException("missing")
            } catch (e: NoWhenBranchMatchedException) {
                println("no-when")
            }

            try {
                throw NoWhenBranchMatchedException()
            } catch (e: RuntimeException) {
                println("runtime")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NoWhenBranchMatchedExceptionCase",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "no-when\nruntime\n")
        }
    }
}
