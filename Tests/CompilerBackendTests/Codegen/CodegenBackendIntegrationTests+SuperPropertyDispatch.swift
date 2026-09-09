#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// BUG-228 regression coverage: a super-qualified property read must select the
// direct superclass declaration, while a super-qualified method call continues
// to use the direct superclass implementation.
private func runSuperPropertyDispatchCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendSuperPropertyDispatchTests {
    @Test
    func testSuperPropertyReadUsesDirectSuperclassImplementation() throws {
        let source = """
        open class Base {
            open val p = "bp"
        }
        class Derived : Base() {
            override val p = "dp"
            fun viaSuper() = super.p
        }
        fun main() {
            println(Derived().viaSuper())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runSuperPropertyDispatchCodegenPipeline(
                inputPath: path,
                moduleName: "Bug228SuperProperty",
                outputPath: outputBase
            )
            #expect(
                !ctx.diagnostics.hasError,
                "Expected BUG-228 repro to compile without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "bp\n")
        }
    }
}
#endif
