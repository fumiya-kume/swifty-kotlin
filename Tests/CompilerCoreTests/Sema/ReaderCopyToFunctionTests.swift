@testable import CompilerCore
import Foundation
import XCTest

/// Sema-surface tests for `kotlin.io.copyTo` extension function on
/// `java.io.Reader` (STDLIB-IO-FN-014).
///
/// Kotlin signature:
///   public fun Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long
///
/// The runtime link names exercised here are:
///   - `kk_reader_copyTo` (explicit bufferSize)
///   - `kk_reader_copyTo_default` (omitted bufferSize, uses the JVM default)
final class ReaderCopyToFunctionTests: XCTestCase {

    // MARK: - Helpers

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - Two-arg overload resolves and types as Long

    func testReaderCopyToWithExplicitBufferSizeResolves() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.BufferedWriter
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File): Long {
            val reader: BufferedReader = src.bufferedReader()
            val writer: BufferedWriter = dst.bufferedWriter()
            return reader.copyTo(writer, 8 * 1024)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.copyTo(out, bufferSize) extension function in kotlin.io should resolve: \(diagnostics)"
            )
        }
    }

    // MARK: - Default-bufferSize overload (no second argument) resolves

    func testReaderCopyToWithDefaultBufferSizeResolves() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.BufferedWriter
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File): Long {
            val reader: BufferedReader = src.bufferedReader()
            val writer: BufferedWriter = dst.bufferedWriter()
            return reader.copyTo(writer)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.copyTo(out) with default bufferSize should resolve: \(diagnostics)"
            )
        }
    }

    // MARK: - Reader / Writer are registered in java.io

    func testReaderAndWriterTypesAreRegistered() throws {
        let source = """
        import java.io.Reader
        import java.io.Writer

        fun stub(reader: Reader, writer: Writer): Unit {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "java.io.Reader / java.io.Writer should be declared as synthetic class symbols: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            XCTAssertNotNil(symbols.lookup(fqName: ["java", "io", "Reader"].map(interner.intern)))
            XCTAssertNotNil(symbols.lookup(fqName: ["java", "io", "Writer"].map(interner.intern)))
        }
    }

    // MARK: - BufferedReader / BufferedWriter are Reader / Writer subtypes

    func testBufferedReaderAndWriterFlowThroughReaderWriterReceivers() throws {
        // `Reader.copyTo(out: Writer, ...)` must accept BufferedReader / BufferedWriter
        // as receiver / argument because BufferedReader extends Reader and
        // BufferedWriter extends Writer in the JDK class hierarchy.  This test
        // pins that subtype relationship by asking Sema to type-check a call
        // where the receiver / argument are declared as the concrete subtypes.
        let source = """
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File) {
            src.bufferedReader().copyTo(dst.bufferedWriter())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "BufferedReader / BufferedWriter should satisfy the Reader / Writer surface of copyTo: \(diagnostics)"
            )
        }
    }

    // MARK: - External link name is wired through to kk_reader_copyTo

    func testReaderCopyToExternalLinkNameIsRegisteredOnSymbol() throws {
        let source = """
        import java.io.Reader
        import java.io.Writer
        import kotlin.io.copyTo

        fun stub(reader: Reader, writer: Writer): Long = reader.copyTo(writer, 4096)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let readerSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "Reader"].map(interner.intern))
            )
            let writerSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "Writer"].map(interner.intern))
            )
            let readerType = types.make(.classType(ClassType(
                classSymbol: readerSymbol, args: [], nullability: .nonNull
            )))
            let writerType = types.make(.classType(ClassType(
                classSymbol: writerSymbol, args: [], nullability: .nonNull
            )))

            let copyToCandidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "copyTo"].map(interner.intern)
            )

            let twoArg = try XCTUnwrap(copyToCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == readerType
                    && signature.parameterTypes == [writerType, types.intType]
                    && signature.returnType == types.longType
            })
            XCTAssertEqual(symbols.externalLinkName(for: twoArg), "kk_reader_copyTo")

            let twoArgSignature = try XCTUnwrap(symbols.functionSignature(for: twoArg))
            XCTAssertEqual(twoArgSignature.valueParameterHasDefaultValues, [false, true])
            XCTAssertEqual(twoArgSignature.valueParameterIsVararg, [false, false])

            let oneArg = try XCTUnwrap(copyToCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == readerType
                    && signature.parameterTypes == [writerType]
                    && signature.returnType == types.longType
            })
            XCTAssertEqual(symbols.externalLinkName(for: oneArg), "kk_reader_copyTo_default")
        }
    }

    // MARK: - Call site binds to the expected copyTo overload

    func testReaderCopyToCallSiteBindsToRegisteredSymbol() throws {
        let source = """
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File) {
            val reader = src.bufferedReader()
            val writer = dst.bufferedWriter()
            reader.copyTo(writer, 1024)
            reader.copyTo(writer)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            let callExprs = memberCallExprIDs(named: "copyTo", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2, "Expected two copyTo call sites")

            let externalNames: [String?] = callExprs.compactMap { exprID in
                guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                    return nil
                }
                return sema.symbols.externalLinkName(for: chosen)
            }
            XCTAssertTrue(externalNames.contains("kk_reader_copyTo"))
            XCTAssertTrue(externalNames.contains("kk_reader_copyTo_default"))
        }
    }

    // MARK: - Closeable .use {} continues to work after Reader / Writer hoisting

    func testBufferedReaderAndWriterRemainCloseable() throws {
        // STDLIB-IO-FN-014 moves the BufferedReader / BufferedWriter -> Closeable
        // edge through the new Reader / Writer intermediaries.  Make sure the
        // `.use { }` extension still resolves on both.
        let source = """
        import java.io.File

        fun copyAll(src: File, dst: File) {
            src.bufferedReader().use { reader ->
                dst.bufferedWriter().use { writer ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        writer.write(line)
                        writer.newLine()
                    }
                }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "BufferedReader / BufferedWriter must remain Closeable after the Reader/Writer hoist: \(diagnostics)"
            )
        }
    }
}
