import Foundation

/// Synthetic JVM stdlib stubs for kotlin.jvm.optionals extension functions.
extension DataFlowSemaPhase {
    func registerSyntheticJvmOptionalStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJvmOptionalsPkg = ensurePackage(
            path: ["kotlin", "jvm", "optionals"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let optionalsPkgSymbol = symbols.lookup(fqName: kotlinJvmOptionalsPkg)

        let optionalSymbol = ensureClassSymbol(
            named: "Optional",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: optionalSymbol)
        }

        let classTypeParamName = interner.intern("T")
        let optionalFQName = javaUtilPkg + [interner.intern("Optional")]
        let classTypeParamFQName = optionalFQName + [classTypeParamName]
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
        let optionalClassType = types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.invariant(classTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([classTypeParamSymbol], for: optionalSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: optionalSymbol)
        symbols.setPropertyType(optionalClassType, for: optionalSymbol)

        registerOptionalGetOrDefault(
            optionalSymbol: optionalSymbol,
            packageFQName: kotlinJvmOptionalsPkg,
            packageSymbol: optionalsPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerOptionalGetOrDefault(
        optionalSymbol: SymbolID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("getOrDefault")
        let functionFQName = packageFQName + [functionName]

        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(tType)],
            nullability: .nonNull
        )))

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == [tType]
                && signature.returnType == tType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 0
        }) {
            symbols.setExternalLinkName("kk_optional_getOrDefault", for: existing)
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_optional_getOrDefault", for: functionSymbol)

        let defaultValueName = interner.intern("defaultValue")
        let defaultValueSymbol = symbols.define(
            kind: .valueParameter,
            name: defaultValueName,
            fqName: functionFQName + [defaultValueName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: defaultValueSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [tType],
                returnType: tType,
                isSuspend: false,
                valueParameterSymbols: [defaultValueSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
