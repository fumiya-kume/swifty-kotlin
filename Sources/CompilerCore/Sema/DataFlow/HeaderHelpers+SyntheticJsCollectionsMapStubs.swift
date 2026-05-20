import Foundation

/// Synthetic Kotlin/JS collections `JsMap<K, V>` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsMapStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlyMap = ensureJsReadonlyMapCollectionsType(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        _ = ensureJsMapCollectionsType(
            packageFQName: pkg,
            readonlyMapSymbol: readonlyMap.symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsReadonlyMapCollectionsType(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, keyTypeParameterSymbol: SymbolID, valueTypeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlyMap")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlyMap",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsMapAnnotation(to: interfaceSymbol, symbols: symbols)

        let keyTypeParamSymbol = ensureJsCollectionsMapTypeParameter(
            named: "K",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
        let valueTypeParamSymbol = ensureJsCollectionsMapTypeParameter(
            named: "V",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, keyTypeParamSymbol, valueTypeParamSymbol)
    }

    private func ensureJsMapCollectionsType(
        packageFQName: [InternedString],
        readonlyMapSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, keyTypeParameterSymbol: SymbolID, valueTypeParameterSymbol: SymbolID) {
        let className = interner.intern("JsMap")
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)
        appendJsCollectionsMapAnnotation(to: classSymbol, symbols: symbols)

        let keyTypeParamSymbol = ensureJsCollectionsMapTypeParameter(
            named: "K",
            in: classFQName,
            owner: classSymbol,
            symbols: symbols,
            interner: interner
        )
        let valueTypeParamSymbol = ensureJsCollectionsMapTypeParameter(
            named: "V",
            in: classFQName,
            owner: classSymbol,
            symbols: symbols,
            interner: interner
        )
        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        let readonlyMapArgs: [TypeArg] = [.invariant(keyType), .out(valueType)]

        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([readonlyMapSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([readonlyMapSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs(readonlyMapArgs, for: classSymbol, supertype: readonlyMapSymbol)
        types.setNominalSupertypeTypeArgs(readonlyMapArgs, for: classSymbol, supertype: readonlyMapSymbol)

        return (classSymbol, keyTypeParamSymbol, valueTypeParamSymbol)
    }

    private func ensureJsCollectionsMapTypeParameter(
        named name: String,
        in ownerFQName: [InternedString],
        owner: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeParamName = interner.intern(name)
        let typeParamFQName = ownerFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(owner, for: typeParamSymbol)
        return typeParamSymbol
    }

    private func appendJsCollectionsMapAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalJsCollectionsApi"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
