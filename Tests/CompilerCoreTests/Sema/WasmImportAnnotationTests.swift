@testable import CompilerCore
import XCTest

final class WasmImportAnnotationTests: XCTestCase {
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
                "Expected WasmImport annotation surface to resolve cleanly, got: \(diagnostics)"
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

    func testWasmImportAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "wasm", "WasmImport"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.wasm.WasmImport must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testWasmImportCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "wasm", "WasmImport"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "WasmImport must carry @Target metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.FUNCTION"]))
        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.wasm.ExperimentalWasmInterop"
            },
            "WasmImport must carry ExperimentalWasmInterop metadata"
        )
    }

    func testWasmImportPropertiesAndConstructorAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let baseFQName = ["kotlin", "wasm", "WasmImport"].map { interner.intern($0) }
        let annotationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: baseFQName))
        let moduleProperty = try XCTUnwrap(
            sema.symbols.lookup(fqName: baseFQName + [interner.intern("module")]),
            "WasmImport.module property must be registered"
        )
        let nameProperty = try XCTUnwrap(
            sema.symbols.lookup(fqName: baseFQName + [interner.intern("name")]),
            "WasmImport.name property must be registered"
        )
        let constructorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: baseFQName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "WasmImport String,String constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))

        XCTAssertEqual(sema.symbols.symbol(moduleProperty)?.kind, .property)
        XCTAssertEqual(sema.symbols.symbol(nameProperty)?.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: moduleProperty), annotationSymbol)
        XCTAssertEqual(sema.symbols.parentSymbol(for: nameProperty), annotationSymbol)
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType, sema.types.stringType])
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true])
        XCTAssertEqual(signature.returnType, sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }

    func testWasmImportIsAcceptedOnFunctionsWithAndWithoutNameArgument() {
        let source = """
        import kotlin.wasm.WasmImport

        @WasmImport("env")
        fun defaultImportName(): Int = 1

        @WasmImport(module = "env", name = "renamed_import")
        fun explicitImportName(): Int = 2
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected WasmImport on functions to type-check, got \(errors)"
        )
    }

    func testWasmImportRejectsClassTarget() {
        let source = """
        import kotlin.wasm.WasmImport

        @WasmImport("env")
        class NotAFunction
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let hasTargetError = ctx.diagnostics.diagnostics.contains { diagnostic in
            diagnostic.severity == .error
                && diagnostic.code.contains("ANNOTATION-TARGET")
        }

        XCTAssertTrue(
            hasTargetError,
            "Expected WasmImport on class to report an annotation target error, got \(ctx.diagnostics.diagnostics)"
        )
    }
}
