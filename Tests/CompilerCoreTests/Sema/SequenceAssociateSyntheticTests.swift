@testable import CompilerCore
import Foundation
import XCTest

final class SequenceAssociateSyntheticTests: XCTestCase {
    func testSequenceAssociateResolvesInCallExpressions() throws {
        let source = """
        fun buildMap(): Map<Int, Int> {
            return sequenceOf(1, 2, 3).associate { value ->
                (value % 2) to (value * 10)
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
                "Expected Sequence.associate surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "associate"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_associate"))
        }
    }
}
