@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenThrowablePrintStackTraceWritesToStandardError() throws {
        let source = """
        fun main() {
            RuntimeException("stack message").printStackTrace()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowablePrintStackTraceRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStderr = result.stderr.replacingOccurrences(of: "\r\n", with: "\n")
            // Linux libswiftCore.so may emit "warning: direct reference to protected
            // function ... may break pointer equality" lines unrelated to the test.
            // Strip those so the assertion focuses on the program's actual output.
            let filteredStderr = normalizedStderr
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("warning: direct reference to protected function") }
                .joined(separator: "\n")
            XCTAssertEqual(result.stdout, "")
            XCTAssertEqual(filteredStderr, "stack message\n")
        }
    }
}
