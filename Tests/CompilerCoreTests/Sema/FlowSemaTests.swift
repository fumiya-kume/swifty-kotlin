@testable import CompilerCore
import Foundation
import XCTest

final class FlowSemaTests: XCTestCase {
    func testFlowBuilderAndChainTypeChecks() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map { it * 2 }
                    .collect { println(it) }
            }
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

    func testRunBlockingLambdaAvoidsTypeConstraintFailure() throws {
        let source = """
        fun main() {
            runBlocking {
                println(1)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testFlowMapCallableReferenceDoesNotOverConstrain() throws {
        let source = """
        fun twice(x: Int): Int = x * 2

        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map(::twice)
                    .collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testFlowStoredInLocalVariableKeepsFlowReceiverTyping() throws {
        let source = """
        fun main() {
            runBlocking {
                val stream = flow {
                    emit(1)
                    emit(2)
                }.map { it * 2 }
                stream.collect { println(it) }
                stream.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testFlowFallbackDoesNotApplyToArbitraryAnyReceiver() throws {
        let source = """
        fun main() {
            val value: Any = 1
            value.map { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.contains(where: { ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code) }),
                "Expected unresolved member diagnostic for non-flow Any receiver. Got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
        }
    }

    func testUserDefinedFlowFunctionShadowsBuiltinFlowFallback() throws {
        let source = """
        fun flow(block: () -> Int): Int = block()

        fun main() {
            val x: Int = flow { 1 }
            println(x)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    // MARK: - TYPE-113: Flow<T> type preservation tests

    func testFlowBuilderExprTypeIsFlowClassType() throws {
        let source = """
        fun main() {
            runBlocking {
                val f = flow { emit(1) }
                f.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            // Find the flow expression and verify its type is Flow<...> (a classType),
            // not Any.
            let flowExprs = sema.bindings.flowExprIDs
            XCTAssertFalse(flowExprs.isEmpty, "Should have at least one flow expression")

            for flowExpr in flowExprs {
                guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                // The expression type should NOT be anyType or nullableAnyType
                XCTAssertNotEqual(exprType, sema.types.anyType,
                    "Flow expression type should not be erased to Any")
                XCTAssertNotEqual(exprType, sema.types.nullableAnyType,
                    "Flow expression type should not be erased to Any?")
                // It should be a classType (Flow<...>)
                if case .classType(let classType) = sema.types.kind(of: exprType) {
                    let symbol = sema.symbols.symbol(classType.classSymbol)
                    let name = symbol.map { ctx.interner.resolve($0.name) }
                    XCTAssertEqual(name, "Flow", "Flow expression should have Flow class type")
                    XCTAssertFalse(classType.args.isEmpty, "Flow type should have type arguments")
                }
            }
        }
    }

    func testFlowMapResultTypeIsFlowClassType() throws {
        let source = """
        fun main() {
            runBlocking {
                val mapped = flow { emit(1) }.map { it * 2 }
                mapped.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            // The map result should also be a flow expression with a non-Any type
            let flowExprs = sema.bindings.flowExprIDs
            XCTAssertGreaterThanOrEqual(flowExprs.count, 2,
                "Should have flow builder + map as flow expressions")

            for flowExpr in flowExprs {
                guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                XCTAssertNotEqual(exprType, sema.types.anyType,
                    "Flow chain result should not be erased to Any")
            }
        }
    }

    func testFlowFilterPreservesElementType() throws {
        let source = """
        fun main() {
            runBlocking {
                val f = flow { emit(1); emit(2) }.filter { it > 1 }
                f.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let flowExprs = sema.bindings.flowExprIDs
            XCTAssertGreaterThanOrEqual(flowExprs.count, 2,
                "Should have flow builder + filter as flow expressions")
            // At least one flow expression (the filter result) should track element type
            let exprsWithElementType = flowExprs.filter { sema.bindings.flowElementType(forExpr: $0) != nil }
            XCTAssertFalse(exprsWithElementType.isEmpty,
                "At least one flow expression should track element type after filter")
        }
    }

    func testFlowTakeResultTypeIsFlowClassType() throws {
        let source = """
        fun main() {
            runBlocking {
                val taken = flow { emit(1); emit(2); emit(3) }.take(2)
                taken.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let flowExprs = sema.bindings.flowExprIDs
            for flowExpr in flowExprs {
                guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                XCTAssertNotEqual(exprType, sema.types.anyType,
                    "Flow.take() result should not be erased to Any")
            }
        }
    }

    func testUserDefinedEmitInsideFlowBuilderShadowsBuiltinEmitFallback() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    val emit = { x: Int -> x + 1 }
                    val y: Int = emit(1)
                    println(y)
                }.collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }
}
