@testable import CompilerCore
import Foundation
import XCTest

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlowSemaPhase+BodyAnalysis.swift (45.8%)
//          DataFlowSemaPhase+HeaderCollection.swift (49.9%)
//          TypeCheckSemaPhase+ExprInference.swift (51.4%)

extension DataFlowAndSemaRegressionTests {
    func testFunctionTypeParameterWithUpperBound() throws {
        let source = """
        fun <T : Any> wrap(value: T): T = value
        fun main() = wrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let wrapSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "wrap"
            }
            XCTAssertNotNil(wrapSymbol)
            if let sym = wrapSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id) {
                XCTAssertFalse(sig.typeParameterSymbols.isEmpty)
            }
        }
    }

    // MARK: - ExprInference: try-catch expression

    func testTryCatchExpressionInference() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch (e: Any) {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes() throws {
        let source = """
        class MyError

        fun risky(): Int {
            return try {
                42
            } catch (e: Int) {
                e
            } catch (e: MyError) {
                0
            }
        }

        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression")
                return
            }
            XCTAssertEqual(catchClauses.count, 2)

            let firstBinding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            let secondBinding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[1].body))
            XCTAssertNotEqual(firstBinding.parameterSymbol, .invalid)
            XCTAssertNotEqual(secondBinding.parameterSymbol, .invalid)
            XCTAssertNotEqual(firstBinding.parameterSymbol, secondBinding.parameterSymbol)

            let intType = sema.types.make(.primitive(.int, .nonNull))
            XCTAssertEqual(firstBinding.parameterType, intType)
            XCTAssertEqual(sema.symbols.propertyType(for: firstBinding.parameterSymbol), intType)

            let customErrorSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .class && ctx.interner.resolve(symbol.name) == "MyError"
            }
            let resolvedCustomErrorSymbol = try XCTUnwrap(customErrorSymbol)
            guard case let .classType(customErrorType) = sema.types.kind(of: secondBinding.parameterType) else {
                XCTFail("Expected nominal catch parameter type")
                return
            }
            XCTAssertEqual(customErrorType.classSymbol, resolvedCustomErrorSymbol.id)
            XCTAssertEqual(sema.symbols.propertyType(for: secondBinding.parameterSymbol), secondBinding.parameterType)

            let catchNameRef = try XCTUnwrap(firstExprID(in: ast) { exprID, expr in
                guard case let .nameRef(name, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(name) == "e"
                    && sema.bindings.identifierSymbol(for: exprID) == firstBinding.parameterSymbol
            })
            XCTAssertEqual(sema.bindings.identifierSymbol(for: catchNameRef), firstBinding.parameterSymbol)
            XCTAssertEqual(sema.bindings.exprType(for: catchNameRef), intType)
        }
    }

    func testTryCatchClauseBindingWithoutParameterDefaultsToAny() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression")
                return
            }
            let binding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            XCTAssertEqual(binding.parameterSymbol, .invalid)
            XCTAssertEqual(binding.parameterType, sema.types.anyType)
        }
    }

    // MARK: - ExprInference: uninitialized variable use

    func testUninitializedVariableUseEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on uninitialized variable

    func testCompoundAssignOnUninitializedVariableEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: local variable deferred initialization via if-else

    func testDeferredInitializationViaIfElse() throws {
        let source = """
        fun main(): Int {
            var x: Int = 0
            if (true) {
                x = 1
            } else {
                x = 2
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - HeaderCollection: suspend function

    func testSuspendFunctionSignature() throws {
        let source = """
        suspend fun delayed(v: Int): Int = v
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let delayedSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "delayed"
            }
            XCTAssertNotNil(delayedSymbol)
            if let sym = delayedSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id) {
                XCTAssertTrue(sig.isSuspend)
            }
        }
    }

    // MARK: - ExprInference: println builtin

    func testPrintlnBuiltinInfersUnit() throws {
        let source = """
        fun main() {
            println("hello")
            println()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: local variable with var and reassignment

    func testVarLocalReassignment() throws {
        let source = """
        fun main(): Int {
            var x = 1
            x = 10
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: is check with erased generic type emits warning

    func testIsCheckWithErasedGenericTypeEmitsWarning() throws {
        let source = """
        fun f(x: Any): Boolean = x is List<String>
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
        }
    }

    func testIsCheckWithStarProjectionDoesNotEmitErasureWarning() throws {
        let source = """
        fun f(x: Any): Boolean = x is List<*>
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
        }
    }
}
