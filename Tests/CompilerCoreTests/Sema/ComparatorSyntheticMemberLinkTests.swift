@testable import CompilerCore
import Foundation
import XCTest

final class ComparatorSyntheticMemberLinkTests: XCTestCase {
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
}
