import Foundation

/// Synthetic Kotlin/JS `JsSymbol` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsSymbolStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let annotationName = interner.intern("JsSymbol")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsSymbol",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendJsSymbolAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerJsSymbolNameMember(
            ownerSymbol: annotationSymbol,
            ownerFQName: kotlinJsPkg + [annotationName],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsSymbolAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
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

    private func registerJsSymbolNameMember(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let name = interner.intern("name")
        let propertyFQName = ownerFQName + [name]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: name,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let constructorSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: constructorFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.stringType]
        }) {
            constructorSymbol = existing
        } else {
            constructorSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: constructorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let parameterFQName = constructorFQName + [name]
        let parameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: parameterFQName) {
            parameterSymbol = existing
        } else {
            parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: parameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
        symbols.setPropertyType(types.stringType, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }
}
