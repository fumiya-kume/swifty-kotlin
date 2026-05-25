import Foundation

/// Synthetic JVM stream `LongStream.toList()` extension surface.
extension DataFlowSemaPhase {
    func registerSyntheticLongStreamToListStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticPrimitiveStreamToListStubs(
            streamClassName: "LongStream",
            elementType: types.longType,
            externalLinkName: "kk_long_stream_toList",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticPrimitiveStreamToListStubs(
        streamClassName: String,
        elementType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaStreamPkg = ensurePackage(
            path: ["java", "util", "stream"],
            symbols: symbols,
            interner: interner
        )
        let kotlinStreamsPkg = ensurePackage(
            path: ["kotlin", "streams"],
            symbols: symbols,
            interner: interner
        )
        let kotlinCollectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let streamSymbol = ensureClassSymbol(
            named: streamClassName,
            in: javaStreamPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaStreamPkgSymbol = symbols.lookup(fqName: javaStreamPkg) {
            symbols.setParentSymbol(javaStreamPkgSymbol, for: streamSymbol)
        }
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")]) else {
            return
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: streamSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let functionName = interner.intern("toList")
        let functionFQName = kotlinStreamsPkg + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols.isEmpty
                && signature.classTypeParameterCount == 0
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
        if let kotlinStreamsPkgSymbol = symbols.lookup(fqName: kotlinStreamsPkg) {
            symbols.setParentSymbol(kotlinStreamsPkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                typeParameterSymbols: [],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
