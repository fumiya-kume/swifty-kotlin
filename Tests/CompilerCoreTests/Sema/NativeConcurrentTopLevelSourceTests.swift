#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeConcurrentTopLevelSourceTests {
    private static nonisolated(unsafe) var _sharedContext: CompilationContext?

    private func sharedContext() throws -> CompilationContext {
        if let cached = Self._sharedContext { return cached }
        var result: CompilationContext?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)
            result = context
        }
        let context = try #require(result)
        Self._sharedContext = context
        return context
    }

    private func symbol(
        _ path: [String],
        in context: CompilationContext
    ) throws -> SymbolID {
        let sema = try #require(context.sema)
        return try #require(
            sema.symbols.lookup(fqName: path.map(context.interner.intern)),
            "Expected \(path.joined(separator: "."))"
        )
    }

    @Test
    func ksp1216NominalEntriesAreClassOnlyAnchors() throws {
        let context = try sharedContext()
        let sema = try #require(context.sema)
        let package = ["kotlin", "native", "concurrent"]
        // FreezableAtomicReference is already source-backed by KSP-1236
        // (its constructor ships in Stdlib/kotlin/native/concurrent/
        // FreezableAtomicReference/Stdlib.kt), so it is intentionally absent
        // from this synthetic-anchor inventory.
        let expectedGenericShapes: [String: (TypeVariance, TypeID)] = [
            "AtomicReference": (.invariant, sema.types.nullableAnyType),
            "DetachedObjectGraph": (.invariant, sema.types.nullableAnyType),
            "WorkerBoundReference": (.out, sema.types.anyType),
        ]

        for name in [
            "AtomicInt", "AtomicLong", "AtomicNativePtr", "AtomicReference",
            "DetachedObjectGraph", "MutableData", "WorkerBoundReference",
        ] {
            let path = package + [name]
            let classSymbol = try symbol(path, in: context)
            let info = try #require(sema.symbols.symbol(classSymbol))
            #expect(info.kind == .class)
            #expect(info.visibility == .public)
            #expect(info.flags.contains(.synthetic))
            #expect(sema.symbols.sourceFileID(for: classSymbol) == nil)
            #expect(
                sema.symbols.lookupAll(
                    fqName: (path + ["<init>"]).map(context.interner.intern)
                ).isEmpty,
                "KSP-1216 must not absorb the constructor task for \(name)"
            )

            if let (variance, upperBound) = expectedGenericShapes[name] {
                #expect(sema.types.nominalTypeParameterVariances(for: classSymbol) == [variance])
                let parameters = sema.types.nominalTypeParameterSymbols(for: classSymbol)
                #expect(parameters.count == 1)
                if let parameter = parameters.first {
                    #expect(sema.symbols.typeParameterUpperBounds(for: parameter) == [upperBound])
                }
            } else {
                #expect(sema.types.nominalTypeParameterSymbols(for: classSymbol).isEmpty)
            }
        }

        // FreezableAtomicReference is already source-backed (KSP-1236) with a
        // value-taking constructor; it is intentionally not a synthetic anchor.
        let freezablePath = package + ["FreezableAtomicReference"]
        let freezableSymbol = try symbol(freezablePath, in: context)
        let freezableInfo = try #require(sema.symbols.symbol(freezableSymbol))
        #expect(freezableInfo.kind == .class)
        #expect(!freezableInfo.flags.contains(.synthetic))
        #expect(sema.symbols.sourceFileID(for: freezableSymbol) != nil)
    }

    @Test
    func nativePtrIsAnOpaqueClassOnlyAnchor() throws {
        let context = try sharedContext()
        let sema = try #require(context.sema)
        let path = ["kotlin", "native", "internal", "NativePtr"]
        let nativePtr = try symbol(path, in: context)
        let info = try #require(sema.symbols.symbol(nativePtr))

        #expect(info.kind == .class)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.types.nominalTypeParameterSymbols(for: nativePtr).isEmpty)
        #expect(
            sema.symbols.lookupAll(
                fqName: (path + ["<init>"]).map(context.interner.intern)
            ).isEmpty
        )
    }

    @Test
    func ksp1216FunctionsAreBundledSourceDeclarations() throws {
        let context = try sharedContext()
        let sema = try #require(context.sema)
        let package = ["kotlin", "native", "concurrent"]
        let expectedArities = [
            "atomicLazy": 1,
            "attachObjectGraphInternal": 1,
            "consumeFuture": 1,
            "detachObjectGraphInternal": 2,
            "executeImpl": 4,
            "freeze": 0,
            "waitForMultipleFutures": 2,
            "waitWorkerTermination": 1,
            "withWorker": 3,
        ]
        let sourcePath = "__bundled_kotlin/native/concurrent/Stdlib.kt"

        for (name, arity) in expectedArities {
            let candidates = sema.symbols.lookupAll(
                fqName: (package + [name]).map(context.interner.intern)
            ).filter { symbol in
                guard let info = sema.symbols.symbol(symbol),
                      info.kind == .function,
                      !info.flags.contains(.synthetic),
                      sema.symbols.functionSignature(for: symbol)?.parameterTypes.count == arity,
                      let fileID = sema.symbols.sourceFileID(for: symbol)
                else {
                    return false
                }
                return context.sourceManager.path(of: fileID) == sourcePath
            }

            #expect(candidates.count == 1, "Expected one source-backed \(name)/\(arity)")
            if let function = candidates.first {
                #expect(sema.symbols.isSourceBackedSymbol(function))
                #expect(sema.symbols.externalLinkName(for: function) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: function))
                #expect((signature.receiverType != nil) == (name == "freeze"))
                #expect(
                    sema.symbols.symbol(function)?.flags.contains(.inlineFunction)
                        == (name == "withWorker")
                )
            }
        }
    }

    @Test
    func sourceWrappersUsePrivateRuntimeBridgeSymbols() throws {
        let context = try sharedContext()
        let sema = try #require(context.sema)
        let package = ["kotlin", "native", "internal"]
        let expectedLinks = [
            "__nativeConcurrentAttachObjectGraph": "__kk_native_concurrent_attach_object_graph",
            "__nativeConcurrentConsumeFuture": "__kk_native_concurrent_consume_future",
            "__nativeConcurrentDetachObjectGraph": "__kk_native_concurrent_detach_object_graph",
            "__nativeConcurrentExecuteImpl": "__kk_native_concurrent_execute_impl",
            "__nativeConcurrentStartWorker": "__kk_native_concurrent_start_worker",
            "__nativeConcurrentTerminateWorker": "__kk_native_concurrent_terminate_worker",
            "__nativeConcurrentWaitForMultipleFutures": "__kk_native_concurrent_wait_for_multiple_futures",
            "__nativeConcurrentWaitWorkerTermination": "__kk_native_concurrent_wait_worker_termination",
        ]

        for (name, link) in expectedLinks {
            let functions = sema.symbols.lookupAll(
                fqName: (package + [name]).map(context.interner.intern)
            ).filter { sema.symbols.symbol($0)?.kind == .function }
            #expect(functions.count == 1)
            if let function = functions.first {
                #expect(sema.symbols.symbol(function)?.visibility == .internal)
                #expect(sema.symbols.externalLinkName(for: function) == link)
            }
        }
    }
}
#endif
