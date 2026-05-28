@testable import CompilerCore
import XCTest

/// Tests for the `kotlin.wasm.unsafe.withScopedMemoryAllocator` synthetic stub.
///
/// Kotlin stdlib signature:
/// ```kotlin
/// @UnsafeWasmMemoryApi
/// inline fun <R> withScopedMemoryAllocator(block: (MemoryAllocator) -> R): R
/// ```
final class WasmUnsafeScopedAllocatorTests: XCTestCase {
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
                "Expected withScopedMemoryAllocator surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func symbol(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: path.map { interner.intern($0) })
    }

    // MARK: - Registration tests

    func testWithScopedMemoryAllocatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            ),
            "kotlin.wasm.unsafe.withScopedMemoryAllocator must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(funcSymbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testWithScopedMemoryAllocatorIsInline() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let info = try XCTUnwrap(sema.symbols.symbol(funcSymbol))
        XCTAssertTrue(
            info.flags.contains(.inlineFunction),
            "withScopedMemoryAllocator must be marked inline"
        )
    }

    func testWithScopedMemoryAllocatorSignatureHasOneBlockParameter() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: funcSymbol))
        XCTAssertEqual(signature.parameterTypes.count, 1, "Expected exactly one parameter (block)")
        XCTAssertNil(signature.receiverType, "withScopedMemoryAllocator is top-level, not an extension")
    }

    func testWithScopedMemoryAllocatorBlockParameterTakesMemoryAllocator() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: funcSymbol))
        let blockTypeID = try XCTUnwrap(signature.parameterTypes.first)

        guard case let .functionType(funcType) = sema.types.kind(of: blockTypeID) else {
            XCTFail("Expected block parameter to be a function type, got: \(sema.types.kind(of: blockTypeID))")
            return
        }
        XCTAssertEqual(funcType.params.count, 1, "block should take one parameter (MemoryAllocator)")

        let allocatorSymbol = try XCTUnwrap(
            symbol(["kotlin", "wasm", "unsafe", "MemoryAllocator"], sema: sema, interner: interner)
        )
        let expectedAllocatorType = sema.types.make(.classType(ClassType(
            classSymbol: allocatorSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            funcType.params.first,
            expectedAllocatorType,
            "block parameter should be MemoryAllocator"
        )
    }

    func testWithScopedMemoryAllocatorHasOneTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: funcSymbol))
        XCTAssertEqual(
            signature.typeParameterSymbols.count,
            1,
            "withScopedMemoryAllocator must have exactly one type parameter (R)"
        )
    }

    func testWithScopedMemoryAllocatorReturnTypeEqualsTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: funcSymbol))
        let rSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
        let expectedReturnType = sema.types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
        XCTAssertEqual(
            signature.returnType,
            expectedReturnType,
            "Return type must be R (the function's type parameter)"
        )
    }

    func testWithScopedMemoryAllocatorCarriesUnsafeWasmMemoryApiAnnotation() throws {
        let (sema, interner) = try makeSema()
        let funcSymbol = try XCTUnwrap(
            symbol(
                ["kotlin", "wasm", "unsafe", "withScopedMemoryAllocator"],
                sema: sema,
                interner: interner
            )
        )
        let annotations = sema.symbols.annotations(for: funcSymbol)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.wasm.unsafe.UnsafeWasmMemoryApi" },
            "withScopedMemoryAllocator must be annotated with @UnsafeWasmMemoryApi, got: \(annotations)"
        )
    }
}
