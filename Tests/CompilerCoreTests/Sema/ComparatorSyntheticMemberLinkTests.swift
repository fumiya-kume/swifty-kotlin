@testable import CompilerCore
import Foundation
import XCTest

final class ComparatorSyntheticMemberLinkTests: XCTestCase {
    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    func testComparatorThenComparatorUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenComparator { a, b -> b.compareTo(a) }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenComparator"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_comparator",
                "Expected thenComparator to resolve to kk_comparator_then_comparator"
            )
        }
    }

    func testCompareByDescendingUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareByDescending<Int> { it % 10 }.thenBy { it / 10 }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(allExprIDs(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(callee) else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "compareByDescending"
            }.first)

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_selector_descending",
                "Expected compareByDescending to resolve to kk_comparator_from_selector_descending"
            )
        }
    }

    func testComparatorThenDescendingUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenDescending { a, b -> b.compareTo(a) }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenDescending"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_descending",
                "Expected thenDescending to resolve to kk_comparator_then_descending"
            )
        }
    }

    func testComparatorThenByUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenBy { it / 10 }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenBy"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_by",
                "Expected thenBy to resolve to kk_comparator_then_by"
            )
        }
    }

    func testComparatorCompareMemberResolves() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }
            comparator.compare(13, 24)
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "compare"
            }.first)

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertEqual(
                symbol.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "Comparator", "compare"],
                "Expected Comparator.compare to resolve to the synthetic Comparator member"
            )
        }
    }

    func testComparatorThenComparatorIsRegisteredAsSyntheticMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Comparator"),
                        ctx.interner.intern("thenComparator"),
                    ]
                ),
                "Expected synthetic Comparator.thenComparator to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_then_comparator",
                "Expected Comparator.thenComparator to map to kk_comparator_then_comparator"
            )
        }
    }

    func testComparatorThenDescendingIsRegisteredAsSyntheticMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Comparator"),
                        ctx.interner.intern("thenDescending"),
                    ]
                ),
                "Expected synthetic Comparator.thenDescending to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_then_descending",
                "Expected Comparator.thenDescending to map to kk_comparator_then_descending"
            )
        }
    }
}
