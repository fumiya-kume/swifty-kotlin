@testable import CompilerCore
import Foundation
import XCTest

final class IterableFirstNotNullOfOrNullSemaTests: XCTestCase {
    func testIterableFirstNotNullOfOrNullResolvesToRuntimeABIAndNullableResult() throws {
        let source = """
        fun probe(values: Iterable<Int>) {
            val result: String? = values.firstNotNullOfOrNull { if (it > 1) "hit" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected firstNotNullOfOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOfOrNull"
            }, "Expected firstNotNullOfOrNull member call")
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

            XCTAssertEqual(sema.symbols.externalLinkName(for: chosen), "kk_iterable_firstNotNullOfOrNull")
            XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.makeNullable(sema.types.stringType))
        }
    }
}
