@testable import CompilerCore
import Foundation
import XCTest

/// Verifies the STDLIB-IO-FN-011 synthetic stub for `String.byteInputStream(charset)`.
/// Two overloads are exposed from `kotlin.io`:
/// - `String.byteInputStream(): ByteArrayInputStream` → `kk_string_byteInputStream`
/// - `String.byteInputStream(charset: Charset): ByteArrayInputStream` → `kk_string_byteInputStream_charset`
///
/// Both return `java.io.ByteArrayInputStream`, which is registered as an
/// `InputStream` subtype so that resource-management surfaces (`.use {}`) work
/// out of the box.
final class StringByteInputStreamFunctionTests: XCTestCase {
    func testNoArgByteInputStreamResolvesToUtf8Stream() throws {
        let source = """
        fun useDefaultCharset(value: String) = value.byteInputStream()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String.byteInputStream() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            // The call site should bind to the synthetic UTF-8 entry point.
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "byteInputStream"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_byteInputStream"
            )

            // The chosen overload must be the zero-parameter, kotlin.io extension.
            let chosenInfo = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertEqual(
                chosenInfo.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "io", "byteInputStream"]
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
            XCTAssertEqual(signature.receiverType, sema.types.stringType)

            // Return type should be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected byteInputStream() to return a class type")
            }
            let returnInfo = try XCTUnwrap(sema.symbols.symbol(returnClassType.classSymbol))
            XCTAssertEqual(
                returnInfo.fqName.map { ctx.interner.resolve($0) },
                ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    func testCharsetAwareByteInputStreamResolvesToDedicatedEntryPoint() throws {
        let source = """
        import kotlin.text.Charsets

        fun useExplicitCharset(value: String) = value.byteInputStream(Charsets.UTF_16)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String.byteInputStream(charset) to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "byteInputStream"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_byteInputStream_charset"
            )

            // Signature should accept a single Charset parameter.
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .classType(paramClassType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected charset parameter to be a class type")
            }
            let paramInfo = try XCTUnwrap(sema.symbols.symbol(paramClassType.classSymbol))
            XCTAssertEqual(
                paramInfo.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "text", "Charset"]
            )

            // Return type should still be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected byteInputStream(charset) to return a class type")
            }
            let returnInfo = try XCTUnwrap(sema.symbols.symbol(returnClassType.classSymbol))
            XCTAssertEqual(
                returnInfo.fqName.map { ctx.interner.resolve($0) },
                ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    func testByteInputStreamReturnTypeFlowsThroughInputStreamMembers() throws {
        // The returned ByteArrayInputStream inherits from InputStream, so its
        // member surfaces (.read(), .close(), .available()) must resolve, and
        // its Closeable conformance must keep `.use {}` working.
        let source = """
        import java.io.ByteArrayInputStream

        fun consume(value: String): Int {
            val stream: ByteArrayInputStream = value.byteInputStream()
            val available = stream.available()
            val first = stream.read()
            stream.close()
            return available + first
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ByteArrayInputStream member usage to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testByteInputStreamUseClosureResolvesViaCloseableConformance() throws {
        // `.use {}` is registered against Closeable. ByteArrayInputStream → InputStream
        // → Closeable, so the call must type-check without explicit imports.
        let source = """
        fun firstByte(value: String): Int = value.byteInputStream().use { it.read() }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected `.use {}` on byteInputStream() to resolve via Closeable, got: \(diagnosticSummary)"
            )
        }
    }

    func testByteInputStreamSymbolsExistInKotlinIOPackage() throws {
        // Direct symbol lookup as a defense against accidental re-registration
        // under the wrong package (e.g. kotlin.text instead of kotlin.io).
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName = ["kotlin", "io", "byteInputStream"].map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fqName)
            XCTAssertEqual(symbols.count, 2, "Expected exactly two byteInputStream overloads in kotlin.io")

            let externalLinks = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertEqual(
                externalLinks,
                ["kk_string_byteInputStream", "kk_string_byteInputStream_charset"]
            )

            // Both overloads must declare String as their extension receiver.
            for symbolID in symbols {
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.receiverType, sema.types.stringType)
            }
        }
    }
}
