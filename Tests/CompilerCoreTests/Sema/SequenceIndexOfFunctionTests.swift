@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-048: `kotlin.sequences.Sequence<T>.indexOf`
///
/// Verifies that `Sequence.indexOf(element)` resolves through Sema's synthetic
/// Sequence-member surface and links to the `kk_sequence_indexOf` runtime
/// function. The runtime implementation is exercised separately in
/// `RuntimeSequenceTests`.
final class SequenceIndexOfFunctionTests: XCTestCase {
    func testSequenceIndexOfOnIntSequenceResolvesToRuntimeABI() throws {
        let source = """
        fun findIndex(): Int {
            return sequenceOf(10, 20, 30, 20).indexOf(20)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.indexOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indexOf"
            }, "Expected indexOf member call")

            let memberFQName = ["kotlin", "sequences", "Sequence", "indexOf"]
                .map(ctx.interner.intern)
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains("kk_sequence_indexOf"),
                "Expected Sequence.indexOf synthetic member to link to kk_sequence_indexOf, " +
                    "got \(links.sorted())"
            )
            XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.intType)
        }
    }

    func testSequenceIndexOfOnStringSequenceResolvesCleanly() throws {
        try assertSequenceMemberResolves(
            source: """
            fun firstHit(): Int {
                val words = sequenceOf("alpha", "beta", "alpha")
                return words.indexOf("alpha")
            }
            """,
            memberName: "indexOf",
            expectedLinkName: "kk_sequence_indexOf",
            diagnosticContext: "Sequence.indexOf"
        )
    }
}
