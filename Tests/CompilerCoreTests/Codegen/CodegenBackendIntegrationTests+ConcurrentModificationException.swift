@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesConcurrentModificationException() throws {
        let source = """
        fun main() {
            try {
                throw ConcurrentModificationException("modified")
            } catch (e: ConcurrentModificationException) {
                println("concurrent")
            }

            try {
                throw ConcurrentModificationException()
            } catch (e: RuntimeException) {
                println("runtime")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ConcurrentModificationExceptionCase",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "concurrent\nruntime\n")
        }
    }
}
