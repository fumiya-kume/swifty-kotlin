import Foundation

/// Trailing batch of synthetic stub registrations from `registerSyntheticDelegateStubs`.
///
/// Why this file exists: the central dispatch in `HeaderHelpers.swift` is one of
/// the hottest merge-conflict sources in the repo, because every new
/// platform-specific stub PR previously had to append a `registerSyntheticXxx(...)`
/// line near the end of the same long function. Multiple parallel branches doing
/// this each landed at the same trailing lines and produced conflict markers.
///
/// Moving the trailing batch into this file gives parallel branches that add
/// Js/Wasm interop stubs a separate touch surface from the core dispatch.
///
/// IMPORTANT: the call order inside this function is **identical** to the
/// original tail of `registerSyntheticDelegateStubs`. Do NOT reorder lines —
/// the Sema golden outputs depend on the registration sequence (some symbols
/// shadow earlier registrations on purpose). When adding a new entry, prefer
/// inserting in alphabetical position within the surrounding peer group, but
/// only when you are sure there is no implicit ordering dependency.
///
/// This is Pilot #1 of the "central dispatch Phase split" refactor.
/// If this lands without breaking Sema golden, further Phase files will be
/// carved out in follow-up PRs.
extension DataFlowSemaPhase {
    func registerSyntheticPhase_PlatformAndJS(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticWasmExportStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsNonModuleStubs(symbols: symbols, interner: interner)
        registerSyntheticJsConsoleStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticWasmImportStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsExportStubs(symbols: symbols, interner: interner)
        registerSyntheticCoroutinesABIStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticWasmUnsafeAnnotationStubs(symbols: symbols, interner: interner)
        registerSyntheticWasmUnsafeMemoryAllocatorStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticWasmUnsafePointerStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsExternalInheritorsOnlyStubs(symbols: symbols, interner: interner)
        registerSyntheticJsArrayStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDynamicStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsClassStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsReferenceStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBooleanStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsSymbolStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsMapStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsSetStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlyArrayToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlyArrayToMutableListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlySetStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlySetToMutableSetStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsNumberInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsIntNumberInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsArrayInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticKPropertyIsInitializedStub(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsStaticStubs(symbols: symbols, interner: interner)
        registerSyntheticJsExternalArgumentStubs(symbols: symbols, interner: interner)
    }
}
