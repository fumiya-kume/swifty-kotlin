import Foundation

/// Synthetic stdlib stub for kotlin.with (STDLIB-061).
/// with<T, R>(receiver: T, block: T.() -> R): R
/// Inline-expanded by CallLowerer; no runtime call.
extension DataFlowSemaPhase {
    func registerSyntheticScopeFunctionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let withName = interner.intern("with")
        let withFQName = kotlinPkg + [withName]

        if symbols.lookup(fqName: withFQName) != nil {
            return
        }

        let tName = interner.intern("T")
        let rName = interner.intern("R")
        let tFQName = withFQName + [tName]
        let rFQName = withFQName + [rName]

        let tSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: tFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rSymbol = symbols.define(
            kind: .typeParameter,
            name: rName,
            fqName: rFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )

        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

        let blockType = types.make(.functionType(FunctionType(
            receiver: tType,
            params: [],
            returnType: rType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let receiverName = interner.intern("receiver")
        let blockName = interner.intern("block")
        let receiverSymbol = symbols.define(
            kind: .valueParameter,
            name: receiverName,
            fqName: withFQName + [receiverName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: withFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let withSymbol = symbols.define(
            kind: .function,
            name: withName,
            fqName: withFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: withSymbol)
        }
        symbols.setParentSymbol(withSymbol, for: tSymbol)
        symbols.setParentSymbol(withSymbol, for: rSymbol)
        symbols.setParentSymbol(withSymbol, for: receiverSymbol)
        symbols.setParentSymbol(withSymbol, for: blockSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tType, blockType],
                returnType: rType,
                isSuspend: false,
                valueParameterSymbols: [receiverSymbol, blockSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: [tSymbol, rSymbol],
                classTypeParameterCount: 0
            ),
            for: withSymbol
        )
    }
}
