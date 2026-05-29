@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-011: Validates that `String.concat(str)` resolves through
/// Sema for plain String receivers as well as literal / expression contexts.
/// The runtime link involved is `kk_string_concat`.
final class StringConcatFunctionTests: XCTestCase {
    func testStringConcatResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun concatTwo(a: String, b: String): String {
            return a.concat(b)
        }

        fun concatLiteral(): String {
            return "Hello".concat(" World")
        }

        fun concatEmpty(s: String): String {
            return s.concat("")
        }

        fun concatChained(a: String, b: String, c: String): String {
            return a.concat(b).concat(c)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.concat(str) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testStringConcatResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "concat"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes == [sema.types.stringType]
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.concat(str) should return String"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_concat")
    }

    func testStringConcatCallBindingResolvesToRuntimeLink() throws {
        let source = """
        fun joinWords(a: String, b: String): String {
            return a.concat(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "concat"
            }, "Expected a member call to concat in the AST")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected a call binding for the concat invocation"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_concat",
                "String.concat(str) member call must resolve to kk_string_concat"
            )
        }
    }
}
