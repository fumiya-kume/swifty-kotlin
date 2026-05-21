@testable import CompilerCore
import Foundation
import XCTest

final class SequenceAssociateByToSyntheticTests: XCTestCase {
    func testSequenceAssociateByToResolvesInCallExpressions() throws {
        let source = """
        fun fillMap(): MutableMap<Int, String> {
            val dest = mutableMapOf<Int, String>()
            return sequenceOf("a", "bb", "ccc").associateByTo(dest) { value ->
                value.length
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
                "Expected Sequence.associateByTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "associateByTo"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_associateByTo"))
        }
    }
}
