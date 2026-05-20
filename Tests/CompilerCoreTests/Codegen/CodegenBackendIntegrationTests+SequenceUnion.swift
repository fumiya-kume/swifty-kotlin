@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceUnionExecutes() throws {
        let source = """
        fun main() {
            val unioned = sequenceOf(1, 2, 3, 2).union(listOf(3, 4, 1))
            println(unioned)
            println(unioned.size)
            println(unioned.contains(4))
            println(unioned.contains(99))

            println(emptySequence<Int>().union(listOf(5, 5, 6)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceUnionRuntime",
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
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4]\n4\ntrue\nfalse\n[5, 6]\n")
        }
    }
}
