@testable import CompilerCore
import Foundation
import XCTest

/// Sema-surface tests for the `kotlin.io.encoding.encodingWith` extension
/// function on `java.io.OutputStream` (STDLIB-IO-ENC-FN-002).
///
/// Kotlin signature: `public fun OutputStream.encodingWith(
///     base64: Base64
/// ): OutputStream`
final class OutputStreamEncodingWithFunctionTests: XCTestCase {
    /// `OutputStream.encodingWith(base64)` should resolve to the synthetic
    /// extension function in `kotlin.io.encoding` and return an `OutputStream`.
    func testOutputStreamEncodingWithResolves() throws {
        let source = """
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.encodingWith

        fun openEncoder(file: File): OutputStream {
            val stream: OutputStream = file.outputStream()
            return stream.encodingWith(Base64.Default)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.encodingWith(base64) extension function in kotlin.io.encoding should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let outputStreamSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
            )
            let base64Symbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "encoding", "Base64"].map(interner.intern))
            )

            let outputStreamType = types.make(.classType(ClassType(
                classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
            )))
            let base64Type = types.make(.classType(ClassType(
                classSymbol: base64Symbol, args: [], nullability: .nonNull
            )))

            let encodingWithSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "encoding", "encodingWith"].map(interner.intern)
            )
            let encodingWith = try XCTUnwrap(encodingWithSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == outputStreamType
                    && signature.parameterTypes == [base64Type]
                    && signature.returnType == outputStreamType
            }, "Sema should register an OutputStream.encodingWith(Base64) extension")

            let signature = try XCTUnwrap(symbols.functionSignature(for: encodingWith))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])
        }
    }

    /// `encodingWith` should accept each predefined `Base64` variant
    /// (Default / UrlSafe / Mime / Pem) without diagnostics.
    func testOutputStreamEncodingWithAcceptsAllBase64Variants() throws {
        let source = """
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.encodingWith

        fun openVariants(file: File): List<OutputStream> {
            val stream: OutputStream = file.outputStream()
            return listOf(
                stream.encodingWith(Base64.Default),
                stream.encodingWith(Base64.UrlSafe),
                stream.encodingWith(Base64.Mime),
                stream.encodingWith(Base64.Pem),
            )
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.encodingWith should accept every Base64 variant: \(diagnostics)"
            )
        }
    }

    /// The returned `OutputStream` should remain usable for the standard
    /// member calls (`write`, `flush`, `close`) — confirming the type chain
    /// after `encodingWith` is preserved as `OutputStream`.
    func testOutputStreamEncodingWithChainedMemberCallsResolve() throws {
        let source = """
        import java.io.File
        import java.io.OutputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.encodingWith

        fun writeAndClose(file: File) {
            val stream: OutputStream = file.outputStream()
            val encoder = stream.encodingWith(Base64.Default)
            encoder.write(0x4B)
            encoder.flush()
            encoder.close()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Chained OutputStream member calls after encodingWith should resolve: \(diagnostics)"
            )
        }
    }

    /// The Sema layer should record the external link name on the symbol so
    /// codegen can resolve it to `kk_output_stream_encodingWith` later in
    /// the pipeline.
    func testOutputStreamEncodingWithExternalLinkNameIsRegisteredOnSymbol() throws {
        let source = """
        import java.io.OutputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.encodingWith

        fun stub(stream: OutputStream): OutputStream = stream.encodingWith(Base64.Default)
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
            let base64Symbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "encoding", "Base64"].map(interner.intern))
            )
            let outputStreamType = types.make(.classType(ClassType(
                classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
            )))
            let base64Type = types.make(.classType(ClassType(
                classSymbol: base64Symbol, args: [], nullability: .nonNull
            )))
            let encodingWithCandidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "encoding", "encodingWith"].map(interner.intern)
            )
            let encodingWith = try XCTUnwrap(encodingWithCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == outputStreamType
                    && signature.parameterTypes == [base64Type]
            }, "Sema should register an OutputStream.encodingWith(Base64) extension")
            XCTAssertEqual(
                symbols.externalLinkName(for: encodingWith),
                "kk_output_stream_encodingWith"
            )
        }
    }
}
