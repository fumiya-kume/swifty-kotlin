@testable import CompilerCore
import XCTest

final class BuilderInferenceSemanticTests: XCTestCase {
    func testBuilderInferenceInfersTypeParameterFromImplicitReceiverMemberCall() {
        let source = """
        fun <T> build(@BuilderInference block: MutableList<T>.() -> Unit): List<T> = TODO()

        val xs = build {
            add(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected builder inference to infer T from add(1), got: \(ctx.diagnostics.diagnostics)")
    }

    func testBuilderInferenceRespectsExpectedType() {
        let source = """
        fun <T> build(@BuilderInference block: MutableList<T>.() -> Unit): List<T> = TODO()

        val xs: List<String> = build {
            add("x")
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected builder inference with expected type to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testWithoutBuilderInferenceStillCompilesWhenContextualInferenceIsSufficient() {
        let source = """
        fun <T> build(block: MutableList<T>.() -> Unit): List<T> = TODO()

        val xs = build {
            add(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected existing contextual inference to keep this case compiling, got: \(ctx.diagnostics.diagnostics)")
    }

    func testBuilderInferenceDoesNotBreakNonReceiverLambdaInference() {
        let source = """
        fun <T> collect(@BuilderInference block: (T) -> Unit): T = TODO()

        val value = collect {
            println(it)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected non-receiver lambda inference to remain unchanged, got: \(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }
}
