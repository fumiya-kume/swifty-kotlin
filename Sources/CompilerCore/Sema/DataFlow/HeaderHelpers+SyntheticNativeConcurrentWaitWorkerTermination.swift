import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: waitWorkerTermination(worker) top-level function.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - waitWorkerTermination

    func registerNativeConcurrentWaitWorkerTermination(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitWorkerTermination",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: types.unitType,
            parameters: [(name: "worker", type: workerType)],
            typeParameterSymbols: [],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}
