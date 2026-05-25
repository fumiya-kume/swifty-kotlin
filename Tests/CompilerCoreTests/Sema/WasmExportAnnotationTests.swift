@testable import CompilerCore
import XCTest

final class WasmExportAnnotationTests: XCTestCase {
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
                "Expected WasmExport annotation surface to resolve cleanly, got: \(diagnostics)"
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

    func testWasmExportAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "wasm", "WasmExport"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.wasm.WasmExport must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testWasmExportCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "wasm", "WasmExport"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "WasmExport must carry @Target metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.FUNCTION"]))
        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.wasm.ExperimentalWasmInterop"
            },
            "WasmExport must carry ExperimentalWasmInterop metadata"
        )
    }

    func testWasmExportNamePropertyAndDefaultConstructorAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let baseFQName = ["kotlin", "wasm", "WasmExport"].map { interner.intern($0) }
        let annotationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: baseFQName))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: baseFQName + [interner.intern("name")]),
            "WasmExport.name property must be registered"
        )
        let constructorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: baseFQName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "WasmExport String constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        let propertyInfo = try XCTUnwrap(sema.symbols.symbol(propertySymbol))

        XCTAssertEqual(propertyInfo.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), annotationSymbol)
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true])
        XCTAssertEqual(signature.returnType, sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }

    func testWasmExportIsAcceptedOnFunctionsWithAndWithoutNameArgument() {
        let source = """
        import kotlin.wasm.WasmExport

        @WasmExport
        fun defaultExportName(): Int = 1

        @WasmExport("renamed_export")
        fun explicitExportName(): Int = 2
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected WasmExport on functions to type-check, got \(errors)"
        )
    }

    func testWasmExportRejectsClassTarget() {
        let source = """
        import kotlin.wasm.WasmExport

        @WasmExport
        class NotAFunction
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let hasTargetError = ctx.diagnostics.diagnostics.contains { diagnostic in
            diagnostic.severity == .error
                && diagnostic.code.contains("ANNOTATION-TARGET")
        }

        XCTAssertTrue(
            hasTargetError,
            "Expected WasmExport on class to report an annotation target error, got \(ctx.diagnostics.diagnostics)"
        )
    }
}
