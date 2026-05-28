@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-067: `kotlin.text.CharSequence.singleOrNull()`
///
/// `singleOrNull()` returns the only character when the receiver has exactly
/// one element, and returns `null` for empty or multi-character receivers. These
/// tests pin the Sema binding to `kk_string_singleOrNull` and the nullable
/// `Char?` return type.
final class StringSingleOrNullFunctionTests: XCTestCase {
    /// Resolve the `kotlin.text.<member>` symbol and return its external link name.
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            if predicate(exprID, expr) {
                results.append(exprID)
            }
        }
        return results
    }

    func testSingleOrNullStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "singleOrNull", sema: sema, interner: interner),
            "kk_string_singleOrNull",
            "CharSequence.singleOrNull should link to kk_string_singleOrNull"
        )
    }

    func testSingleOrNullOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val ch: Char? = "x".singleOrNull()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testSingleOrNullOnEmptyStringResolves() throws {
        // Empty receiver remains type-correct: signature is independent of contents.
        let ctx = makeContextFromSource("""
        fun main() {
            val ch: Char? = "".singleOrNull()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testSingleOrNullOnStringVariableResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val source: String = "kotlin"
            val ch: Char? = source.singleOrNull()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testSingleOrNullReturnTypeIsNullableChar() throws {
        // Assigning to non-nullable Char must fail because singleOrNull returns Char?.
        let ctx = makeContextFromSource("""
        fun main() {
            val ch: Char = "x".singleOrNull()
        }
        """)
        try runSema(ctx)
        XCTAssertTrue(
            ctx.diagnostics.hasError,
            "expected error for assigning Char? to Char, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testSingleOrNullAcceptsNoArguments() throws {
        // Pass an unexpected positional argument; Sema should reject it
        // because the no-predicate overload is the only one currently exposed.
        let ctx = makeContextFromSource("""
        fun main() {
            val ch = "x".singleOrNull(1)
        }
        """)
        try runSema(ctx)
        XCTAssertTrue(
            ctx.diagnostics.hasError,
            "expected error for extra positional argument, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testSingleOrNullResolvesInCallExpression() throws {
        let source = """
        fun firstOnly(value: String): Char? {
            return value.singleOrNull()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "singleOrNull"
            }
            XCTAssertEqual(callExprs.count, 1)
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExprs[0])?.chosenCallee,
                "Expected call binding for singleOrNull"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_singleOrNull",
                "Expected singleOrNull to resolve to kk_string_singleOrNull"
            )
        }
    }
}
