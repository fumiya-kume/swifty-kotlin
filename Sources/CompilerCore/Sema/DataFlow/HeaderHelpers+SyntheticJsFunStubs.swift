import Foundation

/// Synthetic Kotlin/JS `JsFun` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsFunStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg)

        let annotationName = interner.intern("JsFun")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsFun",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: annotationSymbol)
        }

        appendJsFunAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerJsFunCodeMember(
            ownerSymbol: annotationSymbol,
            ownerFQName: kotlinPkg + [annotationName],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsFunAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                ]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlin.js.ExperimentalWasmJsInterop"),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func registerJsFunCodeMember(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let code = interner.intern("code")
        let propertyFQName = ownerFQName + [code]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: code,
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

        let parameterFQName = constructorFQName + [code]
        let parameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: parameterFQName) {
            parameterSymbol = existing
        } else {
            parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: code,
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
