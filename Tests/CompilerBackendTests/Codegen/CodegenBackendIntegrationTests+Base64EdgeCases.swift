#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendBase64EdgeCasesTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
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
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCompilesBase64EncodeDecodeEdgeCases() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val bytes = "foo".encodeToByteArray()
            val encoded = Base64.Default.encode(bytes)
            println(encoded)
            println(Base64.Default.decode(encoded).decodeToString())
            println(Base64.UrlSafe.encode("\\u083e".encodeToByteArray()))
            println(Base64.Mime.decode("Zm9v\\r\\nYmFy").decodeToString())
            println(Base64.Pem.decode("Zm9v\\r\\nYmFy").decodeToString())
            val encodedBytes = Base64.Default.encodeToByteArray(bytes)
            println(Base64.Default.encode(Base64.Default.decode(encodedBytes)))
            println(Base64.UrlSafe.encode(Base64.UrlSafe.decode(Base64.UrlSafe.encodeToByteArray("\\u083e".encodeToByteArray()))))
            println(Base64.Default.encode(Base64.Mime.decode("Zm9v\\r\\nYmFy".encodeToByteArray())))
            val foob = "foob".encodeToByteArray()
            println(Base64.UrlSafe.encode(foob))
            val defaultNoPad = Base64.Default.withPadding(Base64.PaddingOption.ABSENT)
            println(defaultNoPad.encode(foob))
            println(Base64.Default.encode(defaultNoPad.decode("Zm9vYg")))
            val urlSafeNoPad = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL)
            println(urlSafeNoPad.encode("\\u083e!".encodeToByteArray()))
            println(Base64.Default.encode(urlSafeNoPad.decode("4KC-IQ==")))
            val mimeNoPad = Base64.Mime.withPadding(Base64.PaddingOption.ABSENT)
            println(mimeNoPad.encode(foob))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Base64EdgeCases",
            expected:
                """
                Zm9v
                foo
                4KC-
                foobar
                foobar
                Zm9v
                4KC-
                Zm9vYmFy
                Zm9vYg==
                Zm9vYg
                Zm9vYg==
                4KC-IQ
                4KC+IQ==
                Zm9vYg
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesBase64RangeAndDestinationAPIs() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.text.Appendable

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeRange(source: ByteArray): String = Base64.Default.encode(source, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeToByteArrayRange(source: ByteArray): ByteArray =
            Base64.Default.encodeToByteArray(source, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeIntoByteArrayRange(source: ByteArray): String {
            val destination = ByteArray(8)
            val count = Base64.Default.encodeIntoByteArray(source, destination, 2, 1, 4)
            return count.toString() + ":" + destination.decodeToString(2, 2 + count)
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeToAppendableRange(source: ByteArray, destination: Appendable): Appendable =
            Base64.Default.encodeToAppendable(source, destination, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeByteArrayRange(source: ByteArray): ByteArray = Base64.Default.decode(source, 1, 5)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeIntoByteArrayRange(source: ByteArray): String {
            val destination = ByteArray(6)
            val count = Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)
            return count.toString() + ":" + destination.decodeToString(2, 2 + count)
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeCharSequenceRange(source: CharSequence): ByteArray = Base64.Default.decode(source, 1, 5)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeIntoCharSequenceRange(source: CharSequence): String {
            val destination = ByteArray(6)
            val count = Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)
            return count.toString() + ":" + destination.decodeToString(2, 2 + count)
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val source = "xfoob".encodeToByteArray()
            val encodedText = "xZm9vyy"
            println(encodeRange(source))
            println(encodeToByteArrayRange(source).decodeToString())
            println(encodeIntoByteArrayRange(source))
            println(encodeToAppendableRange(source, StringBuilder("prefix:")).toString())
            println(decodeByteArrayRange(encodedText.encodeToByteArray()).decodeToString())
            println(decodeIntoByteArrayRange(encodedText.encodeToByteArray()))
            println(decodeCharSequenceRange(encodedText).decodeToString())
            println(decodeIntoCharSequenceRange(encodedText))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Base64RangeAndDestinationAPIs",
            expected:
                """
                Zm9v
                Zm9v
                4:Zm9v
                prefix:Zm9v
                foo
                3:foo
                foo
                3:foo
                """ + "\n"
        )
    }
}
#endif
