@testable import CompilerCore
import Foundation
import XCTest

final class ReadWriteLockSyntheticLinkTests: XCTestCase {
    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    func testReadResolvesToSyntheticKotlinConcurrentExtension() throws {
        let source = """
        import java.util.concurrent.locks.ReentrantReadWriteLock
        import kotlin.concurrent.read

        fun main(lock: ReentrantReadWriteLock): Int {
            return lock.read { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected read() sample to resolve without diagnostics.")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let readCalls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "read"
            }

            XCTAssertEqual(readCalls.count, 1, "Expected a single ReentrantReadWriteLock.read call.")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: readCalls[0])?.chosenCallee,
                "Expected ReentrantReadWriteLock.read to resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_reentrant_read_write_lock_read"
            )

            let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
            XCTAssertEqual(fqName, ["kotlin", "concurrent", "read"])
        }
    }
}
