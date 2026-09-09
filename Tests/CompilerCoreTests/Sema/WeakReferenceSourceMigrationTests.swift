#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1256: WeakReference receiver APIs must come from bundled Kotlin source.
@Suite
struct WeakReferenceSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/native/ref/WeakReference/WeakReference.kt"

    @Test
    func weakReferenceMembersAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "native", "ref"].map(ctx.interner.intern)

        for name in ["clear", "get", "pointer", "value"] {
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let allSymbols = sema.symbols.lookupAll(fqName: fqName)
            let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == sourcePath
            }

            #expect(allSymbols.count == 1, "Expected source migration to suppress synthetic duplicates for \(name)")
            #expect(sourceSymbols.count == 1, "Expected one bundled source declaration for \(name)")
            let symbol = try #require(sourceSymbols.first)
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)

            if name == "pointer" || name == "value" {
                #expect(sema.symbols.symbol(symbol)?.kind == .property)
                #expect(sema.symbols.extensionPropertyReceiverType(for: symbol) != nil)
            } else {
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes.isEmpty)
                #expect(signature.receiverType != nil)
                if name == "get" {
                    guard case let .typeParam(param) = sema.types.kind(of: signature.returnType) else {
                        Issue.record("Expected WeakReference.get() to return a nullable type parameter")
                        continue
                    }
                    #expect(param.nullability == .nullable)
                } else {
                    #expect(signature.returnType == sema.types.unitType)
                }
            }
        }
    }

    @Test
    func weakReferenceMemberCallsTypeCheckThroughSourceDefinitions() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        fun clearReference(reference: WeakReference<String>) {
            reference.clear()
        }

        fun getReference(reference: WeakReference<String>): String? = reference.get()

        fun valueReference(reference: WeakReference<String>): Any? = reference.value
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
            "WeakReference receiver calls should type-check without errors"
        )
    }
}
#endif
