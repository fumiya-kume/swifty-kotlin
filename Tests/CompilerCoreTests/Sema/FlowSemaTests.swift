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
                ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0024" }),
                "Expected unresolved member diagnostic for non-flow Any receiver."
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
