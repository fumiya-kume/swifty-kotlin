@testable import CompilerCore
import Foundation
import XCTest

extension CompilerCoreTests {
    // MARK: - P5-40 Regression: Strict unresolved reference / type diagnostics

    func testUnresolvedIdentifierInBlockEmitsDiagnostic() throws {
        let source = """
        fun test(): Int {
            val x = missingIdent
            return 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedIdentifierInBinaryExprEmitsDiagnostic() throws {
        let source = """
        fun test(): Int = 1 + noSuchVar
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedFunctionCallWithMultipleArgsEmitsDiagnostic() throws {
        let source = """
        fun test() = missingFun(1, 2, 3)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedFunctionCallInNestedExprEmitsDiagnostic() throws {
        let source = """
        fun known(x: Int): Int = x
        fun test(): Int = known(unknownFn())
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedMemberCallEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo) = f.missing()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnresolvedSafeMemberCallFallsBackToAnyNullable() throws {
        // Safe member calls with unknown methods fall back to Any? (not errorType)
        // because the compiler may not enumerate all built-in methods (e.g. hashCode).
        let source = """
        class Foo
        fun test(f: Foo?) = f?.missing()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnresolvedBinaryOperatorEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo): Foo = f + f
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testUnresolvedTypeAnnotationOnLocalVarEmitsDiagnostic() throws {
        let source = """
        fun test() {
            val x: NoSuchType = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedReturnTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(): MissingReturn = 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedPropertyTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        class Holder {
            val x: GhostType = 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testResolvedIdentifierDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun test(): Int {
            val x = 10
            return x
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testResolvedFunctionCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun helper(x: Int): Int = x
        fun test(): Int = helper(42)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testResolvedTypeAnnotationDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun test(x: Int): String = "ok"
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedLocalFunParamTypeEmitsDiagnostic() throws {
        let source = """
        fun outer() {
            fun inner(p: Phantom): Int = 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedLocalFunReturnTypeEmitsDiagnostic() throws {
        let source = """
        fun outer() {
            fun inner(): Ghost = 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    // MARK: - P5-40 Cascading diagnostic suppression

    func testCascadingBinaryAddOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar + 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    func testCascadingMemberCallOnUnresolvedReceiverEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = unknownObj.method()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: ctx)
    }

    func testCascadingSafeMemberCallOnUnresolvedReceiverEmitsOnlyOneError() throws {
        let source = """
        fun test() = missingVar?.call()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: ctx)
    }

    func testCascadingBinarySubtractOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar - 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    func testCascadingBinaryMultiplyOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar * 2
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    // MARK: - P5-40 Resolved negative tests (no spurious diagnostics)

    func testResolvedMemberCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        fun test(f: Foo): Int = f.bar()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testResolvedSafeMemberCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        fun test(f: Foo?): Int? = f?.bar()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testResolvedBinaryAddDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): Int = 1 + 2
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testResolvedBinaryComparisonDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): Boolean = 1 == 2
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testResolvedStringConcatDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): String = "a" + "b"
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }
}
