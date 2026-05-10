@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSubtractReturnsSetWithReceiverOrder() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 2, 3, 4).subtract(listOf(2, 4, 2)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListSubtractRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("LinkPhase failed: \(error)\n\(diagnostics.joined(separator: "\n"))")
                throw error
            }
            XCTAssertFalse(
                ctx.diagnostics.diagnostics.contains { $0.severity == .error },
                ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            )

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3]\n")
        }
    }
}
