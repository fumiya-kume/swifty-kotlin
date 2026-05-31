import Foundation

/// Synthetic `kotlin.wasm.unsafe.withScopedMemoryAllocator` surface.
///
/// Kotlin stdlib signature (kotlin-stdlib-wasm-js, kotlin.wasm.unsafe):
/// ```kotlin
/// @UnsafeWasmMemoryApi
/// inline fun <R> withScopedMemoryAllocator(block: (MemoryAllocator) -> R): R
/// ```
extension DataFlowSemaPhase {
    func registerSyntheticWasmUnsafeScopedAllocatorStubs(
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

        let funcName = interner.intern("withScopedMemoryAllocator")
        let funcFQName = wasmUnsafePkg + [funcName]

        // Idempotency guard: skip if already registered.
        if symbols.lookup(fqName: funcFQName) != nil {
            return
        }

        let rName = interner.intern("R")
        let rSymbol = symbols.define(
            kind: .typeParameter,
            name: rName,
            fqName: funcFQName + [rName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

        let allocatorSymbol = ensureClassSymbol(
            named: "MemoryAllocator",
            in: wasmUnsafePkg,
            symbols: symbols,
            interner: interner
        )
        let allocatorType = types.make(.classType(ClassType(
            classSymbol: allocatorSymbol,
            args: [],
            nullability: .nonNull
        )))

        let blockFunctionType = types.make(.functionType(FunctionType(
            params: [allocatorType],
            returnType: rType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let blockName = interner.intern("block")
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: funcFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setPropertyType(blockFunctionType, for: blockSymbol)

        let funcSymbol = symbols.define(
            kind: .function,
            name: funcName,
            fqName: funcFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let wasmUnsafePkgSymbol {
            symbols.setParentSymbol(wasmUnsafePkgSymbol, for: funcSymbol)
        }
        symbols.setParentSymbol(funcSymbol, for: rSymbol)
        symbols.setParentSymbol(funcSymbol, for: blockSymbol)

        // @UnsafeWasmMemoryApi annotation
        symbols.setAnnotations(
            [MetadataAnnotationRecord(
                annotationFQName: "kotlin.wasm.unsafe.UnsafeWasmMemoryApi"
            )],
            for: funcSymbol
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockFunctionType],
                returnType: rType,
                isSuspend: false,
                valueParameterSymbols: [blockSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [rSymbol],
                classTypeParameterCount: 0
            ),
            for: funcSymbol
        )
    }
}
