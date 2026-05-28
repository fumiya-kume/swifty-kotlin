@testable import CompilerCore
import Foundation
import XCTest

/// Sema-surface tests for the `kotlin.io.bufferedWriter` extension function
/// on `java.io.OutputStream` (STDLIB-IO-FN-009).
///
/// Kotlin signature: `public fun OutputStream.bufferedWriter(
///     charset: Charset = Charsets.UTF_8
/// ): BufferedWriter`
final class OutputStreamBufferedWriterFunctionTests: XCTestCase {
    /// `OutputStream.bufferedWriter(charset)` should resolve to the
    /// synthetic extension function in `kotlin.io` and return a
    /// `java.io.BufferedWriter`.
    func testOutputStreamBufferedWriterWithExplicitCharsetResolves() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.bufferedWriter
        import kotlin.text.Charsets

        fun openWriter(file: File): BufferedWriter {
            val stream: OutputStream = file.outputStream()
            return stream.bufferedWriter(Charsets.UTF_8)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.bufferedWriter(charset) extension function in kotlin.io should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let outputStreamSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
            )
            let charsetSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
            )
            let bufferedWriterSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
            )

            let outputStreamType = types.make(.classType(ClassType(
                classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
            )))
            let charsetType = types.make(.classType(ClassType(
                classSymbol: charsetSymbol, args: [], nullability: .nonNull
            )))
            let bufferedWriterType = types.make(.classType(ClassType(
                classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
            )))

            let bufferedWriterSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "bufferedWriter"].map(interner.intern)
            )
            let bufferedWriter = try XCTUnwrap(bufferedWriterSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == outputStreamType
                    && signature.parameterTypes == [charsetType]
                    && signature.returnType == bufferedWriterType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: bufferedWriter),
                "kk_output_stream_bufferedWriter"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: bufferedWriter))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])
        }
    }

    /// `OutputStream.bufferedWriter()` with no arguments should resolve via
    /// the `charset` parameter's default value (`Charsets.UTF_8`).
    func testOutputStreamBufferedWriterWithDefaultCharsetResolves() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.bufferedWriter

        fun openWriter(file: File): BufferedWriter {
            val stream: OutputStream = file.outputStream()
            return stream.bufferedWriter()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.bufferedWriter() with default charset should resolve: \(diagnostics)"
            )
        }
    }

    /// The returned `BufferedWriter` should be usable for `.write`, `.flush`,
    /// and `.close` member calls — confirming the type chain stays intact.
    func testOutputStreamBufferedWriterChainedMemberCallsResolve() throws {
        let source = """
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.bufferedWriter
        import kotlin.text.Charsets

        fun writeAndClose(file: File) {
            val stream: OutputStream = file.outputStream()
            val writer = stream.bufferedWriter(Charsets.UTF_8)
            writer.write("hello")
            writer.flush()
            writer.close()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Chained BufferedWriter member calls after OutputStream.bufferedWriter should resolve: \(diagnostics)"
            )
        }
    }

    /// The Sema layer should record the external link name on the symbol so
    /// codegen can resolve it to `kk_output_stream_bufferedWriter` later in
    /// the pipeline.
    func testOutputStreamBufferedWriterExternalLinkNameIsRegisteredOnSymbol() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.OutputStream
        import kotlin.io.bufferedWriter
        import kotlin.text.Charsets

        fun stub(stream: OutputStream): BufferedWriter = stream.bufferedWriter(Charsets.UTF_8)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let outputStreamSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
            )
            let charsetSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
            )
            let outputStreamType = types.make(.classType(ClassType(
                classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
            )))
            let charsetType = types.make(.classType(ClassType(
                classSymbol: charsetSymbol, args: [], nullability: .nonNull
            )))
            let bufferedWriterCandidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "bufferedWriter"].map(interner.intern)
            )
            let bufferedWriter = try XCTUnwrap(bufferedWriterCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == outputStreamType
                    && signature.parameterTypes == [charsetType]
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: bufferedWriter),
                "kk_output_stream_bufferedWriter"
            )
        }
    }
}
