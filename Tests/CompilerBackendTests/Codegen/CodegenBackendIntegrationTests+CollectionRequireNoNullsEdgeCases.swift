@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

private func runCollectionRequireNoNullsCodegenPipeline(
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
struct CodegenBackendCollectionRequireNoNullsEdgeCasesTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCollectionRequireNoNullsCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func codegenCollectionRequireNoNullsChecksIterableReceivers() throws {
        let source = """
        fun main() {
            val values: Iterable<String?> = listOf("a", "b")
            val checked: Iterable<String> = values.requireNoNulls()
            println(checked.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRequireNoNullsEdgeCases",
            expected: "[a, b]\n"
        )
    }

    @Test
    func codegenListRequireNoNullsPreservesListReturnType() throws {
        let source = """
        fun main() {
            val values: List<String?> = listOf("a", "b")
            val checked: List<String> = values.requireNoNulls()
            println(checked)

            try {
                listOf<String?>("a", null).requireNoNulls()
                println("unexpected")
            } catch (e: IllegalArgumentException) {
                println("null")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRequireNoNullsListReturnType",
            expected: "[a, b]\nnull\n"
        )
    }
}
#endif
