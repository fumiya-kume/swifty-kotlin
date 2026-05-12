import Foundation

/// Synthetic Kotlin/JS `JsQualifier` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsQualifierStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsPkgSymbol = symbols.lookup(fqName: jsPkg)

        let annotationName = interner.intern("JsQualifier")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsQualifier",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: annotationSymbol)
        }

        appendJsQualifierAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerJsQualifierValueMember(
            ownerSymbol: annotationSymbol,
            ownerFQName: jsPkg + [annotationName],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsQualifierAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.FILE",
            ]
        )

        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    private func registerJsQualifierValueMember(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let value = interner.intern("value")
        let propertyFQName = ownerFQName + [value]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: value,
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

        let parameterFQName = constructorFQName + [value]
        let parameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: parameterFQName) {
            parameterSymbol = existing
        } else {
            parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: value,
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
