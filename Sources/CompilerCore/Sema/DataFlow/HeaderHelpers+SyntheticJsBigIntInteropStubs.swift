import Foundation

/// Synthetic Kotlin/JS `JsBigInt` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsBigIntInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsBigIntType = ensureJsBigIntType(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerLongToJsBigIntFunction(
            packageFQName: kotlinJsPkg,
            returnType: jsBigIntType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsBigIntType(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let classSymbol = ensureClassSymbol(
            named: "JsBigInt",
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

    private func registerLongToJsBigIntFunction(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("toJsBigInt")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == types.longType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
            symbols.setExternalLinkName("kk_long_toJsBigInt", for: existing)
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
        symbols.setExternalLinkName("kk_long_toJsBigInt", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.longType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
    }
}
