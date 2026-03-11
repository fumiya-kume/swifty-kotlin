@testable import CompilerCore
import Foundation
import XCTest

final class ComparisonSyntheticTopLevelTests: XCTestCase {
    func testMaxOfAndMinOfResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample(): Int {
            val hi = maxOf(3, 7)
            val lo = minOf(3, 7)
            return hi - lo
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try XCTUnwrap(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name
                    },
                    "Expected call to \(name)"
                )
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfInt : .minOfInt)
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern(name),
                ])
            }
        }
    }
}
