@testable import CompilerCore
import Foundation
import XCTest

/// Verifies that `Set` binary collection members resolve to the expected
/// runtime entry points.
final class SetSyntheticMemberLinkTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "collections", "Set", member].map { interner.intern($0) }
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

    func testSetBinaryMembersUseCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "intersect": "kk_set_intersect",
            "union": "kk_set_union",
            "subtract": "kk_set_subtract",
        ]

        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "Set.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testSetBinaryMembersResolveInCallExpressions() throws {
        let source = """
        fun probe(values: Set<Int>, other: List<Int>) {
            val left = values.intersect(other)
            val middle = values.union(other)
            val right = values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedLinks: [String: String] = [
                "intersect": "kk_set_intersect",
                "union": "kk_set_union",
                "subtract": "kk_set_subtract",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
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
