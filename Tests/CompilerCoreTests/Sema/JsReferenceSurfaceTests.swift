@testable import CompilerCore
import XCTest

final class JsReferenceSurfaceTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JsReference surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted by each test.
        }
        return ctx
    }

    func testJsReferenceInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsReference must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: symbol),
            sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
    }

    func testJsReferenceTypeParameterIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)

        XCTAssertEqual(typeParameters.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameters[0])?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameters[0]), symbol)
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsReferenceCanBeImportedAndUsedAsGenericParameterType() {
        let source = """
        import kotlin.js.JsReference

        fun accept(value: JsReference<String>): JsReference<String> = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsReference parameter usage to type-check, got \(errors)")
    }
}
