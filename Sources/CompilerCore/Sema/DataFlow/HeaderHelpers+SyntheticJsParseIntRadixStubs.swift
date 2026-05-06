import Foundation

/// Synthetic Kotlin/JS `parseInt(s, radix)` external function surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsParseIntRadixStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJsParseIntRadixFunction(
            packageFQName: kotlinJsPkg,
            parameterTypes: [types.stringType, types.intType],
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsParseIntRadixFunction(
        packageFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
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
            symbols.setAnnotations([jsParseIntRadixDeprecatedAnnotation()], for: existing)
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
        symbols.setAnnotations([jsParseIntRadixDeprecatedAnnotation()], for: functionSymbol)
    }

    private func jsParseIntRadixDeprecatedAnnotation() -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: [
                "message = \"Use toInt(radix) instead.\"",
                "replaceWith = ReplaceWith(\"s.toInt(radix)\")",
                "level = DeprecationLevel.ERROR",
            ]
        )
    }
}
