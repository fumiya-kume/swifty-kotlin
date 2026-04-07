@testable import CompilerCore
import Foundation
import XCTest

final class OverloadResolutionByLambdaReturnTypeTests: XCTestCase {
    func testUnannotatedLambdaReturnTypeOverloadsRemainAmbiguous() {
        let source = """
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertEqual(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count,
            1,
            "Expected ambiguous overload resolution without annotation, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testAnnotatedLambdaReturnTypeOverloadSelectsMatchingTopLevelOverload() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected annotated overload to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testAnnotatedLambdaReturnTypeOverloadCanSelectNonAnnotatedCandidate() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): String = foo { "x" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected refinement to keep the matching non-annotated overload, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDifferentLambdaInputShapesRemainAmbiguous() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: (Int) -> Int): Int = 1
        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: (String) -> Int): String = "s"

        fun test() = foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertEqual(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count,
            1,
            "Expected ambiguity when lambda parameter shapes differ, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testMultipleLambdaArgumentsRemainAmbiguous() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(a: () -> Int, b: () -> String): Int = 1
        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(a: () -> Int, b: () -> Int): String = "s"

        fun test() = foo({ 42 }, { "x" })
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertEqual(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count,
            1,
            "Expected ambiguity when multiple lambda return types participate, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testCallableReferenceStillResolvesNormally() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        fun provideInt(): Int = 1

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo(::provideInt)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected callable reference overload resolution to keep working, got: \(ctx.diagnostics.diagnostics)")
    }

    func testMemberCallRefinesByLambdaReturnType() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        class Host {
            @OptIn(ExperimentalTypeInference::class)
            @OverloadResolutionByLambdaReturnType
            fun foo(block: () -> Int): Int = 1

            fun foo(block: () -> String): String = "s"
        }

        fun test(host: Host): Int = host.foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected member-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSafeMemberCallRefinesByLambdaReturnType() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        class Host {
            @OptIn(ExperimentalTypeInference::class)
            @OverloadResolutionByLambdaReturnType
            fun foo(block: () -> Int): Int = 1

            fun foo(block: () -> String): String = "s"
        }

        fun test(host: Host?): Int? = host?.foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected safe member-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExtensionCallRefinesByLambdaReturnType() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        class Host

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun Host.foo(block: () -> Int): Int = 1

        fun Host.foo(block: () -> String): String = "s"

        fun test(host: Host): Int = host.foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected extension-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted per test.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }
}
