import Foundation

/// Synthetic `kotlin.wasm.unsafe.MemoryAllocator` surface.
extension DataFlowSemaPhase {
    func registerSyntheticWasmUnsafeMemoryAllocatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let wasmUnsafePkg = ensurePackage(
            path: ["kotlin", "wasm", "unsafe"],
            symbols: symbols,
            interner: interner
        )
        let wasmUnsafePkgSymbol = symbols.lookup(fqName: wasmUnsafePkg)

        let pointerSymbol = ensureWasmUnsafePointerShell(
            packageFQName: wasmUnsafePkg,
            packageSymbol: wasmUnsafePkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let pointerType = types.make(.classType(ClassType(
            classSymbol: pointerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let allocatorSymbol = ensureClassSymbol(
            named: "MemoryAllocator",
            in: wasmUnsafePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic, .abstractType], for: allocatorSymbol)
        if let wasmUnsafePkgSymbol {
            symbols.setParentSymbol(wasmUnsafePkgSymbol, for: allocatorSymbol)
        }

        let allocatorType = types.make(.classType(ClassType(
            classSymbol: allocatorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(allocatorType, for: allocatorSymbol)

        registerWasmUnsafeMemoryAllocatorConstructor(
            ownerSymbol: allocatorSymbol,
            ownerType: allocatorType,
            symbols: symbols,
            interner: interner
        )
        registerWasmUnsafeMemoryAllocatorAllocate(
            ownerSymbol: allocatorSymbol,
            ownerType: allocatorType,
            returnType: pointerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureWasmUnsafePointerShell(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let pointerSymbol = ensureClassSymbol(
            named: "Pointer",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic], for: pointerSymbol)
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: pointerSymbol)
        }
        let pointerType = types.make(.classType(ClassType(
            classSymbol: pointerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pointerType, for: pointerSymbol)
        return pointerSymbol
    }

    private func registerWasmUnsafeMemoryAllocatorConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        if symbols.lookupAll(fqName: constructorFQName).contains(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }) {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: constructorSymbol
        )
    }

    private func registerWasmUnsafeMemoryAllocatorAllocate(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let allocateName = interner.intern("allocate")
        let allocateFQName = ownerInfo.fqName + [allocateName]
        if let existing = symbols.lookupAll(fqName: allocateFQName).first(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == [types.intType]
                && signature.returnType == returnType
        }) {
            symbols.insertFlags([.synthetic, .abstractType], for: existing)
            return
        }

        let allocateSymbol = symbols.define(
            kind: .function,
            name: allocateName,
            fqName: allocateFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType]
        )
        symbols.setParentSymbol(ownerSymbol, for: allocateSymbol)

        let sizeName = interner.intern("size")
        let sizeParameter = symbols.define(
            kind: .valueParameter,
            name: sizeName,
            fqName: allocateFQName + [sizeName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(allocateSymbol, for: sizeParameter)
        symbols.setPropertyType(types.intType, for: sizeParameter)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [types.intType],
                returnType: returnType,
                valueParameterSymbols: [sizeParameter],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: allocateSymbol
        )
    }
}
