@testable import CompilerCore
import Foundation
import XCTest

final class GroupingSyntheticMemberLinkTests: XCTestCase {
    func testGroupingAggregateMembersUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let expectedExternalLinks = [
                "aggregate": "kk_grouping_aggregate",
                "aggregateTo": "kk_grouping_aggregateTo",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("Grouping"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic Grouping member \(memberName) to be registered"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testGroupingAggregateCallsUseRuntimeExternalLinks() throws {
        let source = """
        fun render(values: List<Int>) {
            val grouping = values.groupingBy { it % 2 }
            val aggregated: Map<Int, Int> = grouping.aggregate { key, accumulator, element, first ->
                if (first) key + element else accumulator!! + element
            }
            val destination: MutableMap<Int, Int> = mutableMapOf(1 to 100)
            grouping.aggregateTo(destination) { key, accumulator, element, first ->
                if (first) key + element else accumulator!! + element
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let aggregateCallExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "aggregate"
            })
            let aggregateChosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: aggregateCallExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: aggregateChosenCallee),
                "kk_grouping_aggregate",
                "Expected Grouping.aggregate to resolve to kk_grouping_aggregate"
            )

            let aggregateToCallExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "aggregateTo"
            })
            let aggregateToChosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: aggregateToCallExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: aggregateToChosenCallee),
                "kk_grouping_aggregateTo",
                "Expected Grouping.aggregateTo to resolve to kk_grouping_aggregateTo"
            )
        }
    }
}
