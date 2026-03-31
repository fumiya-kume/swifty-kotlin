@testable import CompilerCore
import Foundation
import XCTest

final class BigIntegerSyntheticLinkTests: XCTestCase {
    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    func testBigIntegerAndResolvesToSyntheticKotlinExtension() throws {
        let source = """
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            a and b
            a.and(b)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let andCalls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "and"
            }

            XCTAssertEqual(andCalls.count, 2, "Expected both infix and dotted BigInteger.and calls")

            for callExpr in andCalls {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected BigInteger.and to resolve"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_biginteger_and"
                )

                let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                XCTAssertEqual(fqName, ["kotlin", "and"])
            }
        }
    }
}
