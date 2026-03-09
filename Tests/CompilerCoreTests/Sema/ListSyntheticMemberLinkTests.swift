@testable import CompilerCore
import Foundation
import XCTest

final class ListSyntheticMemberLinkTests: XCTestCase {
    func testListTransformMembersUseRuntimeExternalLinksForParameterReceivers() throws {
        let source = """
        fun render(values: List<Int>) {
            values.take(3)
            values.drop(2)
            values.reversed()
            values.sorted()
            values.distinct()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "take": "kk_list_take",
                "drop": "kk_list_drop",
                "reversed": "kk_list_reversed",
                "sorted": "kk_list_sorted",
                "distinct": "kk_list_distinct",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }
}
