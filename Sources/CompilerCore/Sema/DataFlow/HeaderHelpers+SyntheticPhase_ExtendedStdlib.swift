import Foundation

/// Extended stdlib batch of synthetic stub registrations from `registerSyntheticDelegateStubs`.
///
/// This Phase covers a 66-call block that previously sat in the middle of the
/// central dispatch: Atomic/Enum/Uuid/Serialization/Networking/Logging/
/// Locale/NumberFormat/Streams/Concurrency/Coroutines/JS-binding stubs.
///
/// Why this file exists: the central dispatch in `HeaderHelpers.swift` is the
/// single largest source of textual merge conflicts in the repo, because every
/// new platform-specific stub PR appends a `registerSyntheticXxx(...)` line to
/// the same long function. Carving stable batches out into Phase files lets
/// parallel branches edit a Phase file rather than fighting over the central
/// dispatch.
///
/// IMPORTANT: the call order inside this function is **identical** to the
/// original middle-section of `registerSyntheticDelegateStubs`. Do NOT reorder
/// lines — Sema golden outputs depend on the registration sequence
/// (some symbols are intentionally re-registered or shadowed by later calls;
/// see e.g. the dual `registerSyntheticJsBooleanInteropStubs` calls preserved
/// here as-is from the original dispatch). When adding a new entry, insert
/// it in the position dictated by any documented dependency; otherwise prefer
/// alphabetical order within the surrounding peer group.
///
/// Companion file: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift` covers
/// the trailing 28-call Wasm/Js batch. Both Phase files preserve the original
/// dispatch order exactly.
extension DataFlowSemaPhase {
    func registerSyntheticPhase_ExtendedStdlib(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticExperimentalBitwiseStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAtomicStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticUuidStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSerializationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURIStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURLStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNetworkStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAdvancedNetworkStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSecurityStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticResourceBundleStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticLocaleConstructorStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNumberFormatStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDateFormatStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticMetaprogStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsStubs(symbols: symbols, interner: interner)
        registerSyntheticJvmAnnotationPropertyStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBigIntegerStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInvokeStubs(symbols: symbols, interner: interner)
        registerSyntheticJvmOptionalStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticIntStreamToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStreamsStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDoubleStreamToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJvmReflectStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticLongStreamToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticThreadLocalStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStreamToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeSetterStubs(symbols: symbols, interner: interner)
        registerSyntheticConcurrencyStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticReadWriteLockStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsQualifierStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsRegExpStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsRegExpMatchStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsDynamicStubs(symbols: symbols, interner: interner)
        registerSyntheticJsAnyStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsReferenceStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsNumberStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBooleanInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBigIntStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsStringStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsPrimitiveWrapperStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBooleanInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsFunStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsArrayStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsArrayToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBigIntToLongStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsStringInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsReferenceInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsFileNameStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBase64Stubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsModuleStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsPromiseStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsDateStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlyMapToMapStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsCollectionsReadonlyMapToMutableMapStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBigIntInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeGetterStubs(symbols: symbols, interner: interner)
        registerSyntheticJsNameStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExperimentalMarkerStubs(symbols: symbols, types: types, interner: interner)
    }
}
