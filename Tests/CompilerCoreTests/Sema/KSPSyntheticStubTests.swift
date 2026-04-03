@testable import CompilerCore
import Foundation
import XCTest

final class KSPSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKSPSyntheticTypesAndFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let processingPkg = ["com", "google", "devtools", "ksp", "processing"].map { interner.intern($0) }

        let expectedTypes: [(String, SymbolKind)] = [
            ("SymbolProcessor", .interface),
            ("KSPLogger", .class),
            ("Resolver", .class),
            ("CodeGenerator", .class),
        ]

        for (name, kind) in expectedTypes {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: processingPkg + [interner.intern(name)]),
                "Expected \(name) to be registered"
            )
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, kind)
        }

        let expectedTopLevelLinks: [String: String] = [
            "registerProcessor": "kk_ksp_register_processor",
            "registeredProcessors": "kk_ksp_registered_processors",
            "runProcessors": "kk_ksp_run_processors",
        ]

        for (name, link) in expectedTopLevelLinks {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: processingPkg + [interner.intern(name)]),
                "Expected \(name) to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), link)
        }
    }

    func testKSPImportsResolveWithoutExternalMetadata() throws {
        let source = """
        import com.google.devtools.ksp.processing.CodeGenerator
        import com.google.devtools.ksp.processing.KSPLogger
        import com.google.devtools.ksp.processing.Resolver
        import com.google.devtools.ksp.processing.SymbolProcessor
        import com.google.devtools.ksp.processing.registerProcessor
        import com.google.devtools.ksp.processing.registeredProcessors
        import com.google.devtools.ksp.processing.runProcessors

        class DemoProcessor : SymbolProcessor {
            override fun process(resolver: Resolver): List<String> {
                return resolver.getSymbolsWithAnnotation("Demo")
            }
        }

        fun runPipeline(logger: KSPLogger, resolver: Resolver, codeGenerator: CodeGenerator) {
            logger.info("boot")
            resolver.addFile("input.kt")
            resolver.addSymbol("PlainSymbol")
            resolver.addAnnotatedSymbol("Demo", "MarkedSymbol")
            registerProcessor("DemoProcessor")
            registeredProcessors()
            runProcessors(logger, resolver, codeGenerator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "KSP synthetic stubs should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let processingPkg = ["com", "google", "devtools", "ksp", "processing"].map { ctx.interner.intern($0) }
            let runProcessorsSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: processingPkg + [ctx.interner.intern("runProcessors")])
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: runProcessorsSymbol),
                "kk_ksp_run_processors"
            )
        }
    }
}
