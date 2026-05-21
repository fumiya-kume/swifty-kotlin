import Foundation

/// Synthetic Kotlin/JS `T.toJsReference` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsReferenceInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsReferenceSymbol = ensureJsReferenceType(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerToJsReferenceFunction(
            packageFQName: kotlinJsPkg,
            jsReferenceSymbol: jsReferenceSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsReferenceType(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let jsReferenceSymbol = ensureInterfaceSymbol(
            named: "JsReference",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: jsReferenceSymbol)
        }

        let typeParamName = interner.intern("T")
        let jsReferenceFQName = kotlinJsPkg + [interner.intern("JsReference")]
        let typeParamFQName = jsReferenceFQName + [typeParamName]
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
        symbols.setParentSymbol(jsReferenceSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let jsReferenceType = types.make(.classType(ClassType(
            classSymbol: jsReferenceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: jsReferenceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: jsReferenceSymbol)
        symbols.setPropertyType(jsReferenceType, for: jsReferenceSymbol)
        appendJsReferenceInteropAnnotation(to: jsReferenceSymbol, symbols: symbols)

        return jsReferenceSymbol
    }

    private func registerToJsReferenceFunction(
        packageFQName: [InternedString],
        jsReferenceSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("toJsReference")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
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
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: jsReferenceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_toJsReference"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == typeParamType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [typeParamSymbol]
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsReferenceInteropAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: typeParamType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]]
            ),
            for: functionSymbol
        )
    }

    private func appendJsReferenceInteropAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalWasmJsInterop"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
