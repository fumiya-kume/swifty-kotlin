import Foundation

/// Synthetic Kotlin/JS `JsBoolean` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsBooleanInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsBooleanType = ensureJsBooleanType(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerBooleanToJsBooleanFunction(
            packageFQName: kotlinJsPkg,
            returnType: jsBooleanType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsBooleanType(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let classSymbol = ensureClassSymbol(
            named: "JsBoolean",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)

        return classType
    }

    private func registerBooleanToJsBooleanFunction(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("toJsBoolean")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == types.booleanType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
            symbols.setExternalLinkName("kk_boolean_toJsBoolean", for: existing)
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
        symbols.setExternalLinkName("kk_boolean_toJsBoolean", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.booleanType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
    }
}
