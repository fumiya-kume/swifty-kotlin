@testable import CompilerCore
import Foundation
import XCTest

final class SequenceFirstNotNullOfOrNullSemaTests: XCTestCase {
    func testSequenceFirstNotNullOfOrNullInfersNullableTransformResult() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val result: String? = values.firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected firstNotNullOfOrNull to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOfOrNull"
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.stringType)
            )

            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("firstNotNullOfOrNull"),
            ]
            XCTAssertTrue(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_firstNotNullOfOrNull"
            })
        }
    }
}
