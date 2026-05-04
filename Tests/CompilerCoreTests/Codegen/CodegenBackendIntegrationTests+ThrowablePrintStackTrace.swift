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
            // Some Linux dynamic linkers emit benign warnings about protected
            // Swift runtime symbols at process startup (e.g. "warning: direct
            // reference to protected function `$sSl...` in libswiftCore.so may
            // break pointer equality"). Drop those lines before comparing.
            let normalizedStderr = result.stderr
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("warning:") }
                .joined(separator: "\n")
            XCTAssertEqual(result.stdout, "")
            XCTAssertEqual(normalizedStderr, "stack message\n")
        }
    }
}
