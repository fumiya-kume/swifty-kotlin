@testable import CompilerCore
import XCTest

final class ReflectAssociatedObjectKeySyntheticTests: XCTestCase {
    func testAssociatedObjectKeyAnnotationSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("annotation class Smoke")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = ["kotlin", "reflect", "AssociatedObjectKey"].map { ctx.interner.intern($0) }
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.kind, .annotationClass)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            },
            "Expected AssociatedObjectKey to target annotation classes, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.reflect.ExperimentalAssociatedObjects"
            },
            "Expected AssociatedObjectKey to carry ExperimentalAssociatedObjects, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments.contains("AnnotationRetention.BINARY")
            },
            "Expected AssociatedObjectKey to carry @Retention(BINARY), got: \(annotations)"
        )
    }

    func testAssociatedObjectKeyCanAnnotateAnnotationClass() {
        let source = """
        import kotlin.reflect.AssociatedObjectKey

        @AssociatedObjectKey
        annotation class Binding
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(targetDiagnostics.isEmpty, "Expected annotation-class target to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testAssociatedObjectKeyRejectsFunctionTarget() {
        let source = """
        import kotlin.reflect.AssociatedObjectKey

        @AssociatedObjectKey
        fun notAnAnnotationClass() {}
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(targetDiagnostics.count, 1, "Expected function target to be rejected, got: \(ctx.diagnostics.diagnostics)")
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

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }
}
