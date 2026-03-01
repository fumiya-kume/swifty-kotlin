public enum SyntheticSymbolScheme {
    public static let defaultStubOffset: Int32 = -40_000
    public static let defaultMaskOffset: Int32 = -30_000
    public static let typeTokenOffset: Int32 = -20_000
    public static let propertySetterAccessorOffset: Int32 = -13_000
    public static let propertyGetterAccessorOffset: Int32 = -12_000
    public static let receiverParameterOffset: Int32 = -10_000

    private static func makeSymbol(offset: Int32, original: SymbolID) -> SymbolID {
        SymbolID(rawValue: offset - original.rawValue)
    }

    public static func defaultStubSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultStubOffset, original: original)
    }

    public static func defaultMaskSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultMaskOffset, original: original)
    }

    public static func setterValueParameterSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultMaskOffset, original: propertySymbol)
    }

    public static func semaSetterValueSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultStubOffset, original: propertySymbol)
    }

    public static func reifiedTypeTokenSymbol(for typeParameterSymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: typeTokenOffset, original: typeParameterSymbol)
    }

    public static func receiverParameterSymbol(for functionSymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: receiverParameterOffset, original: functionSymbol)
    }

    public static func propertyGetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: propertyGetterAccessorOffset, original: propertySymbol)
    }

    public static func propertySetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: propertySetterAccessorOffset, original: propertySymbol)
    }

    public static func propertyAccessorSymbol(
        for propertySymbol: SymbolID,
        kind: PropertyAccessorKind
    ) -> SymbolID {
        switch kind {
        case .getter:
            return propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            return propertySetterAccessorSymbol(for: propertySymbol)
        }
    }

    /// Preserves the historical heuristic used by ABI lowering to classify
    /// synthetic accessor call symbols as non-throwing.
    public static func isLikelySyntheticPropertyAccessor(_ symbol: SymbolID) -> Bool {
        let raw = symbol.rawValue
        return raw <= propertyGetterAccessorOffset && raw > typeTokenOffset
    }
}
