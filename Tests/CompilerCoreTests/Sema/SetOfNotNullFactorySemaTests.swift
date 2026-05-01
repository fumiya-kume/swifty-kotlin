@testable import CompilerCore
import Foundation
import XCTest

final class SetOfNotNullFactorySemaTests: XCTestCase {
    func testSetOfNotNullInfersNonNullSetElementType() throws {
        let source = """
        fun probe() {
            val values = setOfNotNull("a", null, "b")
            val explicit: Set<String> = setOfNotNull<String>(null, "c")
            val onlyNull = setOfNotNull(null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "setOfNotNull"
            }, "Expected setOfNotNull call in AST")

            XCTAssertTrue(
                sema.bindings.isCollectionExpr(callExpr),
                "Expected setOfNotNull to be marked as a collection expression"
            )

            let type = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
            guard case let .classType(classType) = sema.types.kind(of: type) else {
                return XCTFail("Expected setOfNotNull to infer Set<String>, got \(sema.types.kind(of: type))")
            }
            let symbol = try XCTUnwrap(sema.symbols.symbol(classType.classSymbol))
            XCTAssertEqual(ctx.interner.resolve(symbol.name), "Set")
            XCTAssertEqual(classType.args.count, 1)
            guard case let .out(elementType) = classType.args[0] else {
                return XCTFail("Expected Set element type to use an out projection")
            }
            XCTAssertEqual(elementType, sema.types.stringType)
        }
    }
}
