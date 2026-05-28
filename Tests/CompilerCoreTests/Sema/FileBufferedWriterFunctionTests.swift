@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-010: Validates that `File.bufferedWriter()` resolves through Sema
/// for the `java.io.File` receiver and produces a `java.io.BufferedWriter`.
///
/// The runtime link name exercised here is `kk_file_bufferedWriter`.
///
/// Kotlin signature:
///
///     public fun File.bufferedWriter(
///         charset: Charset = Charsets.UTF_8
///     ): BufferedWriter
///
/// Declared as a synthetic member of `java.io.File` (registered via
/// `registerFileMemberFunction` with no-arg parameters; charset support
/// is handled by the runtime which defaults to UTF-8).
final class FileBufferedWriterFunctionTests: XCTestCase {

    // MARK: - Basic resolution

    func testFileBufferedWriterNoArgsResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedWriter
        import java.io.File

        fun openWriter(file: File): BufferedWriter = file.bufferedWriter()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.bufferedWriter() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFileBufferedWriterReturnTypeIsBufferedWriter() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedWriter
        import java.io.File

        fun getWriter(file: File): BufferedWriter {
            val w: BufferedWriter = file.bufferedWriter()
            return w
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.bufferedWriter() return type to be BufferedWriter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Chained member calls

    func testFileBufferedWriterChainedWriteFlushCloseResolve() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun writeAndClose(file: File) {
            val writer = file.bufferedWriter()
            writer.write("hello")
            writer.newLine()
            writer.flush()
            writer.close()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected chained BufferedWriter member calls to resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFileBufferedWriterInlineChainedCallsResolve() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun writeOneLiner(file: File) {
            file.bufferedWriter().use { it.write("one-liner") }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected inline File.bufferedWriter().use { } to resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Sema surface inspection

    func testFileBufferedWriterExtensionFunctionSurfaceIsRegistered() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.File

        fun stub(file: File): BufferedWriter = file.bufferedWriter()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.bufferedWriter() should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let bufferedWriterSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
            )
            let fileType = types.make(.classType(ClassType(
                classSymbol: fileSymbol, args: [], nullability: .nonNull
            )))
            let bufferedWriterType = types.make(.classType(ClassType(
                classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
            )))

            // bufferedWriter is registered as java.io.File.bufferedWriter
            let candidates = symbols.lookupAll(
                fqName: ["java", "io", "File", "bufferedWriter"].map(interner.intern)
            )
            let bufferedWriter = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == fileType
                    && signature.parameterTypes == []
                    && signature.returnType == bufferedWriterType
            }, "Expected to find java.io.File.bufferedWriter() with receiver=File, params=[], ret=BufferedWriter")

            XCTAssertEqual(
                symbols.externalLinkName(for: bufferedWriter),
                "kk_file_bufferedWriter"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: bufferedWriter))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])
        }
    }
}
