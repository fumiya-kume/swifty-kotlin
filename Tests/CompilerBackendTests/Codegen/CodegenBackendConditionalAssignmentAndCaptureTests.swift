@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendConditionalAssignmentAndCaptureTests {
    private func checkExecution(fixture: String, expected: String) throws {
        let source = try diffCaseSource(fixture)
        try withTemporaryFile(contents: source) { input in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let executable = directory.appendingPathComponent("program").path
            let context = CompilationContext(
                options: CompilerOptions(
                    moduleName: "ConditionalAssignmentAndCapture",
                    inputs: [input],
                    outputPath: executable,
                    emit: .executable,
                    target: defaultTargetTriple()
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)
            #expect(!context.diagnostics.hasError)
            let result = try CommandRunner.run(executable: executable, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    @Test
    func unbracedAssignmentsExecuteTheCorrectElseBranch() throws {
        try checkExecution(
            fixture: "unbraced_if_assignments.kt",
            expected: "1\n2\n10\n20\n30\n1\n2\n3\n22\n"
        )
    }

    @Test
    func mutableCaptureInitializationDominatesSiblingBranches() throws {
        try checkExecution(
            fixture: "mutable_capture_conditional_initialization.kt",
            expected: "a\nb\nb\na\n11\n12\n13\n12\n"
        )
    }
}
