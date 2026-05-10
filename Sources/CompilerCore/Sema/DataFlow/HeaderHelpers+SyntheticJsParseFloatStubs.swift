import Foundation

/// Synthetic Kotlin/JS `parseFloat` external function surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsParseFloatStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJsParseFloatFunction(
            packageFQName: kotlinJsPkg,
            parameterTypes: [types.stringType, types.intType],
            returnType: types.doubleType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsParseFloatFunction(
        packageFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("parseFloat")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameterTypes
                && existingSignature.returnType == returnType
        }) {
            symbols.setAnnotations([jsParseFloatDeprecatedAnnotation()], for: existing)
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

        var valueParameterSymbols: [SymbolID] = []
        for (index, parameterType) in parameterTypes.enumerated() {
            let paramNameID = interner.intern(index == 0 ? "s" : "radix")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setPropertyType(parameterType, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: [false, true],
                valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count)
            ),
            for: functionSymbol
        )
        symbols.setAnnotations([jsParseFloatDeprecatedAnnotation()], for: functionSymbol)
    }

    private func jsParseFloatDeprecatedAnnotation() -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: [
                "message = \"Use toDouble() instead.\"",
                "replaceWith = ReplaceWith(\"s.toDouble()\")",
                "level = DeprecationLevel.ERROR",
            ]
        )
    }
}
