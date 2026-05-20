@testable import CompilerCore
import XCTest

final class JsAnySurfaceTests: XCTestCase {
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
                "Expected JsAny surface to resolve cleanly, got: \(diagnostics)"
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

    func testJsAnyInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsAny"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsAny must be registered"
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

    func testJsAnyCarriesExperimentalWasmJsInteropMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsAny"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))

        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
            },
            "JsAny must carry ExperimentalWasmJsInterop metadata"
        )
    }

    func testJsAnyCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.JsAny

        fun accept(value: JsAny): JsAny = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsAny parameter usage to type-check, got \(errors)")
    }

    func testJsAnyToThrowableOrNullIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsAnyFQName = ["kotlin", "js", "JsAny"].map { interner.intern($0) }
        let jsAnySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsAnyFQName))
        let jsAnyType = try XCTUnwrap(sema.symbols.propertyType(for: jsAnySymbol))
        let throwableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
        )
        let throwableType = try XCTUnwrap(sema.symbols.propertyType(for: throwableSymbol))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsAnyFQName + [interner.intern("toThrowableOrNull")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == jsAnyType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.makeNullable(throwableType)
            },
            "JsAny.toThrowableOrNull() member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertNil(sema.symbols.externalLinkName(for: function))
    }

    func testJsAnyToThrowableOrNullCanBeCalled() {
        let source = """
        import kotlin.Throwable
        import kotlin.js.JsAny

        fun convert(value: JsAny): Throwable? = value.toThrowableOrNull()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsAny.toThrowableOrNull usage to type-check, got \(errors)")
    }
}
