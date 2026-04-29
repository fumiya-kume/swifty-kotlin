@testable import CompilerCore
import Foundation
import XCTest

final class NativeUnhandledExceptionHookSurfaceTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func throwableType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: throwableFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func hookType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let throwable = try throwableType(sema: sema, interner: interner)
        return sema.types.make(.functionType(FunctionType(
            params: [throwable],
            returnType: sema.types.unitType
        )))
    }

    private func nativeSymbol(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: ["kotlin", "native", name].map { interner.intern($0) })
    }

    func testReportUnhandledExceptionHookTypeAliasIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let alias = try XCTUnwrap(nativeSymbol("ReportUnhandledExceptionHook", sema: sema, interner: interner))

        XCTAssertEqual(sema.symbols.symbol(alias)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: alias), try hookType(sema: sema, interner: interner))
        XCTAssertTrue(
            sema.symbols.annotations(for: alias).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            }
        )
    }

    func testUnhandledExceptionHookFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let throwable = try throwableType(sema: sema, interner: interner)
        let hook = try hookType(sema: sema, interner: interner)
        let nullableHook = sema.types.makeNullable(hook)

        let expectations: [(String, [TypeID], TypeID, String, Bool)] = [
            ("getUnhandledExceptionHook", [], nullableHook, "kk_native_getUnhandledExceptionHook", false),
            ("setUnhandledExceptionHook", [nullableHook], sema.types.unitType, "kk_native_setUnhandledExceptionHook", false),
            ("processUnhandledException", [throwable], sema.types.unitType, "kk_native_processUnhandledException", true),
            ("terminateWithUnhandledException", [throwable], sema.types.nothingType, "kk_native_terminateWithUnhandledException", false),
        ]

        for (name, params, returnType, externalLinkName, canThrow) in expectations {
            let symbol = try XCTUnwrap(nativeSymbol(name, sema: sema, interner: interner), name)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol), name)
            XCTAssertEqual(signature.receiverType, nil, name)
            XCTAssertEqual(signature.parameterTypes, params, name)
            XCTAssertEqual(signature.returnType, returnType, name)
            XCTAssertEqual(signature.canThrow, canThrow, name)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), externalLinkName, name)
            XCTAssertTrue(
                sema.symbols.annotations(for: symbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                },
                "\(name) must carry ExperimentalNativeApi metadata"
            )
        }
    }

    func testUnhandledExceptionHooksResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.ReportUnhandledExceptionHook
        import kotlin.native.getUnhandledExceptionHook
        import kotlin.native.setUnhandledExceptionHook
        import kotlin.native.processUnhandledException
        import kotlin.native.terminateWithUnhandledException

        fun probe(throwable: Throwable) {
            val hook: ReportUnhandledExceptionHook? = getUnhandledExceptionHook()
            setUnhandledExceptionHook(hook)
            processUnhandledException(throwable)
        }

        fun die(throwable: Throwable): Nothing = terminateWithUnhandledException(throwable)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected unhandled exception hooks to resolve without errors, got \(errors)")
    }
}
