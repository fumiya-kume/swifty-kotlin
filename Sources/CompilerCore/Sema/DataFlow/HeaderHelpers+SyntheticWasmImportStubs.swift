import Foundation

/// Synthetic Kotlin/Wasm `WasmImport` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticWasmImportStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let wasmPkg = ensurePackage(
            path: ["kotlin", "wasm"],
            symbols: symbols,
            interner: interner
        )
        let wasmPkgSymbol = symbols.lookup(fqName: wasmPkg)

        let annotationName = interner.intern("WasmImport")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "WasmImport",
            in: wasmPkg,
            symbols: symbols,
            interner: interner
        )
        if let wasmPkgSymbol {
            symbols.setParentSymbol(wasmPkgSymbol, for: annotationSymbol)
        }

        appendWasmImportAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerWasmImportPropertiesAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: wasmPkg + [annotationName],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendWasmImportAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.wasm.ExperimentalWasmInterop"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FUNCTION"]
            ),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func registerWasmImportPropertiesAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let moduleProperty = registerWasmImportStringProperty(
            named: "module",
            ownerSymbol: ownerSymbol,
            ownerFQName: ownerFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nameProperty = registerWasmImportStringProperty(
            named: "name",
            ownerSymbol: ownerSymbol,
            ownerFQName: ownerFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.stringType, types.stringType]
        }
        guard !hasMatchingConstructor else {
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

        let moduleParameter = registerWasmImportStringParameter(
            named: "module",
            ownerSymbol: constructorSymbol,
            ownerFQName: constructorFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nameParameter = registerWasmImportStringParameter(
            named: "name",
            ownerSymbol: constructorSymbol,
            ownerFQName: constructorFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType, types.stringType],
                returnType: ownerType,
                valueParameterSymbols: [moduleParameter, nameParameter],
                valueParameterHasDefaultValues: [false, true],
                valueParameterIsVararg: [false, false]
            ),
            for: constructorSymbol
        )

        _ = moduleProperty
        _ = nameProperty
    }

    private func registerWasmImportStringProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: propertyName,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.stringType, for: propertySymbol)
        return propertySymbol
    }

    private func registerWasmImportStringParameter(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let parameterName = interner.intern(name)
        let parameterFQName = ownerFQName + [parameterName]
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: parameterFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: parameterSymbol)
        symbols.setPropertyType(types.stringType, for: parameterSymbol)
        return parameterSymbol
    }
}
