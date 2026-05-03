@testable import CompilerCore
import Foundation
import XCTest

final class SequenceFirstNotNullOfSemaTests: XCTestCase {
    func testSequenceFirstNotNullOfResolvesToRuntimeABIAndNonNullResult() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val result: String = values.firstNotNullOf { if (it > 1) "hit" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected firstNotNullOf to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOf"
            }, "Expected firstNotNullOf member call")
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "firstNotNullOf",
            ].map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_firstNotNullOf" },
                "Expected Sequence.firstNotNullOf synthetic member to link to kk_sequence_firstNotNullOf"
            )
            XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.stringType)
        }
    }
}
