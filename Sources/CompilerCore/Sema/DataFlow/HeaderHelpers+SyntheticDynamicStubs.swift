import Foundation

/// Synthetic Kotlin/JS `Dynamic` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticDynamicStubs(
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

        let dynamicSymbol = ensureInterfaceSymbol(
            named: "Dynamic",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: dynamicSymbol)
        }

        let dynamicType = types.make(.classType(ClassType(
            classSymbol: dynamicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(dynamicType, for: dynamicSymbol)

        registerDynamicIterator(
            ownerSymbol: dynamicSymbol,
            ownerType: dynamicType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerDynamicIterator(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        guard let iteratorSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Iterator")]) else {
            return
        }

        let iteratorReturnType = types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(ownerType)],
            nullability: .nonNull
        )))
        let functionName = interner.intern("iterator")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_dynamic_iterator"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == iteratorReturnType
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
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: iteratorReturnType
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    }
}
