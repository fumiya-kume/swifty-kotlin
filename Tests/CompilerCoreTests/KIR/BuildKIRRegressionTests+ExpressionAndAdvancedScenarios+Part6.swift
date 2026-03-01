@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testNestedLocalFunctionScopeResolution() throws {
        let source = """
        fun outer(): Int {
            fun middle(): Int {
                fun inner(): Int = 7
                return inner()
            }
            return middle()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local functions should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // outer, middle, inner, main => at least 4 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 4)
        }
    }

    func testLocalFunctionWithBlockBodyKIRGeneration() throws {
        let source = """
        fun main(): Int {
            fun compute(x: Int): Int {
                val doubled = x * 2
                return doubled + 1
            }
            return compute(10)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Local function with block body: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            XCTAssertGreaterThanOrEqual(module.functionCount, 2)
        }
    }

    func testLocalFunctionCalledMultipleTimes() throws {
        let source = """
        fun main(): Int {
            fun square(n: Int): Int = n * n
            val a = square(3)
            val b = square(4)
            return a + b
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Multiple calls to local function: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testLocalFunctionCapturesOuterVal() throws {
        let source = """
        fun main(): Int {
            val outer = 10
            fun addOuter(x: Int): Int = x + outer
            return addOuter(5)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Local function capturing outer val should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try XCTUnwrap(ctx.kir)
            XCTAssertGreaterThanOrEqual(module.functionCount, 2)
        }
    }

    func testNestedLocalFunctionCaptureFromParentScope() throws {
        let source = """
        fun outer(): Int {
            fun middle(): Int {
                val x = 5
                fun inner(): Int = x + 1
                return inner()
            }
            return middle()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local function capture should be handled: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // outer, middle, inner, main => at least 4 functions with capture analysis performed correctly
            XCTAssertGreaterThanOrEqual(module.functionCount, 4)
        }
    }

    func testLocalFunctionCapturesMultipleOuterVals() throws {
        let source = """
        fun compute(): Int {
            val a = 10
            val b = 20
            fun sum(): Int = a + b
            return sum()
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Local function capturing multiple outer vals should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // compute, sum, main => at least 3 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 3)
        }
    }

    func testLocalFunctionScopeDoesNotLeakBetweenTopLevelFunctions() throws {
        let source = """
        fun first(): Int {
            fun helper(): Int = 1
            return helper()
        }
        fun second(): Int {
            return helper()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertTrue(
                ctx.diagnostics.hasError,
                "Local function should not be visible outside its defining top-level function: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testNestedLocalFunctionCallForwardsCaptureArguments() throws {
        // Regression test: h() captures g(), and g() captures x.
        // When h's body calls g(), the capture arguments for g (i.e. x)
        // must be forwarded correctly via transitive capture.
        let source = """
        fun main(): Int {
            val x = 10
            fun g(): Int = x
            fun h(): Int = g()
            return h()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local function call with capture forwarding should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // main, g, h => at least 3 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 3, "Expected at least 3 functions (main + g + h)")
        }
    }

    func testNestedLocalFunctionForwardsNonLiteralValCapture() throws {
        // Regression test: g() captures a local val x initialized with a
        // non-literal expression (1 + 2), and h() calls g(). The transitive
        // capture must detect x and the callable info remapping must use the
        // direct outerExprToBodyExpr mapping (not symbol reverse lookup) so
        // non-symbolRef expressions like call results remap correctly.
        let source = """
        fun main(): Int {
            val x = 1 + 2
            fun g(): Int = x
            fun h(): Int = g()
            return h()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local function forwarding non-literal val capture should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // main, g, h => at least 3 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 3, "Expected at least 3 functions (main + g + h)")
        }
    }

    func testNestedLocalFunctionForwardsValueParameterCapture() throws {
        // Regression test: g() captures a value parameter p of the enclosing
        // function, and h() calls g(). The transitive capture must detect p
        // even though it's not in localValuesBySymbol (value parameters use
        // captureValueExpr's .valueParameter fallback path).
        let source = """
        fun main(p: Int): Int {
            fun g(): Int = p
            fun h(): Int = g()
            return h()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local function forwarding value parameter capture should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // main, g, h => at least 3 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 3, "Expected at least 3 functions (main + g + h)")
        }
    }

    func testRecursiveLocalFunctionWithCaptureResolvesCorrectly() throws {
        let source = """
        fun main() {
            val limit = 10
            fun countdown(n: Int): Int {
                if (n <= 0) return limit
                return countdown(n - 1)
            }
            countdown(5)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Recursive local function with capture should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // Should have at least main + countdown
            XCTAssertGreaterThanOrEqual(module.functionCount, 2, "Expected at least 2 functions (main + countdown)")
        }
    }

    func firstExprID(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else {
                continue
            }
            if predicate(exprID, expr) {
                return exprID
            }
        }
        return nil
    }
}
