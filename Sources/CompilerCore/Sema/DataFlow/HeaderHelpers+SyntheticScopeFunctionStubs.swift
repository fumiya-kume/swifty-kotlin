import Foundation

/// Synthetic stdlib stubs for Kotlin scope functions.
/// - with<T, R>(receiver: T, block: T.() -> R): R   (STDLIB-061)
/// - T.let<T, R>(block: (T) -> R): R                (STDLIB-400)
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

        registerWithStub(symbols: symbols, types: types, interner: interner, kotlinPkg: kotlinPkg)
        registerLetStub(symbols: symbols, types: types, interner: interner, kotlinPkg: kotlinPkg)
    }

    /// `with<T, R>(receiver: T, block: T.() -> R): R` (STDLIB-061)
    private func registerWithStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
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

    /// `T.let<T, R>(block: (T) -> R): R` (STDLIB-400)
    /// Inline extension function on T (upper bound Any?, so T is nullable-capable).
    /// The block receives T as its parameter (`it`).
    private func registerLetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let letName = interner.intern("let")
        let letFQName = kotlinPkg + [letName]

        if symbols.lookup(fqName: letFQName) != nil {
            return
        }

        let tName = interner.intern("T")
        let rName = interner.intern("R")
        let tFQName = letFQName + [tName]
        let rFQName = letFQName + [rName]

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

        // T and R have upper bound Any? (nullable-capable) per Kotlin spec
        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nullable)))
        let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))

        // block: (T) -> R — lambda that takes T as an explicit parameter (not a receiver)
        let blockType = types.make(.functionType(FunctionType(
            params: [tType],
            returnType: rType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let blockName = interner.intern("block")
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: letFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let letSymbol = symbols.define(
            kind: .function,
            name: letName,
            fqName: letFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: letSymbol)
        }
        symbols.setParentSymbol(letSymbol, for: tSymbol)
        symbols.setParentSymbol(letSymbol, for: rSymbol)
        symbols.setParentSymbol(letSymbol, for: blockSymbol)

        // Extension function: receiverType is T (already nullable-capable, no double-wrapping)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: tType,
                parameterTypes: [blockType],
                returnType: rType,
                isSuspend: false,
                valueParameterSymbols: [blockSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tSymbol, rSymbol],
                classTypeParameterCount: 0
            ),
            for: letSymbol
        )
    }
}
