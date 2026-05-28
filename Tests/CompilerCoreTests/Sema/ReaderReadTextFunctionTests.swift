@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-033: Validates that `kotlin.io.Reader.readText()` resolves
/// through Sema as an extension function on `java.io.Reader`. The synthetic
/// `Reader` supertype lets concrete reader values (currently `BufferedReader`
/// instances produced by `File.bufferedReader()`) participate in the call
/// without explicit upcasting.
///
/// Verifies:
///   1. The synthetic symbol is registered with the correct extension
///      receiver, parameter list, return type, and runtime link name
///      (`kk_reader_readText`).
///   2. The function resolves end-to-end when invoked on a `BufferedReader`
///      value, including the common `File("...").bufferedReader().readText()`
///      chain and inside a `use { }` block.
final class ReaderReadTextFunctionTests: XCTestCase {

    // MARK: - Symbol surface

    func testReaderReadTextFunctionIsRegisteredOnReaderReceiver() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Sema should succeed on a trivial program: " +
                    "\(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let sema = try XCTUnwrap(ctx.sema)

            let readerFQ = ["java", "io", "Reader"].map { ctx.interner.intern($0) }
            let readerSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: readerFQ),
                "java.io.Reader synthetic class should be registered"
            )
            let readerType = sema.types.make(.classType(ClassType(
                classSymbol: readerSymbol, args: [], nullability: .nonNull
            )))

            let readTextFQ = ["kotlin", "io", "readText"].map { ctx.interner.intern($0) }
            let readTextSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: readTextFQ).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == readerType
                        && signature.parameterTypes.isEmpty
                },
                "kotlin.io.Reader.readText() extension should be registered"
            )

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: readTextSymbol))
            XCTAssertEqual(
                signature.returnType,
                sema.types.stringType,
                "Reader.readText() must return non-null String"
            )
            XCTAssertFalse(
                signature.isSuspend,
                "Reader.readText() is not a suspend function"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: readTextSymbol),
                "kk_reader_readText",
                "Reader.readText() must lower to kk_reader_readText runtime entry"
            )
        }
    }

    // MARK: - BufferedReader inherits from Reader

    func testBufferedReaderIsRegisteredAsReaderSubtype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            let readerFQ = ["java", "io", "Reader"].map { ctx.interner.intern($0) }
            let bufferedReaderFQ = ["java", "io", "BufferedReader"].map { ctx.interner.intern($0) }
            let readerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: readerFQ))
            let bufferedReaderSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: bufferedReaderFQ))
            let directSupertypes = sema.symbols.directSupertypes(for: bufferedReaderSymbol)
            XCTAssertTrue(
                directSupertypes.contains(readerSymbol),
                "BufferedReader must list Reader among its direct supertypes; got: \(directSupertypes)"
            )
        }
    }

    // MARK: - Resolves end-to-end on BufferedReader chain

    func testReaderReadTextResolvesOnBufferedReaderChain() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(): String {
            return File("/dev/null").bufferedReader().readText()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "File(...).bufferedReader().readText() should type-check, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testReaderReadTextReturnsStringInVariableBinding() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(file: File): String {
            val reader = file.bufferedReader()
            val text: String = reader.readText()
            reader.close()
            return text
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Binding `val text: String = reader.readText()` should compile, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Works inside Closeable.use { } block

    func testReaderReadTextWorksInsideUseBlock() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAllSafely(file: File): String {
            return file.bufferedReader().use { reader ->
                reader.readText()
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Reader.readText() inside a use { } block should compile, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
