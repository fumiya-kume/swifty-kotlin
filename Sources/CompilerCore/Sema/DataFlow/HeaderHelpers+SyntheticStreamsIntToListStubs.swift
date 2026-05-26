import Foundation

/// Synthetic JVM stream `IntStream.toList()` extension surface.
extension DataFlowSemaPhase {
    func registerSyntheticIntStreamToListStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticPrimitiveStreamToListStubs(
            streamClassName: "IntStream",
            elementType: types.intType,
            externalLinkName: "kk_int_stream_toList",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
