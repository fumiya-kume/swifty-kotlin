@testable import CompilerCore
import Foundation
import XCTest

final class IntConversionMemberCallTests: XCTestCase {
    func testIntConversionCallsInferRuntimeFriendlyTypes() throws {
        let source = """
        fun sample(x: Int) {
            x.toFloat()
            x.toByte()
            x.toShort()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedTypes: [String: TypeID] = [
                "toFloat": sema.types.floatType,
                "toByte": sema.types.intType,
                "toShort": sema.types.intType,
            ]

            for memberName in expectedTypes.keys {
                let callExpr = try XCTUnwrap(
                    firstExprID(in: ast) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else {
                            return false
                        }
                        return ctx.interner.resolve(callee) == memberName
                    },
                    "Expected a call expression for \(memberName)"
                )
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    expectedTypes[memberName],
                    "\(memberName) should infer expected return type"
                )
            }
        }
    }

    func testLongAndDoubleToIntNarrowingConversionInfersIntType() throws {
        let source = """
        fun sample(l: Long, d: Double) {
            l.toInt()
            d.toInt()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            var toIntCallExprIDs: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .memberCall(_, callee, _, _, _) = expr else { continue }
                if ctx.interner.resolve(callee) == "toInt" {
                    toIntCallExprIDs.append(exprID)
                }
            }
            XCTAssertEqual(toIntCallExprIDs.count, 2, "Expected two toInt() calls")
            for exprID in toIntCallExprIDs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[exprID],
                    sema.types.intType,
                    "Long.toInt() and Double.toInt() should infer Int return type"
                )
            }
        }
    }
}
