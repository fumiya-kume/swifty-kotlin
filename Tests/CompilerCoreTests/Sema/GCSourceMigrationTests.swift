#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1261: GC.MainThreadFinalizerProcessor is a bundled source object.
@Suite
struct GCSourceMigrationTests {
    @Test
    func mainThreadFinalizerProcessorIsSourceBackedObject() throws {
        let ctx = makeContextFromSource(
            """
            @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

            import kotlin.native.runtime.GC

            fun processorType(): GC.MainThreadFinalizerProcessor? = null
            """
        )
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected GC.MainThreadFinalizerProcessor to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let gcFQName = ["kotlin", "native", "runtime", "GC"].map(ctx.interner.intern)
        let processorFQName = gcFQName + [ctx.interner.intern("MainThreadFinalizerProcessor")]
        let gcSymbol = try #require(sema.symbols.lookup(fqName: gcFQName))
        let processorSymbol = try #require(sema.symbols.lookup(fqName: processorFQName))

        #expect(sema.symbols.symbol(gcSymbol)?.kind == .object)
        #expect(sema.symbols.symbol(processorSymbol)?.kind == .object)
        #expect(sema.symbols.isSourceBackedSymbol(processorSymbol))
        #expect(sema.symbols.symbol(processorSymbol)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.parentSymbol(for: processorSymbol) == gcSymbol)

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: processorSymbol))
        #expect(
            ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/native/runtime/GC/Stdlib.kt"
        )
    }
}
#endif
