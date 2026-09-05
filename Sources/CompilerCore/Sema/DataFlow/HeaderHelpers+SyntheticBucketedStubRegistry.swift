import Foundation

// Bucketed synthetic stub registry (RF-STUB-006).
// Entries stay in the historical registration order, but each call is tagged
// with the stdlib-pipeline bucket it belongs to: target-out cleanup (a),
// source-backed migration (b), or compiler/runtime residual (c).

private enum SyntheticStubRegistryBucket: String {
    case targetOutCleanup = "a"
    case sourceBackedMigration = "b"
    case residualCompilerSurface = "c"
}

private struct SyntheticStubRegistryEntry {
    let bucket: SyntheticStubRegistryBucket
    let name: String
    let register: (DataFlowSemaPhase, SymbolTable, TypeSystem, StringInterner) -> Void
}

struct SyntheticDelegateStubRegistryContext {
    let kotlinPkg: [InternedString]
    let kotlinPropertiesPkg: [InternedString]
    let bundledIndex: BundledDeclarationIndex
    let skipStats: SyntheticStubSkipStatsCollector
}

private struct SyntheticDelegateStubRegistryEntry {
    let bucket: SyntheticStubRegistryBucket
    let name: String
    let register: (
        DataFlowSemaPhase,
        SymbolTable,
        TypeSystem,
        StringInterner,
        SyntheticDelegateStubRegistryContext
    ) -> Void
}

private func delegateStubRegistryEntries() -> [SyntheticDelegateStubRegistryEntry] {
    [
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Any") { phase, symbols, types, interner, context in
            phase.registerSyntheticAnyStub(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "PropertyInterfaces") { phase, symbols, types, interner, context in
            phase.registerSyntheticPropertyInterfaceStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinPkg: context.kotlinPkg,
                kotlinPropertiesPkg: context.kotlinPropertiesPkg,
                bundledIndex: context.bundledIndex
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Collections") { phase, symbols, types, interner, context in
            phase.registerSyntheticCollectionStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KFunctionParametersPatch") { phase, symbols, types, interner, _ in
            phase.patchKFunctionParametersType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KTypeArgumentsPatch") { phase, symbols, types, interner, _ in
            phase.patchKTypeArgumentsType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KTypeParameterUpperBoundsPatch") { phase, symbols, types, interner, _ in
            phase.patchKTypeParameterUpperBoundsType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "RangeProgression") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRangeProgressionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "RangeUntil") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRangeUntilStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Comparable") { phase, symbols, types, interner, _ in
            if types.comparableInterfaceSymbol == nil {
                phase.registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
            }
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "BuilderDSL") { phase, symbols, types, interner, _ in
            phase.registerSyntheticBuilderDSLStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Comparator") { phase, symbols, types, interner, _ in
            phase.registerSyntheticComparatorStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "String") { phase, symbols, types, interner, _ in
            phase.registerSyntheticStringStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Char") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCharStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Math") { phase, symbols, types, interner, _ in
            phase.registerSyntheticMathStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Coroutine") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCoroutineStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Exception") { phase, symbols, types, interner, context in
            phase.registerSyntheticExceptionStubs(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Duration") { phase, symbols, types, interner, _ in
            phase.registerSyntheticDurationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "InstantRuntimeBridges") { phase, symbols, types, interner, _ in
            phase.registerSyntheticInstantStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ClockRuntimeDispatch") { phase, symbols, types, interner, _ in
            phase.registerSyntheticClockStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExperimentalTimeAnchors") { phase, symbols, types, interner, context in
            phase.registerSyntheticExperimentalTimeStubs(symbols: symbols, types: types, interner: interner, bundledIndex: context.bundledIndex)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "StringBuilder") { phase, symbols, types, interner, context in
            let owner = [interner.intern("kotlin"), interner.intern("text"), interner.intern("StringBuilder")]
            if context.bundledIndex.contains(ownerFQName: owner, name: interner.intern("append"), arity: 1) {
                phase.patchSourceBackedStringBuilderSupertypes(symbols: symbols, types: types, interner: interner)
                return
            }
            phase.registerSyntheticStringBuilderStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "TODOAndIO") { phase, symbols, types, interner, context in
            phase.registerSyntheticTODOAndIOStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats
            )
        },
        // KSP-682: these patches attach the Function{N} supertypes for the
        // synthetic KProperty fallback shells only. When the bundled Kotlin
        // source is present, Sema inheritance binding resolves the `() -> V`
        // supertypes to Function{N} directly, so the patches are skipped.
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KPropertyFunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKPropertyFunctionSupertypes(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty0FunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKMutableProperty0FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty1FunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKMutableProperty1FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "FileIO") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFileIOStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "Path") { phase, symbols, types, interner, _ in
            phase.registerSyntheticPathStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Coercion") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCoercionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExtendedStdlibBuckets") { phase, symbols, types, interner, _ in
            phase.registerSyntheticBucketedExtendedStdlibStubs(symbols: symbols, types: types, interner: interner)
        },
    ]
}

private func extendedStdlibRegistryEntries() -> [SyntheticStubRegistryEntry] {
    [
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "Enum") { phase, symbols, types, interner in
            phase.registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .sourceBackedMigration, name: "Atomic") { phase, symbols, types, interner in
            phase.registerSyntheticAtomicResidualStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "KotlinAnnotation") { phase, symbols, types, interner in
            phase.registerSyntheticKotlinAnnotationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeInterop") { phase, symbols, types, interner in
            phase.registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "ThreadLocal") { phase, symbols, types, interner in
            phase.registerSyntheticThreadLocalStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineCancellation") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineIntrinsics") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeRefRuntime") { phase, symbols, types, interner in
            phase.registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeConcurrent") { phase, symbols, types, interner in
            phase.registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExperimentalMarker") { phase, symbols, types, interner in
            phase.registerSyntheticExperimentalMarkerStubs(symbols: symbols, types: types, interner: interner)
        },
    ]
}

extension DataFlowSemaPhase {
    func registerSyntheticDelegateRegistryStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        context: SyntheticDelegateStubRegistryContext
    ) {
        for entry in delegateStubRegistryEntries() {
            _ = (entry.bucket, entry.name)
            entry.register(self, symbols, types, interner, context)
        }
    }

    func registerSyntheticBucketedExtendedStdlibStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for entry in extendedStdlibRegistryEntries() {
            _ = (entry.bucket, entry.name)
            entry.register(self, symbols, types, interner)
        }
        // KSP-1205: EnumEntries is available after the Enum bucket has run.
        registerSyntheticMemoryModelEnumMembers(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
