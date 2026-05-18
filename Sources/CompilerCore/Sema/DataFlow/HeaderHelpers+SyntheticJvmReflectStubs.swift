import Foundation

/// Synthetic JVM reflection bridge stubs from `kotlin.jvm`.
extension DataFlowSemaPhase {
    func registerSyntheticJvmReflectStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJvmPkg = ensurePackage(
            path: ["kotlin", "jvm"],
            symbols: symbols,
            interner: interner
        )
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )

        let classSymbol = registerJavaLangClassStub(
            packageFQName: javaLangPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let kClassSymbol = ensureInterfaceSymbol(
            named: "KClass",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        types.kClassInterfaceSymbol = kClassSymbol

        registerKClassJavaProperty(
            name: "java",
            externalLinkName: "kk_kclass_java",
            returnsNullable: false,
            classSymbol: classSymbol,
            kClassSymbol: kClassSymbol,
            packageFQName: kotlinJvmPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerKClassJavaProperty(
            name: "javaPrimitiveType",
            externalLinkName: "kk_kclass_javaPrimitiveType",
            returnsNullable: true,
            classSymbol: classSymbol,
            kClassSymbol: kClassSymbol,
            packageFQName: kotlinJvmPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerKClassJavaClassProperty(
            classSymbol: classSymbol,
            kClassSymbol: kClassSymbol,
            packageFQName: kotlinJvmPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJavaLangClassStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let classSymbol = ensureClassSymbol(
            named: "Class",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [interner.intern("Class"), typeParamName]
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
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)

        return classSymbol
    }

    private func registerKClassJavaProperty(
        name: String,
        externalLinkName: String,
        returnsNullable: Bool,
        classSymbol: SymbolID,
        kClassSymbol: SymbolID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
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
        let nonNullReturnType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = returnsNullable ? types.makeNullable(nonNullReturnType) : nonNullReturnType

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

        let getterName = interner.intern("get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterName,
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

    private func registerKClassJavaClassProperty(
        classSymbol: SymbolID,
        kClassSymbol: SymbolID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("javaClass")
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
        let returnArgumentType = types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(returnArgumentType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_kclass_javaClass"

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

        let getterName = interner.intern("get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterName,
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
