import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticPropertyInterfaceStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString],
        kotlinPropertiesPkg: [InternedString]
    ) {
        let anyType = types.anyType
        let knownNames = KnownCompilerNames(interner: interner)

        // Register kotlin.properties.Lazy<T> interface stub used by the existing delegate lowering.
        let legacyLazyInterfaceSymbol = ensureInterfaceSymbol(
            named: "Lazy", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let legacyLazyInterfaceType = types.make(.classType(ClassType(
            classSymbol: legacyLazyInterfaceSymbol, args: [], nullability: .nonNull
        )))

        // Register the stdlib root kotlin.Lazy<out T> interface used by lazyOf(value).
        let rootLazyInterfaceSymbol = ensureInterfaceSymbol(
            named: "Lazy", in: kotlinPkg, symbols: symbols, interner: interner
        )
        let rootLazyTypeParamName = interner.intern("T")
        let rootLazyFQName = kotlinPkg + [interner.intern("Lazy")]
        let rootLazyTypeParamSymbol = symbols.lookup(fqName: rootLazyFQName + [rootLazyTypeParamName]) ?? {
            let symbol = symbols.define(
                kind: .typeParameter,
                name: rootLazyTypeParamName,
                fqName: rootLazyFQName + [rootLazyTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rootLazyInterfaceSymbol, for: symbol)
            return symbol
        }()
        types.setNominalTypeParameterSymbols([rootLazyTypeParamSymbol], for: rootLazyInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: rootLazyInterfaceSymbol)
        let rootLazyTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: rootLazyTypeParamSymbol,
            nullability: .nonNull
        )))
        let rootLazyInterfaceType = types.make(.classType(ClassType(
            classSymbol: rootLazyInterfaceSymbol,
            args: [.invariant(rootLazyTypeParamType)],
            nullability: .nonNull
        )))

        let lazyValueName = interner.intern("value")
        let lazyValueFQName = rootLazyFQName + [lazyValueName]
        if symbols.lookup(fqName: lazyValueFQName) == nil {
            let valueSymbol = symbols.define(
                kind: .property,
                name: lazyValueName,
                fqName: lazyValueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rootLazyInterfaceSymbol, for: valueSymbol)
            symbols.setPropertyType(rootLazyTypeParamType, for: valueSymbol)
            symbols.setExternalLinkName("kk_lazy_get_value", for: valueSymbol)
        }

        let lazyIsInitializedName = interner.intern("isInitialized")
        let lazyIsInitializedFQName = rootLazyFQName + [lazyIsInitializedName]
        if symbols.lookup(fqName: lazyIsInitializedFQName) == nil {
            let isInitializedSymbol = symbols.define(
                kind: .function,
                name: lazyIsInitializedName,
                fqName: lazyIsInitializedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rootLazyInterfaceSymbol, for: isInitializedSymbol)
            symbols.setExternalLinkName("kk_lazy_is_initialized", for: isInitializedSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: rootLazyInterfaceType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [rootLazyTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: isInitializedSymbol
            )
        }

        // Register kotlin.properties.ReadWriteProperty<T, V> interface stub.
        let rwPropertySymbol = ensureInterfaceSymbol(
            named: "ReadWriteProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let rwPropertyType = types.make(.classType(ClassType(
            classSymbol: rwPropertySymbol, args: [], nullability: .nonNull
        )))
        registerPropertyDelegateInterfaceTypeParameters(
            ownerSymbol: rwPropertySymbol,
            ownerPackage: kotlinPropertiesPkg,
            ownerName: "ReadWriteProperty",
            variances: [.in, .invariant],
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Register kotlin.properties.ReadOnlyProperty<in T, out V> interface stub.
        let readOnlyPropertySymbol = ensureInterfaceSymbol(
            named: "ReadOnlyProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        registerPropertyDelegateInterfaceTypeParameters(
            ownerSymbol: readOnlyPropertySymbol,
            ownerPackage: kotlinPropertiesPkg,
            ownerName: "ReadOnlyProperty",
            variances: [.in, .out],
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Register kotlin.reflect.KProperty<out V> interface stub so that
        // `import kotlin.reflect.KProperty` and `KProperty<*>` type references resolve.
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"], symbols: symbols, interner: interner
        )
        registerAssociatedObjectKeyAnnotation(
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        registerFindAssociatedObjectFunction(
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerCreateInstanceFunction(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let kAnnotatedElementSymbol = registerSyntheticKAnnotatedElementStub(
            symbols: symbols, types: types, interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )
        let kDeclarationContainerSymbol = registerSyntheticKDeclarationContainerStub(
            symbols: symbols, types: types, interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )
        let kPropertySymbol = ensureInterfaceSymbol(
            named: "KProperty", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )

        registerPropertyDelegateProviderStub(
            kotlinPropertiesPkg: kotlinPropertiesPkg,
            kPropertySymbol: kPropertySymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-REFLECT-066: Register kotlin.reflect.KType and typeOf<T>() stubs
        registerSyntheticKTypeStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinReflectPkg: kotlinReflectPkg, kotlinPkg: kotlinPkg,
            kAnnotatedElementSymbol: kAnnotatedElementSymbol
        )
        registerSyntheticKVisibilityEnum(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )
        registerSyntheticKParameterStub(
            kAnnotatedElementSymbol: kAnnotatedElementSymbol,
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )

        registerObservablePropertyStub(
            kotlinPropertiesPkg: kotlinPropertiesPkg,
            readWritePropertySymbol: rwPropertySymbol,
            kPropertySymbol: kPropertySymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Register `name` property on KProperty (inherited from KCallable).
        let stringType = types.make(.primitive(.string, .nonNull))
        if let kPropertyInfo = symbols.symbol(kPropertySymbol) {
            let namePropName = interner.intern("name")
            let namePropFQ = kPropertyInfo.fqName + [namePropName]
            if symbols.lookup(fqName: namePropFQ) == nil {
                let namePropSymbol = symbols.define(
                    kind: .property, name: namePropName, fqName: namePropFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kPropertySymbol, for: namePropSymbol)
                symbols.setPropertyType(stringType, for: namePropSymbol)
            }

            let returnTypeName = interner.intern("returnType")
            let returnTypeFQ = kPropertyInfo.fqName + [returnTypeName]
            if symbols.lookup(fqName: returnTypeFQ) == nil {
                let kTypeSymbol = ensureInterfaceSymbol(
                    named: "KType", in: kotlinReflectPkg, symbols: symbols, interner: interner
                )
                let kTypeType = types.make(.classType(ClassType(
                    classSymbol: kTypeSymbol, args: [], nullability: .nonNull
                )))
                let returnTypeSymbol = symbols.define(
                    kind: .property, name: returnTypeName, fqName: returnTypeFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kPropertySymbol, for: returnTypeSymbol)
                symbols.setPropertyType(kTypeType, for: returnTypeSymbol)
            }
        }

        // Also register KProperty0, KProperty1, KMutableProperty, KMutableProperty0, KMutableProperty1
        // as they are commonly used reflect types.
        let kCallableSymbol = ensureInterfaceSymbol(
            named: "KCallable", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        addSyntheticDirectSupertypes(
            [kAnnotatedElementSymbol], to: kCallableSymbol,
            symbols: symbols, types: types
        )
        addSyntheticDirectSupertypes(
            [kCallableSymbol], to: kPropertySymbol,
            symbols: symbols, types: types
        )
        // Register `name` property on KCallable as well.
        if let kCallableInfo = symbols.symbol(kCallableSymbol) {
            let namePropName = interner.intern("name")
            let namePropFQ = kCallableInfo.fqName + [namePropName]
            if symbols.lookup(fqName: namePropFQ) == nil {
                let namePropSymbol = symbols.define(
                    kind: .property, name: namePropName, fqName: namePropFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kCallableSymbol, for: namePropSymbol)
                symbols.setPropertyType(stringType, for: namePropSymbol)
            }
        }
        let kMutablePropertySymbol = ensureInterfaceSymbol(
            named: "KMutableProperty", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kProperty0Symbol = ensureInterfaceSymbol(
            named: "KProperty0", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kProperty1Symbol = ensureInterfaceSymbol(
            named: "KProperty1", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kMutableProperty0Symbol = ensureInterfaceSymbol(
            named: "KMutableProperty0", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kMutableProperty1Symbol = ensureInterfaceSymbol(
            named: "KMutableProperty1", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        registerSyntheticKProperty1Stub(
            kPropertySymbol: kPropertySymbol,
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticKMutableProperty0Stub(
            kMutableProperty0Symbol: kMutableProperty0Symbol,
            kMutablePropertySymbol: kMutablePropertySymbol,
            kProperty0Symbol: kProperty0Symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticKMutableProperty1Stub(
            kMutableProperty1Symbol: kMutableProperty1Symbol,
            kMutablePropertySymbol: kMutablePropertySymbol,
            kProperty1Symbol: kProperty1Symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticKProperty2Stub(
            kPropertySymbol: kPropertySymbol,
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticKMutableProperty2Stub(
            kMutablePropertySymbol: kMutablePropertySymbol,
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Register kotlin.reflect.KFunction<out R> interface stub (STDLIB-REFLECT-063).
        // Store in TypeSystem so subtyping checks can recognise KFunction receivers.
        let kFunctionSymbol = ensureInterfaceSymbol(
            named: "KFunction", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kFunctionInterfaceSymbol = kFunctionSymbol
        addSyntheticDirectSupertypes(
            [kCallableSymbol], to: kFunctionSymbol,
            symbols: symbols, types: types
        )

        let kClassifierSymbol = ensureInterfaceSymbol(
            named: "KClassifier", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kClassifierInterfaceSymbol = kClassifierSymbol
        let kClassSymbol = ensureInterfaceSymbol(
            named: "KClass", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kClassInterfaceSymbol = kClassSymbol
        addSyntheticDirectSupertypes(
            [kDeclarationContainerSymbol, kAnnotatedElementSymbol, kClassifierSymbol], to: kClassSymbol,
            symbols: symbols, types: types
        )

        // Register KFunction member properties: name, isSuspend, parameters (STDLIB-REFLECT-063).
        if let kFunctionInfo = symbols.symbol(kFunctionSymbol) {
            // name: String
            let namePropName = interner.intern("name")
            let namePropFQ = kFunctionInfo.fqName + [namePropName]
            if symbols.lookup(fqName: namePropFQ) == nil {
                let namePropSymbol = symbols.define(
                    kind: .property, name: namePropName, fqName: namePropFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kFunctionSymbol, for: namePropSymbol)
                symbols.setPropertyType(stringType, for: namePropSymbol)
            }

            // isSuspend: Boolean
            let isSuspendName = interner.intern("isSuspend")
            let isSuspendFQ = kFunctionInfo.fqName + [isSuspendName]
            if symbols.lookup(fqName: isSuspendFQ) == nil {
                let isSuspendSymbol = symbols.define(
                    kind: .property, name: isSuspendName, fqName: isSuspendFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kFunctionSymbol, for: isSuspendSymbol)
                symbols.setPropertyType(types.booleanType, for: isSuspendSymbol)
            }

            // parameters: Any (patched to List<Any?> later by patchKFunctionParametersType)
            let paramsName = interner.intern("parameters")
            let paramsFQ = kFunctionInfo.fqName + [paramsName]
            if symbols.lookup(fqName: paramsFQ) == nil {
                let paramsSymbol = symbols.define(
                    kind: .property, name: paramsName, fqName: paramsFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kFunctionSymbol, for: paramsSymbol)
                symbols.setPropertyType(anyType, for: paramsSymbol)
            }
        }

        // Register `lazy` as a top-level function in the kotlin package.
        // Kotlin signature: fun <T> lazy(initializer: () -> T): Lazy<T>
        let lazyName = interner.intern("lazy")
        let lazyFQName = kotlinPkg + [lazyName]
        if symbols.lookup(fqName: lazyFQName) == nil {
            let lazySymbol = symbols.define(
                kind: .function, name: lazyName, fqName: lazyFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            let initializerType = types.make(.functionType(FunctionType(
                params: [], returnType: anyType, isSuspend: false, nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [initializerType], returnType: legacyLazyInterfaceType),
                for: lazySymbol
            )
        }

        // Kotlin signature: fun <T> lazyOf(value: T): Lazy<T>
        let lazyOfName = interner.intern("lazyOf")
        let lazyOfFQName = kotlinPkg + [lazyOfName]
        if symbols.lookup(fqName: lazyOfFQName) == nil {
            let lazyOfSymbol = symbols.define(
                kind: .function,
                name: lazyOfName,
                fqName: lazyOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: lazyOfSymbol)
            }
            symbols.setExternalLinkName("kk_lazy_of", for: lazyOfSymbol)

            let valueTypeParamName = interner.intern("T")
            let valueTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: valueTypeParamName,
                fqName: lazyOfFQName + [valueTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(lazyOfSymbol, for: valueTypeParamSymbol)

            let valueParamName = interner.intern("value")
            let valueParamSymbol = symbols.define(
                kind: .valueParameter,
                name: valueParamName,
                fqName: lazyOfFQName + [valueParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(lazyOfSymbol, for: valueParamSymbol)

            let valueType = types.make(.typeParam(TypeParamType(
                symbol: valueTypeParamSymbol,
                nullability: .nonNull
            )))
            let returnType = types.make(.classType(ClassType(
                classSymbol: rootLazyInterfaceSymbol,
                args: [.invariant(valueType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [valueType],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [valueParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [valueTypeParamSymbol]
                ),
                for: lazyOfSymbol
            )
        }

        // Also register `lazy` with explicit thread-safety mode overload.
        // Kotlin signature: fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T>
        let lazyModeFQName = kotlinPkg + [lazyName, interner.intern("mode")]
        if symbols.lookup(fqName: lazyModeFQName) == nil {
            let lazyModeSymbol = symbols.define(
                kind: .function, name: lazyName, fqName: lazyModeFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            let initializerType = types.make(.functionType(FunctionType(
                params: [], returnType: anyType, isSuspend: false, nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [anyType, initializerType], returnType: legacyLazyInterfaceType),
                for: lazyModeSymbol
            )
        }

        // Register `Delegates` as an object in kotlin.properties.
        let delegatesName = interner.intern("Delegates")
        let delegatesFQName = kotlinPropertiesPkg + [delegatesName]
        let delegatesSymbol: SymbolID = if let existing = symbols.lookup(fqName: delegatesFQName) {
            existing
        } else {
            symbols.define(
                kind: .object, name: delegatesName, fqName: delegatesFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let delegatesType = types.make(.classType(ClassType(
            classSymbol: delegatesSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(delegatesType, for: delegatesSymbol)

        guard let ownerSym = symbols.symbol(delegatesSymbol) else { return }

        for memberName in ["observable", "vetoable"] {
            let internedName = interner.intern(memberName)
            let fqName = ownerSym.fqName + [internedName]
            guard symbols.lookup(fqName: fqName) == nil else { continue }
            let funcSymbol = symbols.define(
                kind: .function, name: internedName, fqName: fqName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(delegatesSymbol, for: funcSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: delegatesType, parameterTypes: [anyType], returnType: rwPropertyType
                ),
                for: funcSymbol
            )
        }

        // Register Delegates.notNull<T>(): ReadWriteProperty<Any?, T>
        let notNullName = knownNames.notNull
        let notNullFQName = ownerSym.fqName + [notNullName]
        if symbols.lookup(fqName: notNullFQName) == nil {
            let notNullSymbol = symbols.define(
                kind: .function, name: notNullName, fqName: notNullFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(delegatesSymbol, for: notNullSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: delegatesType, parameterTypes: [], returnType: rwPropertyType
                ),
                for: notNullSymbol
            )
        }
    }

    private func registerPropertyDelegateInterfaceTypeParameters(
        ownerSymbol: SymbolID,
        ownerPackage: [InternedString],
        ownerName: String,
        variances: [TypeVariance],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let ownerName = interner.intern(ownerName)
        let ownerFQName = ownerPackage + [ownerName]
        let typeParamNames = ["T", "V"].map { interner.intern($0) }
        let typeParamSymbols = typeParamNames.map { name in
            let fqName = ownerFQName + [name]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: symbol)
            return symbol
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: ownerSymbol)
        types.setNominalTypeParameterVariances(variances, for: ownerSymbol)
    }

    private func registerPropertyDelegateProviderStub(
        kotlinPropertiesPkg: [InternedString],
        kPropertySymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let providerName = interner.intern("PropertyDelegateProvider")
        let providerFQName = kotlinPropertiesPkg + [providerName]
        let providerSymbol: SymbolID
        if let existing = symbols.lookup(fqName: providerFQName) {
            providerSymbol = existing
            symbols.insertFlags([.synthetic, .funInterface], for: existing)
        } else {
            providerSymbol = symbols.define(
                kind: .interface,
                name: providerName,
                fqName: providerFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .funInterface]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPropertiesPkg), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: providerSymbol)
            }
        }

        let typeParameterNames = ["T", "D"].map { interner.intern($0) }
        let typeParameterSymbols = typeParameterNames.map { name in
            let fqName = providerFQName + [name]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(providerSymbol, for: symbol)
            return symbol
        }
        guard typeParameterSymbols.count == 2 else {
            return
        }
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: providerSymbol)
        types.setNominalTypeParameterVariances([.in, .out], for: providerSymbol)

        let thisRefType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbols[0],
            nullability: .nonNull
        )))
        let delegateType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbols[1],
            nullability: .nonNull
        )))
        let providerType = types.make(.classType(ClassType(
            classSymbol: providerSymbol,
            args: [.invariant(thisRefType), .invariant(delegateType)],
            nullability: .nonNull
        )))
        let kPropertyType = types.make(.classType(ClassType(
            classSymbol: kPropertySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let provideName = interner.intern("provideDelegate")
        let provideFQName = providerFQName + [provideName]
        if symbols.lookup(fqName: provideFQName) != nil {
            return
        }
        let provideSymbol = symbols.define(
            kind: .function,
            name: provideName,
            fqName: provideFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType, .operatorFunction]
        )
        symbols.setParentSymbol(providerSymbol, for: provideSymbol)

        let thisRefName = interner.intern("thisRef")
        let propertyName = interner.intern("property")
        let thisRefSymbol = symbols.define(
            kind: .valueParameter,
            name: thisRefName,
            fqName: provideFQName + [thisRefName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let propertySymbol = symbols.define(
            kind: .valueParameter,
            name: propertyName,
            fqName: provideFQName + [propertyName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(provideSymbol, for: thisRefSymbol)
        symbols.setParentSymbol(provideSymbol, for: propertySymbol)
        symbols.setPropertyType(thisRefType, for: thisRefSymbol)
        symbols.setPropertyType(kPropertyType, for: propertySymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: providerType,
                parameterTypes: [thisRefType, kPropertyType],
                returnType: delegateType,
                valueParameterSymbols: [thisRefSymbol, propertySymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 2
            ),
            for: provideSymbol
        )
    }

    private func registerObservablePropertyStub(
        kotlinPropertiesPkg: [InternedString],
        readWritePropertySymbol: SymbolID,
        kPropertySymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let observableName = interner.intern("ObservableProperty")
        let observableFQName = kotlinPropertiesPkg + [observableName]
        let observableSymbol: SymbolID
        if let existing = symbols.lookup(fqName: observableFQName) {
            observableSymbol = existing
            symbols.insertFlags([.abstractType, .synthetic], for: existing)
        } else {
            observableSymbol = symbols.define(
                kind: .class,
                name: observableName,
                fqName: observableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPropertiesPkg), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: observableSymbol)
            }
        }

        let vName = interner.intern("V")
        let vFQName = observableFQName + [vName]
        let vSymbol: SymbolID
        if let existing = symbols.lookup(fqName: vFQName) {
            vSymbol = existing
        } else {
            vSymbol = symbols.define(
                kind: .typeParameter,
                name: vName,
                fqName: vFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(observableSymbol, for: vSymbol)
        }

        types.setNominalTypeParameterSymbols([vSymbol], for: observableSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: observableSymbol)

        let vType = types.make(.typeParam(TypeParamType(symbol: vSymbol, nullability: .nonNull)))
        let observableType = types.make(.classType(ClassType(
            classSymbol: observableSymbol,
            args: [.invariant(vType)],
            nullability: .nonNull
        )))
        let nullableAny = types.makeNullable(types.anyType)
        let kPropertyType = types.make(.classType(ClassType(
            classSymbol: kPropertySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        symbols.setDirectSupertypes([readWritePropertySymbol], for: observableSymbol)
        types.setNominalDirectSupertypes([readWritePropertySymbol], for: observableSymbol)
        let readWriteArgs: [TypeArg] = [.in(nullableAny), .invariant(vType)]
        symbols.setSupertypeTypeArgs(readWriteArgs, for: observableSymbol, supertype: readWritePropertySymbol)
        types.setNominalSupertypeTypeArgs(readWriteArgs, for: observableSymbol, supertype: readWritePropertySymbol)

        registerObservablePropertyConstructor(
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            valueType: vType,
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )

        registerObservablePropertyFunction(
            named: "beforeChange",
            visibility: .protected,
            flags: [.synthetic, .openType],
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            parameterNames: ["property", "oldValue", "newValue"],
            parameterTypes: [kPropertyType, vType, vType],
            returnType: types.booleanType,
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )
        registerObservablePropertyFunction(
            named: "afterChange",
            visibility: .protected,
            flags: [.synthetic, .openType],
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            parameterNames: ["property", "oldValue", "newValue"],
            parameterTypes: [kPropertyType, vType, vType],
            returnType: types.unitType,
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )
        registerObservablePropertyFunction(
            named: "getValue",
            flags: [.synthetic, .operatorFunction, .overrideMember, .openType],
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            parameterNames: ["thisRef", "property"],
            parameterTypes: [nullableAny, kPropertyType],
            returnType: vType,
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )
        registerObservablePropertyFunction(
            named: "setValue",
            flags: [.synthetic, .operatorFunction, .overrideMember, .openType],
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            parameterNames: ["thisRef", "property", "value"],
            parameterTypes: [nullableAny, kPropertyType, vType],
            returnType: types.unitType,
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )
        registerObservablePropertyFunction(
            named: "toString",
            flags: [.synthetic, .overrideMember, .openType],
            ownerSymbol: observableSymbol,
            ownerFQName: observableFQName,
            ownerType: observableType,
            parameterNames: [],
            parameterTypes: [],
            returnType: types.make(.primitive(.string, .nonNull)),
            typeParameterSymbol: vSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerObservablePropertyConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        valueType: TypeID,
        typeParameterSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let initFQName = ownerFQName + [initName]
        if symbols.lookup(fqName: initFQName) != nil {
            return
        }
        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let parameterName = interner.intern("initialValue")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: initFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
        symbols.setPropertyType(valueType, for: parameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [valueType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParameterSymbol],
                classTypeParameterCount: 1
            ),
            for: constructorSymbol
        )
    }

    private func registerObservablePropertyFunction(
        named name: String,
        visibility: Visibility = .public,
        flags: SymbolFlags,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        parameterNames: [String],
        parameterTypes: [TypeID],
        returnType: TypeID,
        typeParameterSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = ownerFQName + [functionName]
        if symbols.lookup(fqName: functionFQName) != nil {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: visibility,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)

        var parameterSymbols: [SymbolID] = []
        for (parameterNameText, parameterType) in zip(parameterNames, parameterTypes) {
            let parameterName = interner.intern(parameterNameText)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameterType, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count),
                typeParameterSymbols: [typeParameterSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
    }

    // STDLIB-REFLECT-068: Register KAnnotatedElement with its annotations surface.
    private func registerSyntheticKAnnotatedElementStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) -> SymbolID {
        let kAnnotatedElementSymbol = ensureInterfaceSymbol(
            named: "KAnnotatedElement", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kAnnotatedElementInterfaceSymbol = kAnnotatedElementSymbol

        guard let kAnnotatedElementInfo = symbols.symbol(kAnnotatedElementSymbol) else {
            return kAnnotatedElementSymbol
        }
        let annotationsName = interner.intern("annotations")
        let annotationsFQ = kAnnotatedElementInfo.fqName + [annotationsName]
        if symbols.lookup(fqName: annotationsFQ) == nil {
            let annotationsSymbol = symbols.define(
                kind: .property, name: annotationsName, fqName: annotationsFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(kAnnotatedElementSymbol, for: annotationsSymbol)
            symbols.setPropertyType(types.anyType, for: annotationsSymbol)
        }

        return kAnnotatedElementSymbol
    }

    // STDLIB-REFLECT-069: Register KDeclarationContainer with its members surface.
    private func registerSyntheticKDeclarationContainerStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) -> SymbolID {
        let kDeclarationContainerSymbol = ensureInterfaceSymbol(
            named: "KDeclarationContainer", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kDeclarationContainerInterfaceSymbol = kDeclarationContainerSymbol

        guard let kDeclarationContainerInfo = symbols.symbol(kDeclarationContainerSymbol) else {
            return kDeclarationContainerSymbol
        }
        let membersName = interner.intern("members")
        let membersFQ = kDeclarationContainerInfo.fqName + [membersName]
        if symbols.lookup(fqName: membersFQ) == nil {
            let membersSymbol = symbols.define(
                kind: .property, name: membersName, fqName: membersFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(kDeclarationContainerSymbol, for: membersSymbol)
            symbols.setPropertyType(types.anyType, for: membersSymbol)
        }

        return kDeclarationContainerSymbol
    }

    // STDLIB-REFLECT-TYPE-009: Register KMutableProperty<V> as a mutable KProperty surface.
    private func registerSyntheticKMutablePropertyStub(
        kMutablePropertySymbol: SymbolID,
        kPropertySymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kMutablePropertyInfo = symbols.symbol(kMutablePropertySymbol) else {
            return
        }

        let valueName = interner.intern("V")
        let valueFQ = kMutablePropertyInfo.fqName + [valueName]
        let valueParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueFQ) {
            valueParamSymbol = existing
        } else {
            valueParamSymbol = symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kMutablePropertySymbol, for: valueParamSymbol)
        }

        types.setNominalTypeParameterSymbols([valueParamSymbol], for: kMutablePropertySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: kMutablePropertySymbol)

        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueParamSymbol,
            nullability: .nonNull
        )))
        addSyntheticDirectSupertypes([kPropertySymbol], to: kMutablePropertySymbol, symbols: symbols, types: types)
        let kPropertyArgs: [TypeArg] = [.invariant(valueType)]
        symbols.setSupertypeTypeArgs(kPropertyArgs, for: kMutablePropertySymbol, supertype: kPropertySymbol)
        types.setNominalSupertypeTypeArgs(kPropertyArgs, for: kMutablePropertySymbol, supertype: kPropertySymbol)
    }

    // STDLIB-REFLECT-TYPE-015: Register KProperty0<out V> with callable surface.
    private func registerSyntheticKProperty0Stub(
        kPropertySymbol: SymbolID,
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kProperty0Symbol = ensureInterfaceSymbol(
            named: "KProperty0", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        guard let kProperty0Info = symbols.symbol(kProperty0Symbol) else { return }

        let valueName = interner.intern("V")
        let valueFQ = kProperty0Info.fqName + [valueName]
        let valueParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueFQ) {
            valueParamSymbol = existing
        } else {
            valueParamSymbol = symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kProperty0Symbol, for: valueParamSymbol)
        }

        types.setNominalTypeParameterSymbols([valueParamSymbol], for: kProperty0Symbol)
        types.setNominalTypeParameterVariances([.out], for: kProperty0Symbol)

        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueParamSymbol,
            nullability: .nonNull
        )))
        addSyntheticDirectSupertypes([kPropertySymbol], to: kProperty0Symbol, symbols: symbols, types: types)
        let valueArgs: [TypeArg] = [.out(valueType)]
        symbols.setSupertypeTypeArgs(valueArgs, for: kProperty0Symbol, supertype: kPropertySymbol)
        types.setNominalSupertypeTypeArgs(valueArgs, for: kProperty0Symbol, supertype: kPropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kProperty0Symbol,
            args: valueArgs,
            nullability: .nonNull
        )))
        registerSyntheticKProperty2Function(
            named: "get",
            parameterNames: [],
            ownerSymbol: kProperty0Symbol,
            ownerFQName: kProperty0Info.fqName,
            receiverType: receiverType,
            parameterTypes: [],
            returnType: valueType,
            typeParameterSymbols: [valueParamSymbol],
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "getDelegate",
            parameterNames: [],
            ownerSymbol: kProperty0Symbol,
            ownerFQName: kProperty0Info.fqName,
            receiverType: receiverType,
            parameterTypes: [],
            returnType: types.nullableAnyType,
            typeParameterSymbols: [valueParamSymbol],
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "invoke",
            parameterNames: [],
            ownerSymbol: kProperty0Symbol,
            ownerFQName: kProperty0Info.fqName,
            receiverType: receiverType,
            parameterTypes: [],
            returnType: valueType,
            typeParameterSymbols: [valueParamSymbol],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    // STDLIB-REFLECT-TYPE-022: Register KVisibility enum entries.
    private func registerSyntheticKVisibilityEnum(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        let enumName = interner.intern("KVisibility")
        let enumFQName = kotlinReflectPkg + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinReflectPkg), packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entryNameRaw in ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"] {
            let entryName = interner.intern(entryNameRaw)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    // STDLIB-REFLECT-TYPE-010: Register KMutableProperty0<V> with mutable zero-receiver surface.
    private func registerSyntheticKMutableProperty0Stub(
        kMutableProperty0Symbol: SymbolID,
        kMutablePropertySymbol: SymbolID,
        kProperty0Symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kMutableProperty0Info = symbols.symbol(kMutableProperty0Symbol) else {
            return
        }

        let valueName = interner.intern("V")
        let valueFQ = kMutableProperty0Info.fqName + [valueName]
        let valueParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueFQ) {
            valueParamSymbol = existing
        } else {
            valueParamSymbol = symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kMutableProperty0Symbol, for: valueParamSymbol)
        }

        types.setNominalTypeParameterSymbols([valueParamSymbol], for: kMutableProperty0Symbol)
        types.setNominalTypeParameterVariances([.invariant], for: kMutableProperty0Symbol)

        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueParamSymbol,
            nullability: .nonNull
        )))
        addSyntheticDirectSupertypes(
            [kProperty0Symbol, kMutablePropertySymbol],
            to: kMutableProperty0Symbol,
            symbols: symbols,
            types: types
        )
        let valueArgs: [TypeArg] = [.invariant(valueType)]
        symbols.setSupertypeTypeArgs(valueArgs, for: kMutableProperty0Symbol, supertype: kProperty0Symbol)
        symbols.setSupertypeTypeArgs(valueArgs, for: kMutableProperty0Symbol, supertype: kMutablePropertySymbol)
        types.setNominalSupertypeTypeArgs(valueArgs, for: kMutableProperty0Symbol, supertype: kProperty0Symbol)
        types.setNominalSupertypeTypeArgs(valueArgs, for: kMutableProperty0Symbol, supertype: kMutablePropertySymbol)

        let function0FQName = [interner.intern("kotlin"), interner.intern("Function"), interner.intern("Function0")]
        if let function0Symbol = symbols.lookup(fqName: function0FQName) {
            addSyntheticDirectSupertypes([function0Symbol], to: kMutableProperty0Symbol, symbols: symbols, types: types)
            let functionArgs: [TypeArg] = [.out(valueType)]
            symbols.setSupertypeTypeArgs(functionArgs, for: kMutableProperty0Symbol, supertype: function0Symbol)
            types.setNominalSupertypeTypeArgs(functionArgs, for: kMutableProperty0Symbol, supertype: function0Symbol)
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kMutableProperty0Symbol,
            args: valueArgs,
            nullability: .nonNull
        )))
        registerSyntheticKProperty2Function(
            named: "set",
            parameterNames: ["value"],
            ownerSymbol: kMutableProperty0Symbol,
            ownerFQName: kMutableProperty0Info.fqName,
            receiverType: receiverType,
            parameterTypes: [valueType],
            returnType: types.unitType,
            typeParameterSymbols: [valueParamSymbol],
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
    }

    // STDLIB-REFLECT-TYPE-016: Register KProperty1<T, out V> with callable surface.
    private func registerSyntheticKProperty1Stub(
        kPropertySymbol: SymbolID,
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kProperty1Symbol = ensureInterfaceSymbol(
            named: "KProperty1", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        guard let kProperty1Info = symbols.symbol(kProperty1Symbol) else { return }

        let typeParamSpecs: [(name: String, variance: TypeVariance)] = [
            ("T", .invariant),
            ("V", .out),
        ]
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []
        for spec in typeParamSpecs {
            let paramName = interner.intern(spec.name)
            let paramFQ = kProperty1Info.fqName + [paramName]
            let paramSymbol: SymbolID
            if let existing = symbols.lookup(fqName: paramFQ) {
                paramSymbol = existing
            } else {
                paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQ,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(kProperty1Symbol, for: paramSymbol)
            }
            typeParamSymbols.append(paramSymbol)
            typeParamTypes.append(types.make(.typeParam(TypeParamType(
                symbol: paramSymbol,
                nullability: .nonNull
            ))))
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: kProperty1Symbol)
        types.setNominalTypeParameterVariances(typeParamSpecs.map(\.variance), for: kProperty1Symbol)

        addSyntheticDirectSupertypes([kPropertySymbol], to: kProperty1Symbol, symbols: symbols, types: types)
        symbols.setSupertypeTypeArgs([.out(typeParamTypes[1])], for: kProperty1Symbol, supertype: kPropertySymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamTypes[1])], for: kProperty1Symbol, supertype: kPropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kProperty1Symbol,
            args: [.invariant(typeParamTypes[0]), .out(typeParamTypes[1])],
            nullability: .nonNull
        )))
        registerSyntheticKProperty2Function(
            named: "get",
            parameterNames: ["receiver"],
            ownerSymbol: kProperty1Symbol,
            ownerFQName: kProperty1Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0]],
            returnType: typeParamTypes[1],
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "getDelegate",
            parameterNames: ["receiver"],
            ownerSymbol: kProperty1Symbol,
            ownerFQName: kProperty1Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0]],
            returnType: types.nullableAnyType,
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "invoke",
            parameterNames: ["p1"],
            ownerSymbol: kProperty1Symbol,
            ownerFQName: kProperty1Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0]],
            returnType: typeParamTypes[1],
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    // STDLIB-REFLECT-TYPE-011: Register KMutableProperty1<T, V> with mutable one-receiver surface.
    private func registerSyntheticKMutableProperty1Stub(
        kMutableProperty1Symbol: SymbolID,
        kMutablePropertySymbol: SymbolID,
        kProperty1Symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kMutableProperty1Info = symbols.symbol(kMutableProperty1Symbol) else {
            return
        }

        let typeParamSpecs: [(name: String, variance: TypeVariance)] = [
            ("T", .invariant),
            ("V", .invariant),
        ]
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []
        for spec in typeParamSpecs {
            let paramName = interner.intern(spec.name)
            let paramFQ = kMutableProperty1Info.fqName + [paramName]
            let paramSymbol: SymbolID
            if let existing = symbols.lookup(fqName: paramFQ) {
                paramSymbol = existing
            } else {
                paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQ,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(kMutableProperty1Symbol, for: paramSymbol)
            }
            typeParamSymbols.append(paramSymbol)
            typeParamTypes.append(types.make(.typeParam(TypeParamType(
                symbol: paramSymbol,
                nullability: .nonNull
            ))))
        }

        types.setNominalTypeParameterSymbols(typeParamSymbols, for: kMutableProperty1Symbol)
        types.setNominalTypeParameterVariances(typeParamSpecs.map(\.variance), for: kMutableProperty1Symbol)

        addSyntheticDirectSupertypes(
            [kProperty1Symbol, kMutablePropertySymbol],
            to: kMutableProperty1Symbol,
            symbols: symbols,
            types: types
        )
        let kProperty1Args: [TypeArg] = [.invariant(typeParamTypes[0]), .invariant(typeParamTypes[1])]
        let kMutablePropertyArgs: [TypeArg] = [.invariant(typeParamTypes[1])]
        symbols.setSupertypeTypeArgs(kProperty1Args, for: kMutableProperty1Symbol, supertype: kProperty1Symbol)
        symbols.setSupertypeTypeArgs(kMutablePropertyArgs, for: kMutableProperty1Symbol, supertype: kMutablePropertySymbol)
        types.setNominalSupertypeTypeArgs(kProperty1Args, for: kMutableProperty1Symbol, supertype: kProperty1Symbol)
        types.setNominalSupertypeTypeArgs(kMutablePropertyArgs, for: kMutableProperty1Symbol, supertype: kMutablePropertySymbol)

        let function1FQName = [interner.intern("kotlin"), interner.intern("Function"), interner.intern("Function1")]
        if let function1Symbol = symbols.lookup(fqName: function1FQName) {
            addSyntheticDirectSupertypes([function1Symbol], to: kMutableProperty1Symbol, symbols: symbols, types: types)
            let functionArgs: [TypeArg] = [.out(typeParamTypes[1]), .in(typeParamTypes[0])]
            symbols.setSupertypeTypeArgs(functionArgs, for: kMutableProperty1Symbol, supertype: function1Symbol)
            types.setNominalSupertypeTypeArgs(functionArgs, for: kMutableProperty1Symbol, supertype: function1Symbol)
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kMutableProperty1Symbol,
            args: kProperty1Args,
            nullability: .nonNull
        )))
        registerSyntheticKProperty2Function(
            named: "set",
            parameterNames: ["receiver", "value"],
            ownerSymbol: kMutableProperty1Symbol,
            ownerFQName: kMutableProperty1Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0], typeParamTypes[1]],
            returnType: types.unitType,
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
    }

    // STDLIB-REFLECT-070: Register KProperty2<D, E, out V> with callable surface.
    private func registerSyntheticKProperty2Stub(
        kPropertySymbol: SymbolID,
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kProperty2Symbol = ensureInterfaceSymbol(
            named: "KProperty2", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        guard let kProperty2Info = symbols.symbol(kProperty2Symbol) else { return }

        let typeParamSpecs: [(name: String, variance: TypeVariance)] = [
            ("D", .invariant),
            ("E", .invariant),
            ("V", .out),
        ]
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []
        for spec in typeParamSpecs {
            let paramName = interner.intern(spec.name)
            let paramFQ = kProperty2Info.fqName + [paramName]
            let paramSymbol: SymbolID
            if let existing = symbols.lookup(fqName: paramFQ) {
                paramSymbol = existing
            } else {
                paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQ,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(kProperty2Symbol, for: paramSymbol)
            }
            typeParamSymbols.append(paramSymbol)
            typeParamTypes.append(types.make(.typeParam(TypeParamType(
                symbol: paramSymbol,
                nullability: .nonNull
            ))))
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: kProperty2Symbol)
        types.setNominalTypeParameterVariances(typeParamSpecs.map(\.variance), for: kProperty2Symbol)

        addSyntheticDirectSupertypes([kPropertySymbol], to: kProperty2Symbol, symbols: symbols, types: types)
        symbols.setSupertypeTypeArgs([.out(typeParamTypes[2])], for: kProperty2Symbol, supertype: kPropertySymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamTypes[2])], for: kProperty2Symbol, supertype: kPropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kProperty2Symbol,
            args: [.invariant(typeParamTypes[0]), .invariant(typeParamTypes[1]), .out(typeParamTypes[2])],
            nullability: .nonNull
        )))

        registerSyntheticKProperty2Function(
            named: "get",
            parameterNames: ["receiver1", "receiver2"],
            ownerSymbol: kProperty2Symbol,
            ownerFQName: kProperty2Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0], typeParamTypes[1]],
            returnType: typeParamTypes[2],
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "getDelegate",
            parameterNames: ["receiver1", "receiver2"],
            ownerSymbol: kProperty2Symbol,
            ownerFQName: kProperty2Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0], typeParamTypes[1]],
            returnType: types.nullableAnyType,
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKProperty2Function(
            named: "invoke",
            parameterNames: ["p1", "p2"],
            ownerSymbol: kProperty2Symbol,
            ownerFQName: kProperty2Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0], typeParamTypes[1]],
            returnType: typeParamTypes[2],
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticKProperty2Function(
        named name: String,
        parameterNames: [String],
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID],
        flags: SymbolFlags,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQ = ownerFQName + [functionName]
        guard symbols.lookup(fqName: functionFQ) == nil else { return }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQ,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameterNameRaw in parameterNames {
            let parameterName = interner.intern(parameterNameRaw)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQ + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: typeParameterSymbols.count
            ),
            for: functionSymbol
        )
    }

    // STDLIB-REFLECT-071: Register KMutableProperty2<D, E, V> with mutable property surface.
    private func registerSyntheticKMutableProperty2Stub(
        kMutablePropertySymbol: SymbolID,
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kProperty2Symbol = symbols.lookup(fqName: kotlinReflectPkg + [interner.intern("KProperty2")]) else {
            return
        }
        let kMutableProperty2Symbol = ensureInterfaceSymbol(
            named: "KMutableProperty2", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        guard let kMutableProperty2Info = symbols.symbol(kMutableProperty2Symbol) else { return }

        let typeParamSpecs: [(name: String, variance: TypeVariance)] = [
            ("D", .invariant),
            ("E", .invariant),
            ("V", .invariant),
        ]
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []
        for spec in typeParamSpecs {
            let paramName = interner.intern(spec.name)
            let paramFQ = kMutableProperty2Info.fqName + [paramName]
            let paramSymbol: SymbolID
            if let existing = symbols.lookup(fqName: paramFQ) {
                paramSymbol = existing
            } else {
                paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQ,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(kMutableProperty2Symbol, for: paramSymbol)
            }
            typeParamSymbols.append(paramSymbol)
            typeParamTypes.append(types.make(.typeParam(TypeParamType(
                symbol: paramSymbol,
                nullability: .nonNull
            ))))
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: kMutableProperty2Symbol)
        types.setNominalTypeParameterVariances(typeParamSpecs.map(\.variance), for: kMutableProperty2Symbol)

        addSyntheticDirectSupertypes(
            [kProperty2Symbol, kMutablePropertySymbol],
            to: kMutableProperty2Symbol,
            symbols: symbols,
            types: types
        )
        let kProperty2Args: [TypeArg] = [
            .invariant(typeParamTypes[0]),
            .invariant(typeParamTypes[1]),
            .invariant(typeParamTypes[2]),
        ]
        let kMutablePropertyArgs: [TypeArg] = [.invariant(typeParamTypes[2])]
        symbols.setSupertypeTypeArgs(kProperty2Args, for: kMutableProperty2Symbol, supertype: kProperty2Symbol)
        symbols.setSupertypeTypeArgs(kMutablePropertyArgs, for: kMutableProperty2Symbol, supertype: kMutablePropertySymbol)
        types.setNominalSupertypeTypeArgs(kProperty2Args, for: kMutableProperty2Symbol, supertype: kProperty2Symbol)
        types.setNominalSupertypeTypeArgs(kMutablePropertyArgs, for: kMutableProperty2Symbol, supertype: kMutablePropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: kMutableProperty2Symbol,
            args: [.invariant(typeParamTypes[0]), .invariant(typeParamTypes[1]), .invariant(typeParamTypes[2])],
            nullability: .nonNull
        )))

        registerSyntheticKProperty2Function(
            named: "set",
            parameterNames: ["receiver1", "receiver2", "value"],
            ownerSymbol: kMutableProperty2Symbol,
            ownerFQName: kMutableProperty2Info.fqName,
            receiverType: receiverType,
            parameterTypes: [typeParamTypes[0], typeParamTypes[1], typeParamTypes[2]],
            returnType: types.unitType,
            typeParameterSymbols: typeParamSymbols,
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
    }

    func patchKPropertyFunctionSupertypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let functionPkg = [interner.intern("kotlin"), interner.intern("Function")]
        if let kProperty1Symbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KProperty1")]),
           let function1Symbol = symbols.lookup(fqName: functionPkg + [interner.intern("Function1")])
        {
            let typeParams = types.nominalTypeParameterSymbols(for: kProperty1Symbol)
            if typeParams.count == 2 {
                let receiverType = types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
                let valueType = types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
                addSyntheticDirectSupertypes([function1Symbol], to: kProperty1Symbol, symbols: symbols, types: types)
                let function1Args: [TypeArg] = [.out(valueType), .in(receiverType)]
                symbols.setSupertypeTypeArgs(function1Args, for: kProperty1Symbol, supertype: function1Symbol)
                types.setNominalSupertypeTypeArgs(function1Args, for: kProperty1Symbol, supertype: function1Symbol)
            }
        }

        guard let kProperty2Symbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KProperty2")]),
              let function2Symbol = symbols.lookup(fqName: functionPkg + [interner.intern("Function2")])
        else {
            return
        }
        let typeParams = types.nominalTypeParameterSymbols(for: kProperty2Symbol)
        guard typeParams.count == 3 else { return }
        let dType = types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let eType = types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        let vType = types.make(.typeParam(TypeParamType(symbol: typeParams[2], nullability: .nonNull)))
        addSyntheticDirectSupertypes([function2Symbol], to: kProperty2Symbol, symbols: symbols, types: types)
        let function2Args: [TypeArg] = [.out(vType), .in(dType), .in(eType)]
        symbols.setSupertypeTypeArgs(function2Args, for: kProperty2Symbol, supertype: function2Symbol)
        types.setNominalSupertypeTypeArgs(function2Args, for: kProperty2Symbol, supertype: function2Symbol)
    }

    func patchKMutableProperty0FunctionSupertype(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let functionPkg = [interner.intern("kotlin"), interner.intern("Function")]
        guard let kMutableProperty0Symbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KMutableProperty0")]),
              let function0Symbol = symbols.lookup(fqName: functionPkg + [interner.intern("Function0")])
        else {
            return
        }
        let typeParams = types.nominalTypeParameterSymbols(for: kMutableProperty0Symbol)
        guard typeParams.count == 1 else { return }
        let valueType = types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        addSyntheticDirectSupertypes([function0Symbol], to: kMutableProperty0Symbol, symbols: symbols, types: types)
        let function0Args: [TypeArg] = [.out(valueType)]
        symbols.setSupertypeTypeArgs(function0Args, for: kMutableProperty0Symbol, supertype: function0Symbol)
        types.setNominalSupertypeTypeArgs(function0Args, for: kMutableProperty0Symbol, supertype: function0Symbol)
    }

    func patchKMutableProperty1FunctionSupertype(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let functionPkg = [interner.intern("kotlin"), interner.intern("Function")]
        guard let kMutableProperty1Symbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KMutableProperty1")]),
              let function1Symbol = symbols.lookup(fqName: functionPkg + [interner.intern("Function1")])
        else {
            return
        }
        let typeParams = types.nominalTypeParameterSymbols(for: kMutableProperty1Symbol)
        guard typeParams.count == 2 else { return }
        let receiverType = types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        addSyntheticDirectSupertypes([function1Symbol], to: kMutableProperty1Symbol, symbols: symbols, types: types)
        let function1Args: [TypeArg] = [.out(valueType), .in(receiverType)]
        symbols.setSupertypeTypeArgs(function1Args, for: kMutableProperty1Symbol, supertype: function1Symbol)
        types.setNominalSupertypeTypeArgs(function1Args, for: kMutableProperty1Symbol, supertype: function1Symbol)
    }

    private func addSyntheticDirectSupertypes(
        _ supertypes: [SymbolID],
        to symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        var symbolSupertypes = symbols.directSupertypes(for: symbol)
        for supertype in supertypes where !symbolSupertypes.contains(supertype) {
            symbolSupertypes.append(supertype)
        }
        symbols.setDirectSupertypes(symbolSupertypes, for: symbol)

        var typeSupertypes = types.directNominalSupertypes(for: symbol)
        for supertype in supertypes where !typeSupertypes.contains(supertype) {
            typeSupertypes.append(supertype)
        }
        types.setNominalDirectSupertypes(typeSupertypes, for: symbol)
    }

    // STDLIB-REFLECT-066: Register KType interface stub and typeOf<T>() function stub.
    private func registerSyntheticKTypeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString],
        kotlinPkg: [InternedString],
        kAnnotatedElementSymbol: SymbolID
    ) {
        let anyType = types.anyType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Register kotlin.reflect.KType interface stub
        let kTypeSymbol = ensureInterfaceSymbol(
            named: "KType", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kTypeType = types.make(.classType(ClassType(
            classSymbol: kTypeSymbol, args: [], nullability: .nonNull
        )))
        addSyntheticDirectSupertypes(
            [kAnnotatedElementSymbol], to: kTypeSymbol,
            symbols: symbols, types: types
        )

        if let kTypeInfo = symbols.symbol(kTypeSymbol) {
            // KType.isMarkedNullable: Boolean
            let isMarkedNullableName = interner.intern("isMarkedNullable")
            let isMarkedNullableFQ = kTypeInfo.fqName + [isMarkedNullableName]
            if symbols.lookup(fqName: isMarkedNullableFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: isMarkedNullableName, fqName: isMarkedNullableFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(boolType, for: propSym)
                symbols.setExternalLinkName("kk_ktype_isMarkedNullable", for: propSym)
            }

            // KType.classifier: KClassifier? (returns Any? opaque handle)
            let classifierName = interner.intern("classifier")
            let classifierFQ = kTypeInfo.fqName + [classifierName]
            if symbols.lookup(fqName: classifierFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: classifierName, fqName: classifierFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(types.makeNullable(anyType), for: propSym)
                symbols.setExternalLinkName("kk_ktype_classifier", for: propSym)
            }

            // KType.arguments: List<KTypeProjection> (returns Any opaque)
            let argumentsName = interner.intern("arguments")
            let argumentsFQ = kTypeInfo.fqName + [argumentsName]
            if symbols.lookup(fqName: argumentsFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: argumentsName, fqName: argumentsFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(anyType, for: propSym)
                symbols.setExternalLinkName("kk_ktype_arguments", for: propSym)
            }
        }

        // Register kotlin.reflect.KTypeProjection class stub
        let kTypeProjectionSymbol = ensureClassSymbol(
            named: "KTypeProjection", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )

        registerSyntheticKVarianceStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )
        registerSyntheticKTypeProjectionSurface(
            kTypeProjectionSymbol: kTypeProjectionSymbol,
            kTypeSymbol: kTypeSymbol,
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )

        // Register kotlin.reflect.KClassifier interface stub (supertype of KClass)
        let kClassifierSymbol = ensureInterfaceSymbol(
            named: "KClassifier", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kClassifierInterfaceSymbol = kClassifierSymbol
        registerSyntheticKTypeParameterStub(
            kClassifierSymbol: kClassifierSymbol,
            kTypeSymbol: kTypeSymbol,
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )

        // Register typeOf<T>(): KType — inline reified function accessible without import.
        // Available in the kotlin package as a top-level function.
        let typeOfName = interner.intern("typeOf")
        let typeOfFQName = kotlinPkg + [typeOfName]
        if symbols.lookupAll(fqName: typeOfFQName).isEmpty {
            let tParamName = interner.intern("T")
            let tParamFQName = typeOfFQName + [tParamName]
            let tParamSymbol = symbols.define(
                kind: .typeParameter, name: tParamName, fqName: tParamFQName,
                declSite: nil, visibility: .private, flags: [.reifiedTypeParameter]
            )

            let funcSymbol = symbols.define(
                kind: .function, name: typeOfName, fqName: typeOfFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction]
            )
            if let pkg = symbols.lookup(fqName: kotlinPkg), pkg != .invalid {
                symbols.setParentSymbol(pkg, for: funcSymbol)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [],
                    returnType: kTypeType,
                    isSuspend: false,
                    typeParameterSymbols: [tParamSymbol],
                    reifiedTypeParameterIndices: [0],
                    typeParameterUpperBoundsList: [[]],
                    classTypeParameterCount: 0
                ),
                for: funcSymbol
            )
        }

        // Also register typeOf in kotlin.reflect package for `import kotlin.reflect.typeOf` usage.
        let typeOfReflectFQName = kotlinReflectPkg + [typeOfName]
        if symbols.lookupAll(fqName: typeOfReflectFQName).isEmpty {
            let tParamName2 = interner.intern("T")
            let tParamFQName2 = typeOfReflectFQName + [tParamName2]
            let tParamSymbol2 = symbols.define(
                kind: .typeParameter, name: tParamName2, fqName: tParamFQName2,
                declSite: nil, visibility: .private, flags: [.reifiedTypeParameter]
            )

            let funcSymbol2 = symbols.define(
                kind: .function, name: typeOfName, fqName: typeOfReflectFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction]
            )
            if let pkg = symbols.lookup(fqName: kotlinReflectPkg), pkg != .invalid {
                symbols.setParentSymbol(pkg, for: funcSymbol2)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [],
                    returnType: kTypeType,
                    isSuspend: false,
                    typeParameterSymbols: [tParamSymbol2],
                    reifiedTypeParameterIndices: [0],
                    typeParameterUpperBoundsList: [[]],
                    classTypeParameterCount: 0
                ),
                for: funcSymbol2
            )
        }
    }

    // STDLIB-REFLECT-072: Register KTypeParameter interface and scalar properties.
    private func registerSyntheticKTypeParameterStub(
        kClassifierSymbol: SymbolID,
        kTypeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        let kTypeParameterSymbol = ensureInterfaceSymbol(
            named: "KTypeParameter", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        addKTypeParameterDirectSupertypes(
            [kClassifierSymbol],
            to: kTypeParameterSymbol,
            symbols: symbols,
            types: types
        )

        guard let kTypeParameterInfo = symbols.symbol(kTypeParameterSymbol) else { return }
        let stringType = types.make(.primitive(.string, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let kVarianceType: TypeID = if let kVarianceSymbol = symbols.lookup(
            fqName: kotlinReflectPkg + [interner.intern("KVariance")]
        ) {
            types.make(.classType(ClassType(
                classSymbol: kVarianceSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let kTypeType = types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))

        registerSyntheticKTypeParameterProperty(
            named: "name",
            ownerSymbol: kTypeParameterSymbol,
            ownerFQName: kTypeParameterInfo.fqName,
            propertyType: stringType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKTypeParameterProperty(
            named: "isReified",
            ownerSymbol: kTypeParameterSymbol,
            ownerFQName: kTypeParameterInfo.fqName,
            propertyType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKTypeParameterProperty(
            named: "variance",
            ownerSymbol: kTypeParameterSymbol,
            ownerFQName: kTypeParameterInfo.fqName,
            propertyType: kVarianceType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKTypeParameterProperty(
            named: "upperBounds",
            ownerSymbol: kTypeParameterSymbol,
            ownerFQName: kTypeParameterInfo.fqName,
            propertyType: kTypeType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticKTypeParameterProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else { return }
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

    // STDLIB-REFLECT-TYPE-013: Register KParameter interface and scalar properties.
    private func registerSyntheticKParameterStub(
        kAnnotatedElementSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        let kParameterSymbol = ensureInterfaceSymbol(
            named: "KParameter", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        addSyntheticDirectSupertypes(
            [kAnnotatedElementSymbol],
            to: kParameterSymbol,
            symbols: symbols,
            types: types
        )

        guard let kParameterInfo = symbols.symbol(kParameterSymbol) else { return }
        let kTypeSymbol = ensureInterfaceSymbol(
            named: "KType", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kTypeType = types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))

        let propertySpecs: [(name: String, type: TypeID, externalLinkName: String)] = [
            ("index", types.intType, "kk_kparameter_get_index"),
            ("name", types.make(.primitive(.string, .nullable)), "kk_kparameter_get_name"),
            ("type", kTypeType, "kk_kparameter_get_type"),
            ("isOptional", types.booleanType, "kk_kparameter_is_optional"),
            ("kind", types.intType, "kk_kparameter_get_kind"),
        ]
        for spec in propertySpecs {
            registerSyntheticKParameterProperty(
                named: spec.name,
                ownerSymbol: kParameterSymbol,
                ownerFQName: kParameterInfo.fqName,
                propertyType: spec.type,
                externalLinkName: spec.externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticKParameterProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else { return }
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func addKTypeParameterDirectSupertypes(
        _ supertypes: [SymbolID],
        to symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        var symbolSupertypes = symbols.directSupertypes(for: symbol)
        for supertype in supertypes where !symbolSupertypes.contains(supertype) {
            symbolSupertypes.append(supertype)
        }
        symbols.setDirectSupertypes(symbolSupertypes, for: symbol)

        var typeSupertypes = types.directNominalSupertypes(for: symbol)
        for supertype in supertypes where !typeSupertypes.contains(supertype) {
            typeSupertypes.append(supertype)
        }
        types.setNominalDirectSupertypes(typeSupertypes, for: symbol)
    }

    // STDLIB-REFLECT-074: Register KTypeProjection data-class properties.
    private func registerSyntheticKTypeProjectionSurface(
        kTypeProjectionSymbol: SymbolID,
        kTypeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        guard let kTypeProjectionInfo = symbols.symbol(kTypeProjectionSymbol) else { return }
        let nullableKType = types.makeNullable(types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        ))))
        let nullableKVariance: TypeID = if let kVarianceSymbol = symbols.lookup(
            fqName: kotlinReflectPkg + [interner.intern("KVariance")]
        ) {
            types.makeNullable(types.make(.classType(ClassType(
                classSymbol: kVarianceSymbol,
                args: [],
                nullability: .nonNull
            ))))
        } else {
            types.nullableAnyType
        }

        registerSyntheticKTypeProjectionProperty(
            named: "variance",
            ownerSymbol: kTypeProjectionSymbol,
            ownerFQName: kTypeProjectionInfo.fqName,
            propertyType: nullableKVariance,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticKTypeProjectionProperty(
            named: "type",
            ownerSymbol: kTypeProjectionSymbol,
            ownerFQName: kTypeProjectionInfo.fqName,
            propertyType: nullableKType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticKTypeProjectionProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else { return }
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

    // STDLIB-REFLECT-073: Register KVariance enum with declaration/use-site variance entries.
    private func registerSyntheticKVarianceStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        let enumName = interner.intern("KVariance")
        let enumFQName = kotlinReflectPkg + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol = symbols.lookup(fqName: kotlinReflectPkg), pkgSymbol != .invalid {
                symbols.setParentSymbol(pkgSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["INVARIANT", "IN", "OUT"] {
            let entryName = interner.intern(entry)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            }
            symbols.setPropertyType(enumType, for: entrySymbol)
        }
    }

    private func registerAssociatedObjectKeyAnnotation(
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let symbol = ensureAnnotationClassSymbol(
            named: "AssociatedObjectKey", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
        )
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.reflect.ExperimentalAssociatedObjects"
        )
        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )
        var annotations = symbols.annotations(for: symbol)
        for record in [experimentalRecord, retentionRecord, targetRecord] {
            if !annotations.contains(record) {
                annotations.append(record)
            }
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func registerFindAssociatedObjectFunction(
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("findAssociatedObject")
        let functionFQName = kotlinReflectPkg + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else { return }

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )

        let annotationType: TypeID
        if let annotationSymbol = types.annotationInterfaceSymbol {
            annotationType = types.make(.classType(ClassType(
                classSymbol: annotationSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else if let annotationSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Annotation")]) {
            annotationType = types.make(.classType(ClassType(
                classSymbol: annotationSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            annotationType = types.anyType
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let pkg = symbols.lookup(fqName: kotlinReflectPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setExternalLinkName("kk_kclass_find_associated_object", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.makeKClassType(argument: types.anyType),
                parameterTypes: [],
                returnType: types.makeNullable(types.anyType),
                isSuspend: false,
                canThrow: false,
                typeParameterSymbols: [typeParamSymbol],
                reifiedTypeParameterIndices: [0],
                typeParameterUpperBoundsList: [[annotationType]],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.reflect.ExperimentalAssociatedObjects")],
            for: functionSymbol
        )
    }

    private func registerCreateInstanceFunction(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinReflectFullPkg = ensurePackage(
            path: ["kotlin", "reflect", "full"],
            symbols: symbols,
            interner: interner
        )
        let functionName = interner.intern("createInstance")
        let functionFQName = kotlinReflectFullPkg + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else { return }

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )
        let kClassSymbol = ensureInterfaceSymbol(
            named: "KClass",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        let receiverType = types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinReflectFullPkg), packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )

        // Also register under kotlin.reflect for top-level reference resolution
        let kotlinReflectFQName = kotlinReflectPkg + [functionName]
        if symbols.lookupAll(fqName: kotlinReflectFQName).isEmpty {
            let reflectFunctionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: kotlinReflectFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinReflectPkg), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: reflectFunctionSymbol)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: typeParamType,
                    typeParameterSymbols: [typeParamSymbol],
                    typeParameterUpperBoundsList: [[types.anyType]],
                    classTypeParameterCount: 0
                ),
                for: reflectFunctionSymbol
            )
        }
    }

    /// Updates `KAnnotatedElement.annotations` to `List<Annotation>` once collection stubs exist.
    func patchKAnnotatedElementAnnotationsType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName),
              let kAnnotatedElementSymbol = types.kAnnotatedElementInterfaceSymbol,
              let annotationSymbol = types.annotationInterfaceSymbol,
              let kAnnotatedElementInfo = symbols.symbol(kAnnotatedElementSymbol)
        else {
            return
        }

        let annotationType = types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfAnnotation = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(annotationType)],
            nullability: .nonNull
        )))

        let annotationsPropFQ = kAnnotatedElementInfo.fqName + [interner.intern("annotations")]
        if let annotationsPropSymbol = symbols.lookup(fqName: annotationsPropFQ) {
            symbols.setPropertyType(listOfAnnotation, for: annotationsPropSymbol)
        }
    }

    /// Updates `KDeclarationContainer.members` to `Collection<KCallable<*>>` once collection stubs exist.
    func patchKDeclarationContainerMembersType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let collectionFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("Collection"),
        ]
        let kCallableFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("reflect"), interner.intern("KCallable"),
        ]
        guard let collectionSymbol = symbols.lookup(fqName: collectionFQName),
              let kDeclarationContainerSymbol = types.kDeclarationContainerInterfaceSymbol,
              let kCallableSymbol = symbols.lookup(fqName: kCallableFQName),
              let kDeclarationContainerInfo = symbols.symbol(kDeclarationContainerSymbol)
        else {
            return
        }

        let kCallableStarType = types.make(.classType(ClassType(
            classSymbol: kCallableSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let collectionOfKCallable = types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(kCallableStarType)],
            nullability: .nonNull
        )))

        let membersPropFQ = kDeclarationContainerInfo.fqName + [interner.intern("members")]
        if let membersPropSymbol = symbols.lookup(fqName: membersPropFQ) {
            symbols.setPropertyType(collectionOfKCallable, for: membersPropSymbol)
        }
    }

    /// Updates the `parameters` property type of `KFunction` to `List<Any?>` once the
    /// collection stubs have been registered.  Called from `registerSyntheticDelegateStubs`
    /// after `registerSyntheticCollectionStubs` (STDLIB-REFLECT-063).
    func patchKFunctionParametersType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Locate kotlin.collections.List
        let listFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName),
              let kFunctionSymbol = types.kFunctionInterfaceSymbol
        else {
            return
        }
        // Build List<Any?> type for parameters.
        let nullableAny = types.makeNullable(types.anyType)
        let listOfAnyNullable = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(nullableAny)],
            nullability: .nonNull
        )))

        // Update KFunction.parameters property type.
        guard let kFunctionInfo = symbols.symbol(kFunctionSymbol) else { return }
        let paramsPropFQ = kFunctionInfo.fqName + [interner.intern("parameters")]
        if let paramsPropSymbol = symbols.lookup(fqName: paramsPropFQ) {
            symbols.setPropertyType(listOfAnyNullable, for: paramsPropSymbol)
        }
    }

    func patchKTypeArgumentsType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        guard let listSymbol = symbols.lookup(fqName: listFQName),
              let kTypeSymbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KType")]),
              let kTypeProjectionSymbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KTypeProjection")]),
              let kTypeInfo = symbols.symbol(kTypeSymbol)
        else {
            return
        }
        let projectionType = types.make(.classType(ClassType(
            classSymbol: kTypeProjectionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfProjections = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(projectionType)],
            nullability: .nonNull
        )))
        let argumentsFQName = kTypeInfo.fqName + [interner.intern("arguments")]
        if let argumentsSymbol = symbols.lookup(fqName: argumentsFQName) {
            symbols.setPropertyType(listOfProjections, for: argumentsSymbol)
        }
    }

    func patchKTypeParameterUpperBoundsType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        guard let listSymbol = symbols.lookup(fqName: listFQName),
              let kTypeSymbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KType")]),
              let kTypeParameterSymbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KTypeParameter")]),
              let kTypeParameterInfo = symbols.symbol(kTypeParameterSymbol)
        else {
            return
        }
        let kTypeType = types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfKType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(kTypeType)],
            nullability: .nonNull
        )))
        let upperBoundsFQName = kTypeParameterInfo.fqName + [interner.intern("upperBounds")]
        if let upperBoundsSymbol = symbols.lookup(fqName: upperBoundsFQName) {
            symbols.setPropertyType(listOfKType, for: upperBoundsSymbol)
        }
    }
}

extension DataFlowSemaPhase {
    func registerSyntheticKPropertyIsInitializedStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let kotlinReflectPkg = ensurePackage(path: ["kotlin", "reflect"], symbols: symbols, interner: interner)
        let kProperty0Symbol = ensureInterfaceSymbol(
            named: "KProperty0",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )
        let propertyName = interner.intern("isInitialized")
        let propertyFQName = kotlinPkg + [propertyName]
        let receiverType = types.make(.classType(ClassType(
            classSymbol: kProperty0Symbol,
            args: [.star],
            nullability: .nonNull
        )))
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setPropertyType(types.booleanType, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(types.booleanType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
    }
}
