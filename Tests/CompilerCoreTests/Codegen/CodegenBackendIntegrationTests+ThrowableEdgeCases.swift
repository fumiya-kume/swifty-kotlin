@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenThrowableSuppressedExceptionsProperty() throws {
        let source = """
        fun main() {
            val primary = RuntimeException("primary")
            primary.addSuppressed(IllegalStateException("suppressed1"))
            primary.addSuppressed(IllegalArgumentException("suppressed2"))

            val suppressed = primary.suppressedExceptions
            println(suppressed.size)
            println(suppressed[0].message)
            println(suppressed[1].message)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableSuppressedExceptionsRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\nsuppressed1\nsuppressed2\n")
        }
    }
}
