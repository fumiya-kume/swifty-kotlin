#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags,
        stdlibLibraryPath: try testStdlibArtifactPath()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite
struct CodegenBackendCollectionJoinToTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test func testCodegenIterableJoinToAppendsToStringBuilder() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun main() {
            val values: Collection<Int> = listOf(1, 2, 3)
            val first = StringBuilder("seed:")
            values.joinTo(first, "|", "<", ">")
            println(first.toString())

            val second = StringBuilder()
            listOf("a", "b", "c").joinTo(second)
            println(second.toString())

            val third = StringBuilder()
            setOf("x", "y").joinTo(third, ";", "[", "]")
            println(third.toString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionJoinToRuntime",
            expected:
                """
                seed:<1|2|3>
                a, b, c
                [x;y]
                """ + "\n"
        )
    }

    // KSP-435: Iterable.joinTo is bundled Kotlin source, so the call lowers to
    // the source function instead of the kk_iterable_joinTo runtime bridge.
    @Test func testCodegenIterableJoinToUsesBundledSource() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun render(values: Collection<Int>, builder: StringBuilder): String {
            values.joinTo(builder, "|", "<", ">")
            return builder.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "CollectionJoinToKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(containsKotlinCallee("joinTo", in: callees)
                || containsKotlinCallee("joinTo$default", in: callees))
            #expect(!callees.contains("kk_iterable_joinTo"))
            // KSP-621: the runtime bridge itself (and the CallLowerer fallback that
            // used to rescue unresolved calls onto it) has been removed.
            #expect(!callees.contains("__kk_iterable_joinTo"))
        }
    }
}
#endif
