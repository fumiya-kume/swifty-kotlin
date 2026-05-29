@testable import CompilerCore
import XCTest

final class WasmUnsafeMemoryAllocatorTests: XCTestCase {
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
                "Expected MemoryAllocator surface to resolve cleanly, got: \(diagnostics)"
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

    private func classType(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let classSymbol = try XCTUnwrap(symbol(path, sema: sema, interner: interner))
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func testMemoryAllocatorClassIsRegisteredAsAbstract() throws {
        let (sema, interner) = try makeSema()
        let allocatorSymbol = try XCTUnwrap(
            symbol(["kotlin", "wasm", "unsafe", "MemoryAllocator"], sema: sema, interner: interner),
            "kotlin.wasm.unsafe.MemoryAllocator must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(allocatorSymbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.abstractType))
    }

    func testMemoryAllocatorNoArgumentConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let allocatorFQName = ["kotlin", "wasm", "unsafe", "MemoryAllocator"].map { interner.intern($0) }
        let allocatorSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: allocatorFQName))
        let constructor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: allocatorFQName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "MemoryAllocator constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.parentSymbol(for: constructor), allocatorSymbol)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, try classType(["kotlin", "wasm", "unsafe", "MemoryAllocator"], sema: sema, interner: interner))
    }

    func testAllocateMemberReturnsPointer() throws {
        let (sema, interner) = try makeSema()
        let allocatorFQName = ["kotlin", "wasm", "unsafe", "MemoryAllocator"].map { interner.intern($0) }
        let allocatorSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: allocatorFQName))
        let allocate = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: allocatorFQName + [interner.intern("allocate")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .function
            },
            "MemoryAllocator.allocate must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: allocate))
        let allocateInfo = try XCTUnwrap(sema.symbols.symbol(allocate))

        XCTAssertEqual(sema.symbols.parentSymbol(for: allocate), allocatorSymbol)
        XCTAssertTrue(allocateInfo.flags.contains(.abstractType))
        XCTAssertEqual(signature.receiverType, try classType(["kotlin", "wasm", "unsafe", "MemoryAllocator"], sema: sema, interner: interner))
        XCTAssertEqual(signature.parameterTypes, [sema.types.intType])
        XCTAssertEqual(signature.returnType, try classType(["kotlin", "wasm", "unsafe", "Pointer"], sema: sema, interner: interner))
    }

    func testMemoryAllocatorAllocateResolvesInSource() throws {
        let source = """
        import kotlin.wasm.unsafe.MemoryAllocator

        fun allocatePointer(allocator: MemoryAllocator) = allocator.allocate(4)
        """
        let (sema, interner) = try makeSema(source: source)
        let functionSymbol = try XCTUnwrap(
            symbol(["allocatePointer"], sema: sema, interner: interner),
            "allocatePointer must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        XCTAssertEqual(signature.returnType, try classType(["kotlin", "wasm", "unsafe", "Pointer"], sema: sema, interner: interner))
    }

    func testWithScopedMemoryAllocatorResolvesInSource() throws {
        let source = """
        import kotlin.wasm.unsafe.withScopedMemoryAllocator

        fun allocateScoped() =
            withScopedMemoryAllocator { allocator -> allocator.allocate(4) }
        """
        let (sema, interner) = try makeSema(source: source)
        let functionSymbol = try XCTUnwrap(
            symbol(["allocateScoped"], sema: sema, interner: interner),
            "allocateScoped must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        XCTAssertEqual(signature.returnType, try classType(["kotlin", "wasm", "unsafe", "Pointer"], sema: sema, interner: interner))
    }

    func testWithScopedMemoryAllocatorSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "wasm", "unsafe"].map { interner.intern($0) }
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: packageFQName + [interner.intern("withScopedMemoryAllocator")]),
            "withScopedMemoryAllocator must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        XCTAssertTrue(sema.symbols.symbol(functionSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(signature.parameterTypes.count, 1)
        XCTAssertEqual(signature.returnType, sema.types.make(.typeParam(TypeParamType(
            symbol: try XCTUnwrap(signature.typeParameterSymbols.first),
            nullability: .nonNull
        ))))
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_wasm_withScopedMemoryAllocator")
        XCTAssertTrue(sema.symbols.annotations(for: functionSymbol).contains {
            $0.annotationFQName == "kotlin.wasm.unsafe.UnsafeWasmMemoryApi"
        })
    }
}
