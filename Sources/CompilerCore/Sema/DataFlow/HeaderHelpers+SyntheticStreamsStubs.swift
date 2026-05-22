import Foundation

/// Synthetic JVM stream extension stubs for `kotlin.streams`.
extension DataFlowSemaPhase {
    func registerSyntheticStreamsStubs(
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
        let javaStreamPkgSymbol = symbols.lookup(fqName: javaStreamPkg)
        let kotlinStreamsPkgSymbol = symbols.lookup(fqName: kotlinStreamsPkg)

        let streamSymbol = ensureClassSymbol(named: "Stream", in: javaStreamPkg, symbols: symbols, interner: interner)
        let intStreamSymbol = ensureClassSymbol(named: "IntStream", in: javaStreamPkg, symbols: symbols, interner: interner)
        let longStreamSymbol = ensureClassSymbol(named: "LongStream", in: javaStreamPkg, symbols: symbols, interner: interner)
        let doubleStreamSymbol = ensureClassSymbol(named: "DoubleStream", in: javaStreamPkg, symbols: symbols, interner: interner)
        if let javaStreamPkgSymbol {
            symbols.setParentSymbol(javaStreamPkgSymbol, for: streamSymbol)
            symbols.setParentSymbol(javaStreamPkgSymbol, for: intStreamSymbol)
            symbols.setParentSymbol(javaStreamPkgSymbol, for: longStreamSymbol)
            symbols.setParentSymbol(javaStreamPkgSymbol, for: doubleStreamSymbol)
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
        let streamElementType = types.make(.typeParam(TypeParamType(
            symbol: streamTypeParameterSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([streamTypeParameterSymbol], for: streamSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: streamSymbol)
        symbols.setPropertyType(
            types.make(.classType(ClassType(
                classSymbol: streamSymbol,
                args: [.invariant(streamElementType)],
                nullability: .nonNull
            ))),
            for: streamSymbol
        )

        registerStreamAsSequence(
            receiverSymbol: streamSymbol,
            receiverElementType: streamElementType,
            receiverTypeParameterSymbol: streamTypeParameterSymbol,
            externalLinkName: "kk_stream_asSequence",
        kotlinStreamsPkg: kotlinStreamsPkg,
        kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPrimitiveStreamAsSequence(
            receiverSymbol: intStreamSymbol,
            receiverElementType: types.intType,
            externalLinkName: "kk_int_stream_asSequence",
            kotlinStreamsPkg: kotlinStreamsPkg,
            kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPrimitiveStreamAsSequence(
            receiverSymbol: longStreamSymbol,
            receiverElementType: types.longType,
            externalLinkName: "kk_long_stream_asSequence",
            kotlinStreamsPkg: kotlinStreamsPkg,
            kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPrimitiveStreamAsSequence(
            receiverSymbol: doubleStreamSymbol,
            receiverElementType: types.doubleType,
            externalLinkName: "kk_double_stream_asSequence",
            kotlinStreamsPkg: kotlinStreamsPkg,
            kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerStreamAsSequence(
        receiverSymbol: SymbolID,
        receiverElementType: TypeID,
        receiverTypeParameterSymbol: SymbolID,
        externalLinkName: String,
        kotlinStreamsPkg: [InternedString],
        kotlinStreamsPkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [.out(receiverElementType)],
            nullability: .nonNull
        )))
        registerStreamsAsSequenceFunction(
            receiverType: receiverType,
            returnElementType: receiverElementType,
            typeParameterSymbols: [receiverTypeParameterSymbol],
            externalLinkName: externalLinkName,
            kotlinStreamsPkg: kotlinStreamsPkg,
            kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerPrimitiveStreamAsSequence(
        receiverSymbol: SymbolID,
        receiverElementType: TypeID,
        externalLinkName: String,
        kotlinStreamsPkg: [InternedString],
        kotlinStreamsPkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerStreamsAsSequenceFunction(
            receiverType: receiverType,
            returnElementType: receiverElementType,
            typeParameterSymbols: [],
            externalLinkName: externalLinkName,
            kotlinStreamsPkg: kotlinStreamsPkg,
            kotlinStreamsPkgSymbol: kotlinStreamsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerStreamsAsSequenceFunction(
        receiverType: TypeID,
        returnElementType: TypeID,
        typeParameterSymbols: [SymbolID],
        externalLinkName: String,
        kotlinStreamsPkg: [InternedString],
        kotlinStreamsPkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("asSequence")
        let functionFQName = kotlinStreamsPkg + [functionName]
        let hasMatchingSignature = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols == typeParameterSymbols
        }
        guard !hasMatchingSignature else { return }

        let sequenceType = makeSyntheticSequenceReturnType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: returnElementType
        )
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let kotlinStreamsPkgSymbol {
            symbols.setParentSymbol(kotlinStreamsPkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: sequenceType,
                isSuspend: false,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func makeSyntheticSequenceReturnType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        guard let sequenceSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
