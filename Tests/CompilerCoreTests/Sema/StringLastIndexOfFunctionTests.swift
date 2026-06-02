@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-034: Validates that `CharSequence.lastIndexOf` resolves through
/// Sema for the (Char, startIndex, ignoreCase) overload and gets wired to the
/// runtime entry point `kk_string_lastIndexOf_char`. The previously-existing
/// String/String overloads remain wired to `kk_string_lastIndexOf` and
/// `kk_string_lastIndexOf_ignoreCase` respectively.
final class StringLastIndexOfFunctionTests: XCTestCase {
    func testLastIndexOfCharResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findChar(value: CharSequence): Int {
            return value.lastIndexOf('o', 10, false)
        }

        fun findCharIgnoreCase(value: String): Int {
            return value.lastIndexOf('O', 10, true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected CharSequence.lastIndexOf(Char, Int, Boolean) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testLastIndexOfCharLinksToRuntimeEntryPoint() throws {
        let source = """
        fun probe(value: CharSequence): Int {
            return value.lastIndexOf('x', 5, false)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CharSequence.lastIndexOf(Char,...) to resolve cleanly"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "text", "lastIndexOf"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_string_lastIndexOf_char"),
            "Expected CharSequence.lastIndexOf(Char, Int, Boolean) to link to kk_string_lastIndexOf_char, got: \(links)"
        )
        // Existing overloads must continue to be registered.
        XCTAssertTrue(
            links.contains("kk_string_lastIndexOf"),
            "Expected String.lastIndexOf(String) to remain linked to kk_string_lastIndexOf, got: \(links)"
        )
        XCTAssertTrue(
            links.contains("kk_string_lastIndexOf_ignoreCase"),
            "Expected String.lastIndexOf(String, Int, Boolean) to remain linked to kk_string_lastIndexOf_ignoreCase, got: \(links)"
        )
    }

    func testLastIndexOfCharResolvesInCallExpressions() throws {
        let source = """
        fun lastChar(value: CharSequence): Int {
            return value.lastIndexOf('o', 3, true)
        }

        fun stringLastChar(value: String): Int {
            return value.lastIndexOf('A', 2, false)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        var callExprs: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  ctx.interner.resolve(callee) == "lastIndexOf"
            else { continue }
            callExprs.append(exprID)
        }
        XCTAssertEqual(callExprs.count, 2)
        for callExpr in callExprs {
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for lastIndexOf"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_lastIndexOf_char",
                "Expected lastIndexOf(Char, Int, Boolean) to resolve to kk_string_lastIndexOf_char"
            )
        }
    }

    func testLastIndexOfCharReturnsInt() throws {
        let source = """
        fun probe(value: CharSequence): Int {
            return value.lastIndexOf('z', 0, false)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected CharSequence.lastIndexOf(Char,...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "lastIndexOf"
        }, "Expected lastIndexOf member call")
        XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.intType)
    }
}
