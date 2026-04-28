@testable import CompilerCore
import Foundation
import XCTest

/// Sema-level overload resolution tests for Comparator composition APIs (STDLIB-COMP-002).
/// Covers: compareBy { } single-selector, compareBy(selector1, selector2, ...) multi-selector,
/// thenBy / thenByDescending chained on Comparator, Comparator.reversed(),
/// naturalOrder() / reverseOrder(), nullsFirst() / nullsLast() wrapping.
final class ComparatorOverloadResolutionTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - compareBy { } single-selector overload

    func testCompareByLambdaOverloadSelectsPrimitiveVariant() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it * 2 }
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            }, "Expected a call to compareBy")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected overload resolution to produce a chosen callee for compareBy { }"
            )
            let link = sema.symbols.externalLinkName(for: chosenCallee)
            XCTAssertTrue(
                link == "kk_comparator_from_selector_primitive" || link == "kk_comparator_from_selector",
                "Expected compareBy<Int> { } to link to a selector-based comparator runtime, got: \(link ?? "nil")"
            )
        }
    }

    func testCompareByLambdaProducesComparatorReturnType() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }
            listOf("banana", "apple").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            })

            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                XCTFail("Expected compareBy result to be a class type (Comparator<T>)")
                return
            }
            let symbol = try XCTUnwrap(sema.symbols.symbol(ct.classSymbol))
            XCTAssertEqual(
                symbol.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "Comparator"],
                "Expected compareBy { } to return kotlin.Comparator<T>"
            )
        }
    }

    // MARK: - compareBy(selector1, selector2, ...) multi-selector varargs

    func testCompareByTwoSelectorsResolvesToMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String>({ it.length }, { it })
            listOf("banana", "apple", "fig").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 2
                }.first,
                "Expected 2-selector compareBy call"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected overload resolution to produce a chosen callee for compareBy(s1, s2)"
            )
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertEqual(sig.parameterTypes.count, 2, "Expected 2-param signature for 2-selector compareBy")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_multi_selectors",
                "Expected 2-selector compareBy to link to kk_comparator_from_multi_selectors"
            )
        }
    }

    func testCompareByThreeSelectorsResolvesToMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String>({ it.length }, { it.first() }, { it.last() })
            listOf("banana", "apple", "fig").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 3
                }.first,
                "Expected 3-selector compareBy call"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected overload resolution to produce a chosen callee for compareBy(s1, s2, s3)"
            )
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertEqual(sig.parameterTypes.count, 3, "Expected 3-param signature for 3-selector compareBy")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_multi_selectors3",
                "Expected 3-selector compareBy to link to kk_comparator_from_multi_selectors3"
            )
        }
    }

    func testCompareByFourSelectorsResolvesToVarargMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it })
            listOf(231, 132, 121, 221).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 4
                }.first,
                "Expected 4-selector compareBy call"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected overload resolution to produce a chosen callee for compareBy(vararg selectors)"
            )
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertEqual(sig.parameterTypes.count, 1, "Expected single vararg parameter for 4-selector compareBy")
            XCTAssertEqual(sig.valueParameterIsVararg, [true])
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_multi_selectors_vararg",
                "Expected 4-selector compareBy to link to kk_comparator_from_multi_selectors_vararg"
            )
        }
    }

    func testComparatorThenChainedOnCompareByResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it % 10 }.then(compareBy { -it })
            listOf(11, 21, 12, 22).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "then"
            }, "Expected a then(comparator) member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected then(comparator) to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_comparator",
                "Expected then(comparator) to link to kk_comparator_then_comparator"
            )
        }
    }

    // MARK: - thenBy { } chained

    func testThenByIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparator"),
                    ctx.interner.intern("thenBy"),
                ]),
                "Expected synthetic Comparator.thenBy to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_then_by",
                "Expected Comparator.thenBy to map to kk_comparator_then_by"
            )
        }
    }

    func testThenByChainedOnCompareByResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }.thenBy { it }
            listOf("banana", "apple").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenBy"
            }, "Expected a thenBy member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected thenBy to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_by",
                "Expected thenBy to link to kk_comparator_then_by"
            )
        }
    }

    // MARK: - thenByDescending { } chained

    func testThenByDescendingIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparator"),
                    ctx.interner.intern("thenByDescending"),
                ]),
                "Expected synthetic Comparator.thenByDescending to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_then_by_descending",
                "Expected Comparator.thenByDescending to map to kk_comparator_then_by_descending"
            )
        }
    }

    func testThenByDescendingChainedOnCompareByResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }.thenByDescending { it }
            listOf("banana", "apple").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenByDescending"
            }, "Expected a thenByDescending member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected thenByDescending to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_then_by_descending",
                "Expected thenByDescending to link to kk_comparator_then_by_descending"
            )
        }
    }

    func testThenByDescendingReturnTypeIsComparator() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it % 10 }.thenByDescending { it / 10 }
            listOf(231, 114, 123).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenByDescending"
            })

            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                XCTFail("Expected thenByDescending result to be Comparator<T>")
                return
            }
            let symbol = try XCTUnwrap(sema.symbols.symbol(ct.classSymbol))
            XCTAssertEqual(
                symbol.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "Comparator"],
                "Expected thenByDescending to return kotlin.Comparator<T>"
            )
        }
    }

    // MARK: - Comparator.reversed()

    func testReversedIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparator"),
                    ctx.interner.intern("reversed"),
                ]),
                "Expected synthetic Comparator.reversed to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_reversed",
                "Expected Comparator.reversed to map to kk_comparator_reversed"
            )
        }
    }

    func testReversedCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.reversed()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reversed"
            }, "Expected a reversed member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected reversed() to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_reversed",
                "Expected reversed() to link to kk_comparator_reversed"
            )
        }
    }

    func testReversedReturnTypeIsComparator() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.reversed()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reversed"
            })

            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                XCTFail("Expected reversed() result to be Comparator<T>")
                return
            }
            let symbol = try XCTUnwrap(sema.symbols.symbol(ct.classSymbol))
            XCTAssertEqual(
                symbol.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "Comparator"],
                "Expected reversed() to return kotlin.Comparator<T>"
            )
        }
    }

    // MARK: - naturalOrder() / reverseOrder()

    func testNaturalOrderIsRegisteredAsSyntheticTopLevelFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("comparisons"),
                    ctx.interner.intern("naturalOrder"),
                ]),
                "Expected synthetic naturalOrder to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_natural_order",
                "Expected naturalOrder() to map to kk_comparator_natural_order"
            )
        }
    }

    func testReverseOrderIsRegisteredAsSyntheticTopLevelFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("comparisons"),
                    ctx.interner.intern("reverseOrder"),
                ]),
                "Expected synthetic reverseOrder to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_reverse_order",
                "Expected reverseOrder() to map to kk_comparator_reverse_order"
            )
        }
    }

    func testNaturalOrderCallResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = naturalOrder<Int>()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "naturalOrder"
                }.first,
                "Expected a naturalOrder() call"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected naturalOrder() to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_natural_order",
                "Expected naturalOrder() to link to kk_comparator_natural_order"
            )
        }
    }

    func testReverseOrderCallResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = reverseOrder<Int>()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "reverseOrder"
                }.first,
                "Expected a reverseOrder() call"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected reverseOrder() to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_reverse_order",
                "Expected reverseOrder() to link to kk_comparator_reverse_order"
            )
        }
    }

    func testNaturalOrderSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("naturalOrder"),
            ]))
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(sig.parameterTypes.isEmpty, "Expected naturalOrder() to take no parameters")
        }
    }

    func testReverseOrderSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("reverseOrder"),
            ]))
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(sig.parameterTypes.isEmpty, "Expected reverseOrder() to take no parameters")
        }
    }

    // MARK: - nullsFirst() / nullsLast()

    func testNullsFirstIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparator"),
                    ctx.interner.intern("nullsFirst"),
                ]),
                "Expected synthetic Comparator.nullsFirst to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_nulls_first",
                "Expected Comparator.nullsFirst to map to kk_comparator_nulls_first"
            )
        }
    }

    func testNullsLastIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparator"),
                    ctx.interner.intern("nullsLast"),
                ]),
                "Expected synthetic Comparator.nullsLast to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbolID),
                "kk_comparator_nulls_last",
                "Expected Comparator.nullsLast to map to kk_comparator_nulls_last"
            )
        }
    }

    func testNullsFirstCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.nullsFirst()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "nullsFirst"
            }, "Expected a nullsFirst member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected nullsFirst() to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_nulls_first",
                "Expected nullsFirst() to link to kk_comparator_nulls_first"
            )
        }
    }

    func testNullsLastCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.nullsLast()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "nullsLast"
            }, "Expected a nullsLast member call")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected nullsLast() to resolve to a callee"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_nulls_last",
                "Expected nullsLast() to link to kk_comparator_nulls_last"
            )
        }
    }

    func testNullsFirstSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("Comparator"),
                ctx.interner.intern("nullsFirst"),
            ]))
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(sig.parameterTypes.isEmpty, "Expected nullsFirst() to take no parameters")
        }
    }

    func testNullsLastSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("Comparator"),
                ctx.interner.intern("nullsLast"),
            ]))
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(sig.parameterTypes.isEmpty, "Expected nullsLast() to take no parameters")
        }
    }

    // MARK: - Chained composition: compareBy + thenBy + reversed

    func testChainedCompareByThenByReversedResolvesCleanly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it % 10 }
                .thenBy { it / 10 }
                .reversed()
            listOf(231, 114, 123).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected no diagnostics for chained compareBy.thenBy.reversed(), got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    func testNullsFirstAndNullsLastReturnComparatorType() throws {
        let source = """
        fun sample() {
            val a = compareBy<Int> { it }.nullsFirst()
            val b = compareBy<Int> { it }.nullsLast()
            listOf(3, 1, 2).sortedWith(a)
            listOf(3, 1, 2).sortedWith(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected no diagnostics for nullsFirst/nullsLast usage, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
