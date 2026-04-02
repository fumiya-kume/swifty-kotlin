import Foundation

/// Synthetic stdlib stubs for java.lang.ThreadLocal and kotlin.concurrent.getOrSet.
extension DataFlowSemaPhase {
    func registerSyntheticThreadLocalStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let javaLangPkgSymbol = symbols.lookup(fqName: javaLangPkg)
        let concurrentPkgSymbol = symbols.lookup(fqName: concurrentPkg)

        let threadLocalSymbol = ensureClassSymbol(
            named: "ThreadLocal",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLangPkgSymbol {
            symbols.setParentSymbol(javaLangPkgSymbol, for: threadLocalSymbol)
        }

        let classTypeParamName = interner.intern("T")
        let classTypeParamFQName = javaLangPkg + [interner.intern("ThreadLocal"), classTypeParamName]
        let classTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: classTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: classTypeParamName,
                fqName: classTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let classTType = types.make(.typeParam(TypeParamType(
            symbol: classTypeParamSymbol,
            nullability: .nonNull
        )))
        let threadLocalType = types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(classTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([classTypeParamSymbol], for: threadLocalSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: threadLocalSymbol)
        symbols.setPropertyType(threadLocalType, for: threadLocalSymbol)

        registerThreadLocalConstructor(
            ownerSymbol: threadLocalSymbol,
            ownerType: threadLocalType,
            typeParameterSymbol: classTypeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        registerThreadLocalGetOrSet(
            threadLocalSymbol: threadLocalSymbol,
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerThreadLocalConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        typeParameterSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let initFQName = (symbols.symbol(ownerSymbol)?.fqName ?? []) + [initName]
        if let existing = symbols.lookupAll(fqName: initFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == nil
                && signature.parameterTypes.isEmpty
                && signature.returnType == ownerType
                && signature.typeParameterSymbols == [typeParameterSymbol]
                && signature.classTypeParameterCount == 1
        }) {
            symbols.setExternalLinkName("kk_thread_local_new", for: existing)
            return
        }

        let initSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: initSymbol)
        symbols.setExternalLinkName("kk_thread_local_new", for: initSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [],
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParameterSymbol],
                classTypeParameterCount: 1
            ),
            for: initSymbol
        )
    }

    private func registerThreadLocalGetOrSet(
        threadLocalSymbol: SymbolID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("getOrSet")
        let functionFQName = packageFQName + [functionName]

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: functionTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: functionTypeParamName,
                fqName: functionTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let functionTType = types.make(.typeParam(TypeParamType(
            symbol: functionTypeParamSymbol,
            nullability: .nonNull
        )))
        let threadLocalReceiverType = types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(functionTType)],
            nullability: .nonNull
        )))
        let defaultFunctionType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [],
            returnType: functionTType
        )))

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == threadLocalReceiverType
                && signature.parameterTypes == [defaultFunctionType]
                && signature.returnType == functionTType
                && signature.typeParameterSymbols == [functionTypeParamSymbol]
                && signature.classTypeParameterCount == 0
        }) {
            symbols.setExternalLinkName("kk_thread_local_getOrSet", for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_thread_local_getOrSet", for: functionSymbol)

        let defaultName = interner.intern("default")
        let defaultSymbol = symbols.define(
            kind: .valueParameter,
            name: defaultName,
            fqName: functionFQName + [defaultName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: defaultSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: threadLocalReceiverType,
                parameterTypes: [defaultFunctionType],
                returnType: functionTType,
                isSuspend: false,
                valueParameterSymbols: [defaultSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
