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
        registerWithScopedMemoryAllocatorFunction(
            packageFQName: wasmUnsafePkg,
            packageSymbol: wasmUnsafePkgSymbol,
            allocatorType: allocatorType,
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

    private func registerWithScopedMemoryAllocatorFunction(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        allocatorType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("withScopedMemoryAllocator")
        let functionFQName = packageFQName + [functionName]
        let returnTypeParameterName = interner.intern("R")
        let returnTypeParameterFQName = functionFQName + [returnTypeParameterName]
        let returnTypeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: returnTypeParameterFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            returnTypeParameterSymbol = existing
        } else {
            returnTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: returnTypeParameterName,
                fqName: returnTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: returnTypeParameterSymbol)
        let returnTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: returnTypeParameterSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: [allocatorType],
            returnType: returnTypeParameterType
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [blockType]
                && signature.returnType == returnTypeParameterType
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: returnTypeParameterSymbol)

        let blockName = interner.intern("block")
        let blockParameter = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: functionFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParameter)
        symbols.setPropertyType(blockType, for: blockParameter)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [blockType],
                returnType: returnTypeParameterType,
                typeParameterSymbols: [returnTypeParameterSymbol],
                typeParameterUpperBoundsList: [[types.anyType]],
                valueParameterSymbols: [blockParameter],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName("kk_wasm_withScopedMemoryAllocator", for: functionSymbol)
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.wasm.unsafe.UnsafeWasmMemoryApi")],
            for: functionSymbol
        )
    }
}
