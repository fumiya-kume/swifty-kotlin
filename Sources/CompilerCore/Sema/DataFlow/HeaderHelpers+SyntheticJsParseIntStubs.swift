import Foundation

/// Synthetic Kotlin/JS `parseInt` external function surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsParseIntStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJsParseIntFunction(
            packageFQName: kotlinJsPkg,
            parameterTypes: [types.stringType],
            returnType: types.intType,
            valueParameterHasDefaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsParseIntFunction(
        packageFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        valueParameterHasDefaultValues: [Bool],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("parseInt")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameterTypes
                && existingSignature.returnType == returnType
        }) {
            symbols.setAnnotations([jsParseIntDeprecatedAnnotation()], for: existing)
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
            let paramName = index == 0 ? "s" : "radix"
            let paramNameID = interner.intern(paramName)
            let paramFQNameID = interner.intern("\(paramName)$string")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramFQNameID],
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
                valueParameterHasDefaultValues: valueParameterHasDefaultValues,
                valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count)
            ),
            for: functionSymbol
        )
        symbols.setAnnotations([jsParseIntDeprecatedAnnotation()], for: functionSymbol)
    }

    private func jsParseIntDeprecatedAnnotation() -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: [
                "message = \"Use toInt() instead.\"",
                "replaceWith = ReplaceWith(\"s.toInt()\")",
                "level = DeprecationLevel.ERROR",
            ]
        )
    }
}
