import Foundation

/// Synthetic Kotlin/JS collections `JsArray<E>` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlyArray = ensureJsReadonlyArrayCollectionsType(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        _ = ensureJsArrayCollectionsType(
            packageFQName: pkg,
            readonlyArraySymbol: readonlyArray.symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsReadonlyArrayCollectionsType(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlyArray")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlyArray",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsAnnotation(to: interfaceSymbol, symbols: symbols)

        let typeParamName = interner.intern("E")
        let typeParamFQName = interfaceFQName + [typeParamName]
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
        symbols.setParentSymbol(interfaceSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, typeParamSymbol)
    }

    private func ensureJsArrayCollectionsType(
        packageFQName: [InternedString],
        readonlyArraySymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let className = interner.intern("JsArray")
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
        appendJsCollectionsAnnotation(to: classSymbol, symbols: symbols)

        let typeParamName = interner.intern("E")
        let typeParamFQName = classFQName + [typeParamName]
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
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([readonlyArraySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([readonlyArraySymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: classSymbol, supertype: readonlyArraySymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: classSymbol, supertype: readonlyArraySymbol)

        return (classSymbol, typeParamSymbol)
    }

    private func appendJsCollectionsAnnotation(
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
