@testable import CompilerCore
import Foundation
import XCTest

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

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
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                XCTAssertFalse(sig.typeParameterSymbols.isEmpty)
            }
        }
    }

    func testReifiedInlineFunctionSupportsUnsafeCastAndBoundedTypeParameter() throws {
        let source = """
        inline fun <reified T> castOrThrow(value: Any): T = value as T
        inline fun <reified T : Comparable<T>> boundedTypeName(): String = T::class.simpleName ?: "unknown"

        fun main() {
            println(castOrThrow<String>("hello"))
            println(boundedTypeName<String>())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            let castSymbol = try XCTUnwrap(sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "castOrThrow"
            })
            let castSignature = try XCTUnwrap(sema.symbols.functionSignature(for: castSymbol.id))
            XCTAssertEqual(castSignature.reifiedTypeParameterIndices, Set([0]))
            XCTAssertEqual(castSignature.typeParameterSymbols.count, 1)

            let boundedSymbol = try XCTUnwrap(sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "boundedTypeName"
            })
            let boundedSignature = try XCTUnwrap(sema.symbols.functionSignature(for: boundedSymbol.id))
            XCTAssertEqual(boundedSignature.reifiedTypeParameterIndices, Set([0]))
            XCTAssertEqual(boundedSignature.typeParameterSymbols.count, 1)

            let boundedTypeParameter = try XCTUnwrap(boundedSignature.typeParameterSymbols.first)
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: boundedTypeParameter)
            XCTAssertEqual(upperBounds.count, 1)
            if let upperBound = upperBounds.first {
                guard case let .classType(classType) = sema.types.kind(of: upperBound) else {
                    XCTFail("Expected Comparable upper bound")
                    return
                }
                let comparableFQName = [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparable"),
                ]
                let comparableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: comparableFQName))
                XCTAssertEqual(classType.classSymbol, comparableSymbol)
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

    func testTryCatchExpressionMatchesCompletionCriteriaExample() throws {
        let source = """
        fun f(): String {
            val x: String = try {
                "ok"
            } catch (e: Exception) {
                "err"
            }
            return x
        }

        fun main() = f()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    func testTryCatchDefiniteInitializationMergesNormalBranches() throws {
        let source = """
        class Handled

        fun f(flag: Boolean): Int {
            var x: Int
            try {
                if (flag) throw Handled()
                x = 1
            } catch (e: Handled) {
                x = 2
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    func testTryPartialCatchRethrowMergesOnlyNormalPaths() throws {
        let source = """
        class Handled
        class Unhandled

        fun f(flag: Boolean): Int {
            var x: Int
            try {
                if (flag) throw Handled() else throw Unhandled()
            } catch (e: Handled) {
                x = 7
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    func testTryFinallyReturnValueDoesNotPolluteTypeInference() throws {
        let source = """
        fun f(): String {
            val x: String = try {
                "ok"
            } finally {
                123
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
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
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
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

    func testStringSplitMarksCollectionForFallbackMembers() throws {
        let source = """
        fun main() {
            val parts = "1,2,3".split(",")
            println(parts.size)
            val mapped = parts.map { it }
            println(mapped.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
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
            assertHasDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: ctx)
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
            assertNoDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: ctx)
        }
    }

    func testIsCheckWithNonReifiedTypeParameterEmitsDiagnostic() throws {
        let source = """
        fun <T> f(x: Any): Boolean = x is T
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0084", in: ctx)
        }
    }

    func testIsCheckWithReifiedTypeParameterDoesNotEmitNonReifiedDiagnostic() throws {
        let source = """
        inline fun <reified T> f(x: Any): Boolean = x is T
        fun main(): Int = if (f<Int>(1)) 1 else 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0084", in: ctx)
        }
    }

    // MARK: - Const property validation

    func testConstValRejectsNullablePrimitiveTypeAnnotation() throws {
        let source = """
        const val maybeInt: Int? = 1
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }

    func testConstValRejectsNullableStringTypeAnnotation() throws {
        let source = """
        const val maybeName: String? = "ok"
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }

    func testConstValAcceptsNonNullableStringTypeAnnotation() throws {
        let source = """
        const val name: String = "ok"
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }
}
