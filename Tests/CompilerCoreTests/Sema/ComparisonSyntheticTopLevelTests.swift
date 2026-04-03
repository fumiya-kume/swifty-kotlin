@testable import CompilerCore
import Foundation
import XCTest

final class ComparisonSyntheticTopLevelTests: XCTestCase {
    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

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

    func testCompareByAndCompareByDescendingResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample() {
            val ascending = compareBy<Int> { it % 10 }
            val descending = compareByDescending<Int> { it % 10 }
            println(listOf(231, 114, 123).sortedWith(ascending))
            println(listOf(231, 114, 123).sortedWith(descending))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for (name, expectedLink) in [
                ("compareBy", "kk_comparator_from_selector"),
                ("compareByDescending", "kk_comparator_from_selector_descending"),
            ] {
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

                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
                XCTAssertEqual(
                    symbol.fqName.map { interner.resolve($0) },
                    ["kotlin", "comparisons", name],
                    "Expected \(name) to resolve to kotlin.comparisons.\(name)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLink,
                    "Expected \(name) to link to \(expectedLink)"
                )
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

    func testRemainingMaxOfOverloadsResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample() {
            val generic2 = maxOf("b", "a")
            val genericVararg = maxOf("d", "b", "a", "c")
            val comparator3 = maxOf(1, 2, reverseOrder<Int>())
            val comparatorVararg = maxOf(1, 4, 2, 3, reverseOrder<Int>())
            val unsigned2 = maxOf(1u, 4000000000u)
            val unsigned3 = maxOf(1u, 3u, 4000000000u)
            println(generic2)
            println(genericVararg)
            println(comparator3)
            println(comparatorVararg)
            println(unsigned2)
            println(unsigned3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                (2, sema.types.stringType),
                (4, sema.types.stringType),
                (3, sema.types.intType),
                (5, sema.types.intType),
                (2, sema.types.uintType),
                (3, sema.types.uintType),
            ]

            for expected in expectedCases {
                let callExpr = try XCTUnwrap(
                    firstExprID(in: ast) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == "maxOf"
                            && args.count == expected.argCount
                            && sema.bindings.exprTypes[exprID] == expected.returnType
                    },
                    "Expected maxOf(\(expected.argCount) args) to resolve"
                )
                XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], expected.returnType)
            }
        }
    }
}
