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

    func testUnresolvedSafeMemberCallEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo?) = f?.missing()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
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

    // MARK: - Additional unresolved-reference cases

    func testUnresolvedPropertyReadEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo): Int = f.missingProp
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testResolvedPropertyReadDoesNotEmitDiagnostic() throws {
        let source = """
        class Foo(val x: Int)
        fun test(f: Foo): Int = f.x
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnresolvedConstructorCallEmitsDiagnostic() throws {
        let source = """
        fun test() {
            val x = NoSuchClass()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertTrue(
            ctx.diagnostics.diagnostics.contains(where: { ["KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023"].contains($0.code) }),
            "Expected unresolved-reference diagnostic for unknown constructor, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    func testResolvedConstructorCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        class Point(val x: Int, val y: Int)
        fun test(): Point = Point(1, 2)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testCascadingFromUnresolvedTypeAnnotationDoesNotDoubleReport() throws {
        // The unresolved type `Ghost` should produce SEMA-0025 once; using the
        // variable afterward should not produce a second SEMA-0022 for `x`.
        let source = """
        fun test() {
            val x: Ghost = 0
            val y = x + 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 0, in: ctx)
    }

    func testMultipleUnresolvedIdentifiersEachEmitDiagnostic() throws {
        let source = """
        fun test() {
            val a = missingA
            val b = missingB
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 2, in: ctx)
    }
}
