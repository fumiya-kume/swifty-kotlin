@testable import CompilerCore
import XCTest

final class ExperimentalBitwiseFunctionTests: XCTestCase {
    func testByteAndShortBitwiseFunctionsResolveThroughKotlinExperimentalImports() throws {
        let source = """
        import kotlin.experimental.and
        import kotlin.experimental.inv
        import kotlin.experimental.or
        import kotlin.experimental.xor

        fun byteOps(a: Byte, b: Byte) {
            a.and(b)
            a.inv()
            a.or(b)
            a.xor(b)
        }

        fun shortOps(a: Short, b: Short) {
            a.and(b)
            a.inv()
            a.or(b)
            a.xor(b)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertTrue(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected kotlin.experimental Byte/Short bitwise imports to resolve cleanly, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let bitwiseNames: Set<String> = ["and", "inv", "or", "xor"]
        var seenCalls: [String: Int] = [:]

        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(receiver, callee, _, args, _) = ast.arena.expr(exprID) else {
                continue
            }
            let name = ctx.interner.resolve(callee)
            guard bitwiseNames.contains(name) else {
                continue
            }

            seenCalls[name, default: 0] += 1
            XCTAssertEqual(sema.bindings.exprTypes[receiver], sema.types.intType)
            XCTAssertEqual(sema.bindings.exprTypes[exprID], sema.types.intType)
            for arg in args {
                XCTAssertEqual(sema.bindings.exprTypes[arg.expr], sema.types.intType)
            }
        }

        XCTAssertEqual(seenCalls, ["and": 2, "inv": 2, "or": 2, "xor": 2])
    }
}
