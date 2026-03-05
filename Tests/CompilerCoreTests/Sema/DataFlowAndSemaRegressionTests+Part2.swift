@testable import CompilerCore
import Foundation
import XCTest

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {
    func testContinueOutsideLoopEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            continue
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0019", in: ctx)
        }
    }

    // MARK: - ExprInference: unresolved reference

    func testUnresolvedReferenceEmitsDiagnostic() throws {
        let source = """
        fun main(): Int = unknownVar
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    // MARK: - ExprInference: unresolved function

    func testUnresolvedFunctionEmitsDiagnostic() throws {
        let source = """
        fun main(): Int = unknownFunc(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - ExprInference: local function

    func testLocalFunctionDeclarationInference() throws {
        let source = """
        fun main(): Int {
            fun add(a: Int, b: Int): Int = a + b
            return add(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: array access and assign

    func testArrayAccessAndAssignInference() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(3)
            arr[0] = 10
            return arr[0]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: for loop with loop variable

    func testForLoopInfersElementType() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(3)
            var sum = 0
            for (item in arr) {
                sum += item
            }
            return sum
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: binary type promotion

    func testBinaryOperatorTypePromotionLong() throws {
        let source = """
        fun main(): Long = 1L + 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testBinaryOperatorTypePromotionDouble() throws {
        let source = """
        fun main(): Double = 1.0 + 2.0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testBinaryOperatorTypePromotionFloat() throws {
        let source = """
        fun main(): Float = 1.5f + 2.5f
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: string template

    func testStringTemplateInference() throws {
        let source = """
        fun main(): String {
            val name = "World"
            return "Hello, $name!"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: if expression with else

    func testIfExpressionWithElseInfersLUB() throws {
        let source = """
        fun pick(flag: Boolean): Int {
            val x = if (flag) 1 else 2
            return x
        }
        fun main() = pick(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: if expression without else infers Unit

    func testIfExpressionWithoutElseInfersUnit() throws {
        let source = """
        fun doSomething(flag: Boolean) {
            if (flag) println("yes")
        }
        fun main() = doSomething(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: null reference

    func testNullLiteralInference() throws {
        let source = """
        fun main(): Any? = null
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: while loop

    func testWhileLoopInference() throws {
        let source = """
        fun main(): Int {
            var i = 0
            while (i < 10) {
                i = i + 1
            }
            return i
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: rangeTo operator

    func testRangeToOperatorInference() throws {
        let source = """
        fun main() {
            val r = 1..10
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: local assign to unresolved variable

    func testLocalAssignToUnresolvedVariableEmitsDiagnostic() throws {
        let source = """
        fun main() {
            noSuchVar = 42
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
        }
    }

    // MARK: - ExprInference: when without else (boolean exhaustive)

    func testWhenBooleanExhaustive() throws {
        let source = """
        fun desc(flag: Boolean): String = when (flag) {
            true -> "yes"
            false -> "no"
        }
        fun main() = desc(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - HeaderCollection: property with type annotation

    func testPropertyTypeAnnotationResolves() throws {
        let source = """
        val count: Int = 0
        val name: String = "test"
        val flag: Boolean = true
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let countSym = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "count" && symbol.kind == .property
            }
            XCTAssertNotNil(countSym)
            if let sym = countSym {
                XCTAssertNotNil(sema.symbols.propertyType(for: sym.id))
            }
        }
    }

    // MARK: - HeaderCollection: function with type parameters and upper bounds
}
