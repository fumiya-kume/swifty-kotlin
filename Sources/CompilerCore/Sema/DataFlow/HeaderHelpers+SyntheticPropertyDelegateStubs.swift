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

        // Register kotlin.properties.Lazy<T> interface stub.
        let lazyInterfaceSymbol = ensureInterfaceSymbol(
            named: "Lazy", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let lazyInterfaceType = types.make(.classType(ClassType(
            classSymbol: lazyInterfaceSymbol, args: [], nullability: .nonNull
        )))

        // Register kotlin.properties.ReadWriteProperty<T, V> interface stub.
        let rwPropertySymbol = ensureInterfaceSymbol(
            named: "ReadWriteProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let rwPropertyType = types.make(.classType(ClassType(
            classSymbol: rwPropertySymbol, args: [], nullability: .nonNull
        )))

        // Register kotlin.properties.ReadOnlyProperty<in T, out V> interface stub.
        _ = ensureInterfaceSymbol(
            named: "ReadOnlyProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )

        // Register kotlin.reflect.KProperty<out V> interface stub so that
        // `import kotlin.reflect.KProperty` and `KProperty<*>` type references resolve.
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"], symbols: symbols, interner: interner
        )
        let kPropertySymbol = ensureInterfaceSymbol(
            named: "KProperty", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )

        // STDLIB-REFLECT-066: Register kotlin.reflect.KType and typeOf<T>() stubs
        registerSyntheticKTypeStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinReflectPkg: kotlinReflectPkg, kotlinPkg: kotlinPkg
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
        for reflectTypeName in [
            "KProperty0", "KProperty1",
            "KMutableProperty", "KMutableProperty0", "KMutableProperty1",
        ] {
            _ = ensureInterfaceSymbol(
                named: reflectTypeName, in: kotlinReflectPkg, symbols: symbols, interner: interner
            )
        }

        // Register kotlin.reflect.KFunction<out R> interface stub (STDLIB-REFLECT-063).
        // Store in TypeSystem so subtyping checks can recognise KFunction receivers.
        let kFunctionSymbol = ensureInterfaceSymbol(
            named: "KFunction", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kFunctionInterfaceSymbol = kFunctionSymbol

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
                FunctionSignature(parameterTypes: [initializerType], returnType: lazyInterfaceType),
                for: lazySymbol
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
                FunctionSignature(parameterTypes: [anyType, initializerType], returnType: lazyInterfaceType),
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

    // STDLIB-REFLECT-066: Register KType interface stub and typeOf<T>() function stub.
    private func registerSyntheticKTypeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString],
        kotlinPkg: [InternedString]
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
        _ = ensureClassSymbol(
            named: "KTypeProjection", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )

        // Register kotlin.reflect.KClassifier interface stub (supertype of KClass)
        _ = ensureInterfaceSymbol(
            named: "KClassifier", in: kotlinReflectPkg, symbols: symbols, interner: interner
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
}
