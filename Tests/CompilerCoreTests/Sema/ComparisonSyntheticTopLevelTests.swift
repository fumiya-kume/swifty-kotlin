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

    // STDLIB-614: 3-arg minOf / maxOf overloads
    func testThreeArgMaxOfMinOfResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample(): Int {
            val hi = maxOf(1, 5, 3)
            val lo = minOf(1, 5, 3)
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
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfInt3 : .minOfInt3)
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern(name),
                ])
                // Verify 3-param signature
                let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
                XCTAssertEqual(sig.parameterTypes.count, 3)
            }
        }
    }

    func testThreeArgMaxOfMinOfLongOverload() throws {
        let source = """
        fun sample(): Long {
            val hi = maxOf(1L, 5L, 3L)
            val lo = minOf(1L, 5L, 3L)
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
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.longType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfLong3 : .minOfLong3)
            }
        }
    }

    func testThreeArgMaxOfMinOfDoubleOverload() throws {
        let source = """
        fun sample(): Double {
            val hi = maxOf(1.0, 5.0, 3.0)
            val lo = minOf(1.0, 5.0, 3.0)
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
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfDouble3 : .minOfDouble3)
            }
        }
    }
}
