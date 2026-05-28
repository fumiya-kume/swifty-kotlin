@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-ENC-FN-001: Validates that
/// `kotlin.io.encoding.InputStream.decodingWith(base64)` resolves through
/// Sema for plain `java.io.InputStream` receivers and yields a
/// `java.io.InputStream` value carrying the decoded bytes.
///
/// The extension is wired through the synthetic Base64 stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticBase64Stubs.swift`
/// and is expected to bind to the runtime helper `kk_input_stream_decodingWith`
/// declared in `Sources/Runtime/RuntimeBase64.swift`.
final class InputStreamDecodingWithFunctionTests: XCTestCase {
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

    // MARK: - Sema resolution

    func testDecodingWithResolvesOnInputStreamReceiver() throws {
        let source = """
        import java.io.InputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.io.encoding.decodingWith

        @OptIn(ExperimentalEncodingApi::class)
        fun openDecoded(stream: InputStream): InputStream {
            return stream.decodingWith(Base64.Default)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "InputStream.decodingWith(Base64.Default) should resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testDecodingWithResolvesWithVariantsAndCustomPadding() throws {
        // Verify decodingWith accepts every Base64 variant and a custom
        // Base64 instance returned by .withPadding(...).
        let source = """
        import java.io.InputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.io.encoding.decodingWith

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeDefault(stream: InputStream): InputStream =
            stream.decodingWith(Base64.Default)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeUrlSafe(stream: InputStream): InputStream =
            stream.decodingWith(Base64.UrlSafe)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeMime(stream: InputStream): InputStream =
            stream.decodingWith(Base64.Mime)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeCustom(stream: InputStream): InputStream {
            val custom: Base64 = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT)
            return stream.decodingWith(custom)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "InputStream.decodingWith should resolve for every Base64 form, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Signature + runtime link wiring

    func testDecodingWithFunctionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let inputStreamSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
            )
            let base64Symbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "encoding", "Base64"].map(interner.intern))
            )
            let inputStreamType = types.make(
                .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
            )
            let base64Type = types.make(
                .classType(ClassType(classSymbol: base64Symbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "encoding", "decodingWith"].map(interner.intern)
            )
            let decodingWith = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == inputStreamType
                    && signature.parameterTypes == [base64Type]
                    && signature.returnType == inputStreamType
            }, "decodingWith function with InputStream receiver + Base64 param must be registered")

            XCTAssertEqual(
                symbols.externalLinkName(for: decodingWith),
                "kk_input_stream_decodingWith",
                "InputStream.decodingWith should bind to runtime helper kk_input_stream_decodingWith"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: decodingWith))
            XCTAssertEqual(signature.receiverType, inputStreamType)
            XCTAssertEqual(signature.parameterTypes, [base64Type])
            XCTAssertEqual(signature.returnType, inputStreamType)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])
            XCTAssertFalse(signature.isSuspend)

            // Verify the function lives in the kotlin.io.encoding package.
            let parent = try XCTUnwrap(symbols.parentSymbol(for: decodingWith))
            let parentInfo = try XCTUnwrap(symbols.symbol(parent))
            XCTAssertEqual(
                parentInfo.fqName.map(interner.resolve),
                ["kotlin", "io", "encoding"],
                "decodingWith must be a top-level extension in kotlin.io.encoding"
            )

            // Verify the single value parameter is named `base64`.
            XCTAssertEqual(signature.valueParameterSymbols.count, 1)
            let paramInfo = try XCTUnwrap(symbols.symbol(signature.valueParameterSymbols[0]))
            XCTAssertEqual(interner.resolve(paramInfo.name), "base64")
        }
    }

    // MARK: - Call-site typing

    func testDecodingWithCallExpressionTypedAsInputStream() throws {
        let source = """
        import java.io.InputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.io.encoding.decodingWith

        @OptIn(ExperimentalEncodingApi::class)
        fun openDecoded(stream: InputStream): InputStream {
            val decoded: InputStream = stream.decodingWith(Base64.Default)
            return decoded
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "InputStream.decodingWith should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let inputStreamSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
            )
            let inputStreamType = types.make(
                .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
            )

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "decodingWith", in: ast, interner: interner)
            XCTAssertFalse(callExprs.isEmpty, "Expected at least one decodingWith call in the AST")
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    inputStreamType,
                    "InputStream.decodingWith call expression must be typed as java.io.InputStream"
                )
            }
        }
    }

    // MARK: - Downstream usability

    func testDecodedInputStreamCanFlowIntoInputStreamSurface() throws {
        // The returned InputStream must remain usable as a standard
        // InputStream (read/available/close/.use { }).  This guards against
        // the registration accidentally producing a wider or narrower type.
        let source = """
        import java.io.InputStream
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.io.encoding.decodingWith

        @OptIn(ExperimentalEncodingApi::class)
        fun consume(source: InputStream): Int {
            val decoded: InputStream = source.decodingWith(Base64.Default)
            val first: Int = decoded.read()
            val rest: Int = decoded.available()
            decoded.close()
            return first + rest
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun consumeWithUse(source: InputStream): Int {
            return source.decodingWith(Base64.Default).use { stream ->
                stream.read()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Decoded InputStream must be usable as a regular InputStream, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
