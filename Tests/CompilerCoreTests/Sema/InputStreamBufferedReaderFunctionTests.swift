@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-007: Validates that `InputStream.bufferedReader(charset)` —
/// the `kotlin.io` top-level extension on `java.io.InputStream` — resolves
/// through Sema for both the default-charset and explicit-charset call
/// shapes, and that the returned `BufferedReader` exposes its `readLine`,
/// `readLines`, `read`, `ready`, and `close` members so the `.use { }`
/// closeable pattern works.
///
/// Runtime link names involved: `kk_input_stream_bufferedReader`,
/// `kk_buffered_reader_readLine`, `kk_buffered_reader_close`.
final class InputStreamBufferedReaderFunctionTests: XCTestCase {

    func testInputStreamBufferedReaderResolvesWithDefaultCharset() throws {
        let ctx = makeContextFromSource("""
        import java.io.ByteArrayInputStream
        import java.io.BufferedReader
        import java.io.InputStream

        fun readWithDefaults(bytes: List<Int>): String? {
            val stream: InputStream = ByteArrayInputStream(bytes)
            val reader: BufferedReader = stream.bufferedReader()
            val firstLine = reader.readLine()
            reader.close()
            return firstLine
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "InputStream.bufferedReader() with default charset should type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testInputStreamBufferedReaderResolvesWithExplicitCharset() throws {
        let ctx = makeContextFromSource("""
        import java.io.ByteArrayInputStream
        import java.io.BufferedReader
        import java.io.InputStream
        import kotlin.text.Charsets

        fun readAllLines(bytes: List<Int>): List<String> {
            val stream: InputStream = ByteArrayInputStream(bytes)
            val reader: BufferedReader = stream.bufferedReader(Charsets.UTF_8)
            return reader.readLines()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "InputStream.bufferedReader(Charsets.UTF_8) should type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testInputStreamBufferedReaderSignatureIsExtensionOnInputStream() throws {
        let ctx = makeContextFromSource("""
        fun probe() {}
        """)
        try runSema(ctx)

        guard let sema = ctx.sema else {
            return XCTFail("Sema module unavailable after runSema")
        }
        let symbols = sema.symbols
        let types = sema.types
        let interner = ctx.interner

        let bufferedReaderName = interner.intern("bufferedReader")
        let kotlinIOFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("io"),
            bufferedReaderName,
        ]

        let inputStreamFQName: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("InputStream"),
        ]
        let bufferedReaderClassFQName: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedReader"),
        ]
        guard let inputStreamSymbol = symbols.lookup(fqName: inputStreamFQName) else {
            return XCTFail("InputStream class symbol not registered")
        }
        guard let bufferedReaderSymbol = symbols.lookup(fqName: bufferedReaderClassFQName) else {
            return XCTFail("BufferedReader class symbol not registered")
        }

        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol, args: [], nullability: .nonNull
        )))
        let bufferedReaderType = types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
        )))

        let candidates = symbols.lookupAll(fqName: kotlinIOFQName)
        let matching = candidates.first { symbolID -> Bool in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.returnType == bufferedReaderType
                && signature.parameterTypes.count == 1
        }

        guard let functionSymbol = matching else {
            return XCTFail(
                "kotlin.io.bufferedReader extension on InputStream not registered (found \(candidates.count) candidate(s))"
            )
        }

        XCTAssertEqual(
            symbols.externalLinkName(for: functionSymbol),
            "kk_input_stream_bufferedReader",
            "InputStream.bufferedReader must link to kk_input_stream_bufferedReader"
        )

        guard let signature = symbols.functionSignature(for: functionSymbol) else {
            return XCTFail("Function signature unavailable")
        }
        XCTAssertEqual(
            signature.valueParameterHasDefaultValues,
            [true],
            "InputStream.bufferedReader's charset parameter must carry a default value"
        )
    }
}
