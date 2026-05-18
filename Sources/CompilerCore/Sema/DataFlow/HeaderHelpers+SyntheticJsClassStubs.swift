import Foundation

/// Synthetic Kotlin/JS `JsClass<T : Any>` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsClassStubs(
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
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )

        let jsClassSymbol = ensureInterfaceSymbol(
            named: "JsClass",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsClassSymbol)
        }

        let typeParamName = interner.intern("T")
        let jsClassFQName = kotlinJsPkg + [interner.intern("JsClass")]
        let typeParamFQName = jsClassFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(jsClassSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let jsClassType = types.make(.classType(ClassType(
            classSymbol: jsClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: jsClassSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: jsClassSymbol)
        symbols.setPropertyType(jsClassType, for: jsClassSymbol)

        registerJsClassNameProperty(
            ownerSymbol: jsClassSymbol,
            propertyType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        let kClassSymbol = types.kClassInterfaceSymbol ?? ensureInterfaceSymbol(
            named: "KClass",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        types.kClassInterfaceSymbol = kClassSymbol
        registerKClassJsProperty(
            jsClassSymbol: jsClassSymbol,
            kClassSymbol: kClassSymbol,
            packageFQName: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJsClassNameProperty(
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern("name")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
            return
        }
        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    private func registerKClassJsProperty(
        jsClassSymbol: SymbolID,
        kClassSymbol: SymbolID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("js")
        let propertyFQName = packageFQName + [propertyName]

        let typeParamName = interner.intern("T")
        let typeParamFQName = propertyFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: jsClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_kclass_js"

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setPropertyType(returnType, for: existing)
            symbols.setExtensionPropertyReceiverType(receiverType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType,
                        typeParameterSymbols: [typeParamSymbol],
                        classTypeParameterCount: 0
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setParentSymbol(propertySymbol, for: typeParamSymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }
}
