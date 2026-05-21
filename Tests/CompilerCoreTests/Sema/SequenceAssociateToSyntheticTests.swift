@testable import CompilerCore
import Foundation
import XCTest

final class SequenceAssociateToSyntheticTests: XCTestCase {
    func testSequenceAssociateToResolvesInCallExpressions() throws {
        let source = """
        fun fillMap(): MutableMap<String, Int> {
            val dest = mutableMapOf<String, Int>()
            return sequenceOf("a", "bb", "ccc").associateTo(dest) { value ->
                Pair(value, value.length)
            }
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
                "Expected Sequence.associateTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "associateTo"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_associateTo"))
        }
    }
}
