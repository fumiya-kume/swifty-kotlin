@testable import CompilerCore
import Foundation
import XCTest

final class RangeSyntheticMemberLinkTests: XCTestCase {
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

    private func externalLink(
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else {
            return nil
        }
        return sema.symbols.externalLinkName(for: sym)
    }

    func testRangeRandomStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(owner: String, link: String)] = [
            ("IntRange", "kk_range_random"),
            ("LongRange", "kk_long_range_random"),
            ("CharRange", "kk_range_random"),
            ("UIntRange", "kk_uint_range_random"),
            ("ULongRange", "kk_ulong_range_random"),
        ]

        for expectation in expected {
            XCTAssertEqual(
                externalLink(
                    for: expectation.owner,
                    member: "random",
                    sema: sema,
                    interner: interner
                ),
                expectation.link,
                "\(expectation.owner).random should link to \(expectation.link)"
            )
        }
    }

    func testRangeRandomMembersResolveInCallExpressions() throws {
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: IntRange): Int = range.random()
            """,
            expectedLink: "kk_range_random",
            expectedTypeName: "Int"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: LongRange): Long = range.random()
            """,
            expectedLink: "kk_long_range_random",
            expectedTypeName: "Long"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: CharRange): Char = range.random()
            """,
            expectedLink: "kk_range_random",
            expectedTypeName: "Char"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: UIntRange): UInt = range.random()
            """,
            expectedLink: "kk_uint_range_random",
            expectedTypeName: "UInt"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: ULongRange): ULong = range.random()
            """,
            expectedLink: "kk_ulong_range_random",
            expectedTypeName: "ULong"
        )
    }

    private func assertRandomCallLink(
        source: String,
        expectedLink: String,
        expectedTypeName: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(callee) == "random"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), expectedLink)
            let expectedType: TypeID
            switch expectedTypeName {
            case "Int":
                expectedType = sema.types.intType
            case "Long":
                expectedType = sema.types.longType
            case "Char":
                expectedType = sema.types.charType
            case "UInt":
                expectedType = sema.types.uintType
            case "ULong":
                expectedType = sema.types.ulongType
            default:
                XCTFail("Unexpected expected type name: \(expectedTypeName)")
                return
            }
            XCTAssertEqual(
                sema.bindings.exprTypes[callExpr],
                expectedType,
                "Expected random() to return \(expectedTypeName)"
            )
        }
    }
}
