@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-054: Validates that `String.repeat(n)` resolves through
/// Sema for plain String receivers as well as literal / expression contexts.
/// The runtime link involved is `kk_string_repeat`
/// (see `Sources/Runtime/RuntimeStringStdlib.swift`).
final class StringRepeatFunctionTests: XCTestCase {
    func testStringRepeatResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun repeatTwice(s: String): String {
            return s.repeat(2)
        }

        fun repeatLiteral(): String {
            return "ab".repeat(3)
        }

        fun repeatZero(s: String): String {
            return s.repeat(0)
        }

        fun repeatWithExpression(s: String, n: Int): String {
            return s.repeat(n + 1)
        }

        fun repeatInConcatenation(s: String): String {
            return "[" + s.repeat(2) + "]"
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.repeat(n) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testStringRepeatResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "repeat"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes == [sema.types.intType]
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.repeat(n) should return String"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_repeat")
    }

    func testStringRepeatCallBindingResolvesToRuntimeLink() throws {
        let source = """
        fun makeBanner(token: String): String {
            return token.repeat(4)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "repeat"
            }, "Expected a member call to repeat in the AST")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected a call binding for the repeat invocation"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_repeat",
                "String.repeat(n) member call must resolve to kk_string_repeat"
            )
        }
    }
}
