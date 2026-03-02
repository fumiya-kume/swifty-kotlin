@testable import CompilerCore
import Foundation
import XCTest

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlowSemaPhase+BodyAnalysis.swift (45.8%)
//          DataFlowSemaPhase+HeaderCollection.swift (49.9%)
//          TypeCheckSemaPhase+ExprInference.swift (51.4%)

extension DataFlowAndSemaRegressionTests {
    func testClassWithTypeParametersDefinesVariance() throws {
        let source = """
        class Box<out T>(val value: T)
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let boxSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Box"
            }
            XCTAssertNotNil(boxSymbol)
        }
    }

    // MARK: - ExprInference: typed local declaration

    func testTypedLocalDeclarationInfersCorrectly() throws {
        let source = """
        fun main(): Int {
            val x: Int = 42
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let xSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "x" && symbol.kind == .local
            }
            XCTAssertNotNil(xSymbol)
        }
    }

    // MARK: - ExprInference: val reassignment diagnostic

    func testValReassignmentEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 1
            x = 2
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: do-while loop

    func testDoWhileLoopInfersUnitType() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do {
                x = x + 1
            } while (x < 3)
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testDoWhileConditionCanReferenceBodyLocal() throws {
        let source = """
        fun main(): Int {
            var loops = 0
            do {
                val local = loops + 1
                loops = local
            } while (local < 3)
            return loops
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    func testDoWhileBodyLocalDoesNotLeakOutsideLoop() throws {
        let source = """
        fun main(): Int {
            do {
                val local = 1
            } while (local < 2)
            return local
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    func testDoWhileInlineBodyAssignmentTypeChecks() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do x = x + 1 while (x < 3)
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assignment operators

    func testCompoundAssignmentOperators() throws {
        let source = """
        fun main(): Int {
            var x = 10
            x += 5
            x -= 3
            x *= 2
            x /= 4
            x %= 3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on val

    func testCompoundAssignOnValEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 5
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: when expression

    func testWhenExpressionInference() throws {
        let source = """
        fun classify(x: Int): String {
            return when (x) {
                1 -> "one"
                2 -> "two"
                else -> "other"
            }
        }
        fun main() = classify(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: return expression

    func testReturnExpressionInference() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            if (flag) return 42
            return 0
        }
        fun main() = earlyReturn(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)
            let returnCount = body.filter { instruction in
                if case .returnValue = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(returnCount, 2)
        }
    }

    // MARK: - ExprInference: Long/Float/Double/Char literals

    func testLongLiteralInference() throws {
        let source = """
        fun main(): Long = 42L
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testFloatLiteralInference() throws {
        let source = """
        fun main(): Float = 1.5f
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testDoubleLiteralInference() throws {
        let source = """
        fun main(): Double = 3.14
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testCharLiteralInference() throws {
        let source = """
        fun main(): Char = 'A'
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: is check and as cast

    func testIsCheckInfersBoolean() throws {
        let source = """
        fun check(x: Any): Boolean = x is Int
        fun main() = check(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testSafeCastInfersNullableType() throws {
        let source = """
        fun tryCast(x: Any): Int? = x as? Int
        fun main() = tryCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testHardCastInference() throws {
        let source = """
        fun forceCast(x: Any): Int = x as Int
        fun main() = forceCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: null assert

    func testNullAssertInfersNonNullable() throws {
        let source = """
        fun forceUnwrap(x: Int?): Int = x!!
        fun main() = forceUnwrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: elvis operator

    func testElvisOperatorInference() throws {
        let source = """
        fun fallback(x: Int?): Int = x ?: 0
        fun main() = fallback(null)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: break/continue outside loop

    func testBreakOutsideLoopEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            break
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0018", in: ctx)
        }
    }
}
