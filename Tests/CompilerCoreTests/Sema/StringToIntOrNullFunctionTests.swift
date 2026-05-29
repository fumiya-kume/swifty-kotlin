@testable import CompilerCore
import Foundation
import XCTest

final class StringToIntOrNullFunctionTests: XCTestCase {
    func testStringToIntOrNullInfersNullableIntType() throws {
        let source = """
        fun probe(text: String) {
            val result: Int? = text.toIntOrNull()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toIntOrNull() to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toIntOrNull"
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.intType)
            )

            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("toIntOrNull"),
            ]
            XCTAssertTrue(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_string_toIntOrNull"
            })
        }
    }

    func testStringToIntOrNullWithRadixInfersNullableIntType() throws {
        let source = """
        fun probe(text: String) {
            val result: Int? = text.toIntOrNull(16)
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toIntOrNull(radix) to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toIntOrNull" && args.count == 1
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.intType)
            )

            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("toIntOrNull"),
            ]
            XCTAssertTrue(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_string_toIntOrNull_radix"
            })
        }
    }

    func testStringToIntOrNullOnLiteralAndElvisFallback() throws {
        let source = """
        fun probe(): Int {
            val parsed: Int? = "42".toIntOrNull()
            return parsed ?: 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toIntOrNull() on a literal to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toIntOrNull"
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.intType)
            )
        }
    }
}
