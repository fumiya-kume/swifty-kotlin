import Foundation

/// Synthetic JVM stream `DoubleStream.toList()` extension surface.
extension DataFlowSemaPhase {
    func registerSyntheticDoubleStreamToListStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticPrimitiveStreamToListStubs(
            streamClassName: "DoubleStream",
            elementType: types.doubleType,
            externalLinkName: "kk_double_stream_toList",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
