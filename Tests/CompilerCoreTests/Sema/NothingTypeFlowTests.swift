@testable import CompilerCore
import Foundation
import XCTest

final class NothingTypeFlowTests: XCTestCase {
    func testControlFlowTerminalsBindNothingType() throws {
        let source = """
        class E

        fun f(flag: Boolean): Int {
            var x = 0
            while (x < 5) {
                x = x + 1
                if (x == 2) continue
                if (x == 4) break
            }
            if (flag) return x
            throw E()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let returnExprs = exprIDs(in: ast) { expr in
                if case .returnExpr = expr { return true }
                return false
            }
            let breakExprs = exprIDs(in: ast) { expr in
                if case .breakExpr = expr { return true }
                return false
            }
            let continueExprs = exprIDs(in: ast) { expr in
                if case .continueExpr = expr { return true }
                return false
            }
            let throwExprs = exprIDs(in: ast) { expr in
                if case .throwExpr = expr { return true }
                return false
            }

            XCTAssertFalse(returnExprs.isEmpty)
            XCTAssertFalse(breakExprs.isEmpty)
            XCTAssertFalse(continueExprs.isEmpty)
            XCTAssertFalse(throwExprs.isEmpty)

            for exprID in returnExprs + breakExprs + continueExprs + throwExprs {
                XCTAssertEqual(
                    sema.bindings.exprType(for: exprID),
                    sema.types.nothingType,
                    "Expected terminal control-flow expression to be typed as Nothing."
                )
            }
        }
    }

    func testNothingParticipatesAsBottomInIfWhenTryLUB() throws {
        let source = """
        class E

        fun ifCase(flag: Boolean): Int {
            val x: Int = if (flag) 1 else throw E()
            return x
        }

        fun whenCase(flag: Boolean): Int = when (flag) {
            true -> 1
            false -> throw E()
        }

        fun tryCase(flag: Boolean): Int = try {
            if (flag) 1 else throw E()
        } catch (e: E) {
            2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let ifExprIDs = exprIDs(in: ast) { expr in
                if case .ifExpr = expr { return true }
                return false
            }
            let whenExprIDs = exprIDs(in: ast) { expr in
                if case .whenExpr = expr { return true }
                return false
            }
            let tryExprIDs = exprIDs(in: ast) { expr in
                if case .tryExpr = expr { return true }
                return false
            }

            XCTAssertFalse(ifExprIDs.isEmpty)
            XCTAssertFalse(whenExprIDs.isEmpty)
            XCTAssertFalse(tryExprIDs.isEmpty)

            for exprID in ifExprIDs + whenExprIDs + tryExprIDs {
                XCTAssertEqual(
                    sema.bindings.exprType(for: exprID),
                    sema.types.intType,
                    "Expected control-flow merge with Nothing branch to infer Int."
                )
            }

            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        }
    }

    func testNullLiteralUsesNullableNothingAndLubWithIntBecomesNullableInt() throws {
        let source = """
        fun f(): Int? {
            val x = null
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let nullNameRef = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return ctx.interner.resolve(name) == "null"
            })
            XCTAssertEqual(sema.bindings.exprType(for: nullNameRef), sema.types.nullableNothingType)

            let nullableInt = sema.types.makeNullable(sema.types.intType)
            XCTAssertEqual(
                sema.types.lub([sema.types.intType, sema.types.nullableNothingType]),
                nullableInt
            )
            XCTAssertFalse(ctx.diagnostics.hasError)
        }
    }

    func testUnreachableAfterNothingEmitsDiagnostic() throws {
        let source = """
        class E

        fun f(): Int {
            throw E()
            return 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0096", in: ctx)
        }
    }

    private func exprIDs(
        in ast: ASTModule,
        where predicate: (Expr) -> Bool
    ) -> [ExprID] {
        var result: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            if predicate(expr) {
                result.append(exprID)
            }
        }
        return result
    }
}
