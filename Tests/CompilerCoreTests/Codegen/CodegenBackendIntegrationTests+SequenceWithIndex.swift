@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceWithIndexUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("sequence_withindex.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceWithIndexRuntime",
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
            XCTAssertEqual(
                normalizedStdout,
                "[IndexedValue(index=0, value=10), IndexedValue(index=1, value=20), IndexedValue(index=2, value=30)]\n"
                    + "[IndexedValue(index=0, value=10)]\n"
                    + "[]\n"
            )
        }
    }
}
