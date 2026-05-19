import Foundation

/// Synthetic Kotlin/JS `String.toJsString` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsStringInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsStringType = ensureJsStringType(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerStringToJsStringFunction(
            packageFQName: kotlinJsPkg,
            returnType: jsStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsStringType(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let classSymbol = ensureClassSymbol(
            named: "JsString",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)
        appendJsStringInteropAnnotation(to: classSymbol, symbols: symbols)

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)

        return classType
    }

    private func registerStringToJsStringFunction(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("toJsString")
        let functionFQName = packageFQName + [functionName]
        let externalLinkName = "kk_string_toJsString"
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == types.stringType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsStringInteropAnnotation(to: existing, symbols: symbols)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsStringInteropAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.stringType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
    }

    private func appendJsStringInteropAnnotation(
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
