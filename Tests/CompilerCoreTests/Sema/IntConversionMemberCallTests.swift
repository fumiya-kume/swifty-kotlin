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
}
