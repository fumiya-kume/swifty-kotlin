@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-044: Validates that `Sequence<T>.forEach` resolves through Sema
/// for the `kotlin.sequences.Sequence` receiver wired through the standard HOF
/// infrastructure. The lambda receives the element and returns `Unit`; the call
/// itself is typed as `Unit` and is linked to the runtime symbol
/// `kk_sequence_forEach`.
final class SequenceForEachFunctionTests: XCTestCase {
    func testSequenceForEachResolvesToRuntimeABIAndUnitResult() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            var sum = 0
            values.forEach { sum += it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected forEach to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "forEach"
            }, "Expected forEach member call")
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "forEach",
            ].map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_forEach" },
                "Expected Sequence.forEach synthetic member to link to kk_sequence_forEach"
            )
            XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.unitType)
        }
    }
}
