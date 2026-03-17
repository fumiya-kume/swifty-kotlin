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

        if symbols.lookup(fqName: withFQName) == nil {
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

        // --- Top-level run<R>(block: () -> R): R (STDLIB-401) ---
        registerTopLevelRunStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
        )

        // --- Extension T.run<R>(block: T.() -> R): R (STDLIB-401) ---
        registerExtensionRunStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
        )
    }

    /// Top-level `run<R>(block: () -> R): R` — just executes block and returns result.
    private func registerTopLevelRunStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let runName = interner.intern("run")
        let runFQName = kotlinPkg + [runName]

        // Skip if already registered.
        // KNOWN LIMITATION: This checks any symbol at kotlin.run FQN.  The extension
        // overload shares the same FQN, so if it is registered first, this check
        // incorrectly skips the top-level overload.  In practice the top-level stub
        // is registered before the extension stub in registerScopeFunctionStubs(),
        // so this ordering dependency is safe but fragile.
        if symbols.lookup(fqName: runFQName) != nil {
            return
        }

        // NOTE: The type parameter R shares FQN kotlin.run.R with the extension
        // overload's R.  The symbol table accepts this because typeParameter symbols
        // are scoped by their parent function symbol, not by FQN uniqueness.
        let rName = interner.intern("R")
        let rFQName = runFQName + [rName]

        let rSymbol = symbols.define(
            kind: .typeParameter,
            name: rName,
            fqName: rFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )

        let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

        let blockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: rType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let blockName = interner.intern("block")
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: runFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let runSymbol = symbols.define(
            kind: .function,
            name: runName,
            fqName: runFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: runSymbol)
        }
        symbols.setParentSymbol(runSymbol, for: rSymbol)
        symbols.setParentSymbol(runSymbol, for: blockSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: rType,
                isSuspend: false,
                valueParameterSymbols: [blockSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [rSymbol],
                classTypeParameterCount: 0
            ),
            for: runSymbol
        )
    }

    /// Extension `T.run<R>(block: T.() -> R): R` — receiver becomes `this` in lambda.
    private func registerExtensionRunStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let runName = interner.intern("run")
        let extRunFQName = kotlinPkg + [runName]

        // The top-level `run` overload shares the same FQN; the symbol table
        // supports function overloads under one FQN via canCoexistAsOverload.
        // Skip only when the extension overload (with receiverType) is already
        // registered.
        let existingRunSymbols = symbols.lookupAll(fqName: extRunFQName)
        let extensionAlreadyRegistered = existingRunSymbols.contains { symID in
            guard let sig = symbols.functionSignature(for: symID) else { return false }
            return sig.receiverType != nil
        }
        if extensionAlreadyRegistered {
            return
        }

        // NOTE: T and R type parameters share FQNs (kotlin.run.T, kotlin.run.R)
        // with the top-level overload's R.  This is acceptable because type parameter
        // symbols are scoped by their parent function symbol.
        let tName = interner.intern("T")
        let rName = interner.intern("R")
        let tFQName = extRunFQName + [tName]
        let rFQName = extRunFQName + [rName]

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

        let blockName = interner.intern("block")
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: extRunFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let runSymbol = symbols.define(
            kind: .function,
            name: runName,
            fqName: extRunFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: runSymbol)
        }
        symbols.setParentSymbol(runSymbol, for: tSymbol)
        symbols.setParentSymbol(runSymbol, for: rSymbol)
        symbols.setParentSymbol(runSymbol, for: blockSymbol)

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
            for: runSymbol
        )
    }
}
