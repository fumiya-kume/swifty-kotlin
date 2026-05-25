import Foundation

/// Synthetic JVM stream `Stream<T>.toList()` extension surface.
extension DataFlowSemaPhase {
    func registerSyntheticStreamToListStubs(
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
            named: "Stream",
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

        let streamTypeParameterName = interner.intern("T")
        let streamFQName = javaStreamPkg + [interner.intern("Stream")]
        let streamTypeParameterSymbol = symbols.lookup(fqName: streamFQName + [streamTypeParameterName])
            ?? symbols.define(
                kind: .typeParameter,
                name: streamTypeParameterName,
                fqName: streamFQName + [streamTypeParameterName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
        symbols.setParentSymbol(streamSymbol, for: streamTypeParameterSymbol)
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: streamTypeParameterSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([streamTypeParameterSymbol], for: streamSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: streamSymbol)
        symbols.setPropertyType(
            types.make(.classType(ClassType(
                classSymbol: streamSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            ))),
            for: streamSymbol
        )

        let receiverType = types.make(.classType(ClassType(
            classSymbol: streamSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let functionName = interner.intern("toList")
        let functionFQName = kotlinStreamsPkg + [functionName]
        let externalLinkName = "kk_stream_toList"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [streamTypeParameterSymbol]
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
                typeParameterSymbols: [streamTypeParameterSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
