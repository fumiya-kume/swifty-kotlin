@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression coverage for imported inline KIR callback result types.
@Suite
struct ImportedInlineKIRRegressionTests {
    private static let artifactLock = NSLock()
    nonisolated(unsafe) private static var cachedArtifactPath: String?

    private static func buildStdlibArtifact() throws -> String {
        artifactLock.lock()
        defer { artifactLock.unlock() }

        if let cachedArtifactPath {
            return cachedArtifactPath
        }

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSP1374-ImportedInlineKIR-\(UUID().uuidString)")
            .path
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: outputBase,
            includeStdlib: true,
            stdlibOnly: true
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        let artifactPath = outputBase + ".kklib"
        #expect(FileManager.default.fileExists(atPath: artifactPath))
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/inline-kir"))
        cachedArtifactPath = artifactPath
        return artifactPath
    }

    @Test
    func importedFirstPredicateFalseBranchRunsThroughArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        private fun firstNonLocal(source: CharSequence): Char {
            source.first {
                if (it == 'x') return '!'
                false
            }
            return '?'
        }

        fun main() {
            println(firstNonLocal("ax").code)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSP1374-ImportedInlineKIR-User-\(UUID().uuidString)")
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1374ImportedInlineKIRUser",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "33\n")
        }
    }
}
