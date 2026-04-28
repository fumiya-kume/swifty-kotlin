@testable import CompilerCore
import XCTest

final class ReflectFindAssociatedObjectSyntheticTests: XCTestCase {
    func testFindAssociatedObjectSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("annotation class Smoke")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = ["kotlin", "reflect", "findAssociatedObject"].map { ctx.interner.intern($0) }
        let symbolID = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName).first)
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))

        XCTAssertEqual(symbol.kind, .function)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertTrue(symbol.flags.contains(.inlineFunction))
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_kclass_find_associated_object")
        XCTAssertEqual(signature.parameterTypes.count, 0)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(sema.types.renderType(signature.returnType), "Any?")

        guard let receiverType = signature.receiverType else {
            return XCTFail("findAssociatedObject must be a KClass extension function")
        }
        if case .kClassType = sema.types.kind(of: receiverType) {
            // Expected receiver shape.
        } else {
            XCTFail("Expected KClass receiver, got \(sema.types.renderType(receiverType))")
        }

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.reflect.ExperimentalAssociatedObjects" },
            "Expected findAssociatedObject to require ExperimentalAssociatedObjects opt-in, got: \(annotations)"
        )
    }

    func testFindAssociatedObjectRequiresOptIn() {
        let source = """
        import kotlin.reflect.KClass
        import kotlin.reflect.findAssociatedObject

        annotation class Binding

        fun find(kclass: KClass<*>): Any? = kclass.findAssociatedObject<Binding>()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected findAssociatedObject usage to require opt-in, got: \(ctx.diagnostics.diagnostics)")
    }

    func testFindAssociatedObjectAllowsExplicitOptIn() {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects
        import kotlin.reflect.KClass
        import kotlin.reflect.findAssociatedObject

        annotation class Binding

        @OptIn(ExperimentalAssociatedObjects::class)
        fun find(kclass: KClass<*>): Any? = kclass.findAssociatedObject<Binding>()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @OptIn to satisfy findAssociatedObject usage, got: \(ctx.diagnostics.diagnostics)")
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
