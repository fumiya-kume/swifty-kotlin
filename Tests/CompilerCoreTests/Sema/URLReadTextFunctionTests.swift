@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-035: `fun java.net.URL.readText(): String`
///
/// Verifies that the synthetic `readText` member registered on the
/// `java.net.URL` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticURLStubs.swift`)
/// resolves through Sema for plain URL receivers and binds to the runtime
/// helper `kk_url_readText` listed in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
final class URLReadTextFunctionTests: XCTestCase {
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

    // MARK: - readText() resolves cleanly on a URL receiver

    func testURLReadTextResolves() throws {
        let source = """
        import java.net.URL

        fun fetchContent(url: URL): String {
            return url.readText()
        }

        fun main() {
            val url = URL("file:///tmp/test.txt")
            println(fetchContent(url))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "URL.readText() should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - readText() call expression is typed as String

    func testURLReadTextCallExpressionIsTypedAsString() throws {
        let source = """
        import java.net.URL

        fun readContent(url: URL): String {
            val text: String = url.readText()
            return text
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "URL.readText() call expression should type cleanly as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            let callExprs = memberCallExprIDs(named: "readText", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 1, "expected one readText member call")
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    sema.types.stringType,
                    "URL.readText() call expression must be typed as String"
                )
            }
        }
    }

    // MARK: - Sema registers readText with the expected runtime link name

    func testURLReadTextSignatureAndRuntimeLinkName() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let urlSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "net", "URL"].map(interner.intern))
            )
            let urlType = types.make(
                .classType(ClassType(classSymbol: urlSymbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["java", "net", "URL", "readText"].map(interner.intern)
            )

            let readTextSymbol = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == urlType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == types.stringType
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: readTextSymbol),
                "kk_url_readText",
                "URL.readText() should bind to runtime helper kk_url_readText"
            )
        }
    }
}
