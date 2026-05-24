@testable import CompilerCore
import Foundation
import XCTest

final class WasmUnsafeMemoryApiTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Wasm unsafe annotation surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func unsafeWasmMemoryApiSymbol(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let fqName = ["kotlin", "wasm", "unsafe", "UnsafeWasmMemoryApi"].map {
            interner.intern($0)
        }
        return try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.wasm.unsafe.UnsafeWasmMemoryApi to be registered"
        )
    }

    func testUnsafeWasmMemoryApiIsRegisteredAsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        let symbol = try unsafeWasmMemoryApiSymbol(sema: sema, interner: interner)
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testUnsafeWasmMemoryApiCarriesRequiresOptInMessage() throws {
        let (sema, interner) = try makeSema()
        let symbol = try unsafeWasmMemoryApiSymbol(sema: sema, interner: interner)
        let annotations = sema.symbols.annotations(for: symbol)

        let requiresOptIn = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "UnsafeWasmMemoryApi should carry @RequiresOptIn, got: \(annotations)"
        )
        XCTAssertTrue(
            requiresOptIn.arguments.contains {
                $0.contains("Unsafe APIs to access to WebAssembly linear memory")
            },
            "UnsafeWasmMemoryApi should carry the official opt-in message, got: \(requiresOptIn.arguments)"
        )
    }

    func testUnsafeWasmMemoryApiResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.wasm.unsafe.UnsafeWasmMemoryApi

        @UnsafeWasmMemoryApi
        fun unsafeEntry() {}
        """)
    }
}
