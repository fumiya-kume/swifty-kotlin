@testable import CompilerCore
import Foundation
import XCTest

extension CompilerCoreTests {
    func testInvokeOperatorResolvesForTopLevelPropertyCallee() throws {
        let source = """
        class Adder {
            operator fun invoke(x: Int): Int = x + 1
        }
        val globalAdder: Adder = Adder()
        fun use(): Int = globalAdder(41)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testInvokeOperatorResolvesForObjectSingletonCallee() throws {
        let source = """
        object Incrementer {
            operator fun invoke(x: Int): Int = x + 1
        }
        fun use(): Int = Incrementer(41)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testInvokeOperatorResolvesForExpressionResultCallee() throws {
        let source = """
        class Adder {
            operator fun invoke(x: Int): Int = x + 1
        }
        fun makeAdder(): Adder = Adder()
        fun use(): Int = makeAdder()(41)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testNonOperatorInvokeDoesNotResolveCallSyntax() throws {
        let source = """
        class Adder {
            fun invoke(x: Int): Int = x + 1
        }
        fun use(): Int {
            val adder: Adder = Adder()
            return adder(41)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }
}
