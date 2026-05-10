import Foundation

/// Synthetic JVM annotation bridge properties from `kotlin.jvm`.
extension DataFlowSemaPhase {
    func registerSyntheticJvmAnnotationPropertyStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let kotlinJvmPkg = ensurePackage(path: ["kotlin", "jvm"], symbols: symbols, interner: interner)
        let kotlinReflectPkg = ensurePackage(path: ["kotlin", "reflect"], symbols: symbols, interner: interner)

        let annotationSymbol = types.annotationInterfaceSymbol ?? ensureInterfaceSymbol(
            named: "Annotation",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.annotationInterfaceSymbol = annotationSymbol

        let kClassSymbol = types.kClassInterfaceSymbol ?? ensureInterfaceSymbol(
            named: "KClass",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        types.kClassInterfaceSymbol = kClassSymbol

        registerAnnotationClassProperty(
            annotationSymbol: annotationSymbol,
            kClassSymbol: kClassSymbol,
            packageFQName: kotlinJvmPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerAnnotationClassProperty(
        annotationSymbol: SymbolID,
        kClassSymbol: SymbolID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("annotationClass")
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

        let annotationType = types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([annotationType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))
        let returnType = types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_annotation_get_class"

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == typeParamType
        }) {
            symbols.setPropertyType(returnType, for: existing)
            symbols.setExtensionPropertyReceiverType(typeParamType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: typeParamType,
                        parameterTypes: [],
                        returnType: returnType,
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[annotationType]],
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
        symbols.setExtensionPropertyReceiverType(typeParamType, for: propertySymbol)
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
                receiverType: typeParamType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[annotationType]],
                classTypeParameterCount: 0
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }
}
