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
            let normalizedStderr = result.stderr
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    !(line.hasPrefix("warning: direct reference to protected function ")
                        && line.contains(" may break pointer equality"))
                }
                .joined(separator: "\n")
            XCTAssertEqual(result.stdout, "")
            XCTAssertEqual(normalizedStderr, "stack message\n")
        }
    }
}
