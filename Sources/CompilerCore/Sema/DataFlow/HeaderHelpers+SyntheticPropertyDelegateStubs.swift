
extension DataFlowSemaPhase {
    func registerSyntheticPropertyInterfaceStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString],
        kotlinPropertiesPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex
    ) {
        let anyType = types.anyType

        // Register kotlin.reflect.KProperty<out V> interface stub so that
        // `import kotlin.reflect.KProperty` and `KProperty<*>` type references resolve.
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"], symbols: symbols, interner: interner
        )
        registerAssociatedObjectKeyAnnotation(
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerFindAssociatedObjectFunction(
            kotlinReflectPkg: kotlinReflectPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let kPropertySymbol = ensureInterfaceSymbol(
            named: "KProperty", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )

        // STDLIB-REFLECT-066: Register kotlin.reflect.KType and typeOf<T>() stubs
        registerSyntheticKTypeStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinReflectPkg: kotlinReflectPkg, kotlinPkg: kotlinPkg
        )
        registerSyntheticKParameterStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )

        // Register `name` property on KProperty (inherited from KCallable).
        let stringType = types.stringType
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

        let kCallableSymbol = ensureInterfaceSymbol(
            named: "KCallable", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        // KCallable is source-backed when the bundled stdlib is present. Keep
        // its generic shell and properties here so early synthetic declarations
        // can refer to the same symbols before bundled headers are collected.
        let returnTypeParameterName = interner.intern("R")
        let returnTypeParameterFQ = (symbols.symbol(kCallableSymbol)?.fqName
            ?? kotlinReflectPkg + [interner.intern("KCallable")]) + [returnTypeParameterName]
        let returnTypeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: returnTypeParameterFQ) {
            returnTypeParameterSymbol = existing
        } else {
            returnTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: returnTypeParameterName,
                fqName: returnTypeParameterFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kCallableSymbol, for: returnTypeParameterSymbol)
        }
        types.setNominalTypeParameterSymbols([returnTypeParameterSymbol], for: kCallableSymbol)
        types.setNominalTypeParameterVariances([.out], for: kCallableSymbol)
        addSyntheticDirectSupertypes(
            [kCallableSymbol], to: kPropertySymbol,
            symbols: symbols, types: types
        )
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

            let returnTypeName = interner.intern("returnType")
            let returnTypeFQ = kCallableInfo.fqName + [returnTypeName]
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
                symbols.setParentSymbol(kCallableSymbol, for: returnTypeSymbol)
                symbols.setPropertyType(kTypeType, for: returnTypeSymbol)
            }
        }
        let kMutablePropertySymbol = ensureInterfaceSymbol(
            named: "KMutableProperty", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        registerSyntheticKMutablePropertyStub(
            kMutablePropertySymbol: kMutablePropertySymbol,
            kPropertySymbol: kPropertySymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // KSP-682: KProperty0/1/2 and KMutableProperty0/1/2 are bundled Kotlin
        // source (Stdlib/kotlin/reflect/KProperties.kt) when the stdlib is
        // included; register the synthetic fallback shells only when the bundled
        // source is absent (e.g. compilations without the stdlib).
        if !bundledIndex.contains(
            ownerFQName: kotlinReflectPkg + [interner.intern("KProperty0")],
            name: interner.intern("get"),
            arity: 0
        ) {
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
            registerSyntheticKProperty0Stub(
                kPropertySymbol: kPropertySymbol,
                kotlinReflectPkg: kotlinReflectPkg,
                symbols: symbols,
                types: types,
                interner: interner
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
        }

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
        let kClassSymbol = ensureInterfaceSymbol(
            named: "KClass", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        types.kClassInterfaceSymbol = kClassSymbol
        addSyntheticDirectSupertypes(
            [kClassifierSymbol], to: kClassSymbol,
            symbols: symbols, types: types
        )

        if let kFunctionInfo = symbols.symbol(kFunctionSymbol) {
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

            // Patched to List<Any?> later by patchKFunctionParametersType.
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

        let setterPkg = kMutablePropertyInfo.fqName
        let setterSymbol = ensureInterfaceSymbol(named: "Setter", in: setterPkg, symbols: symbols, interner: interner)
        symbols.setParentSymbol(kMutablePropertySymbol, for: setterSymbol)

        guard let setterInfo = symbols.symbol(setterSymbol) else { return }
        let setterValueName = interner.intern("V")
        let setterValueFQ = setterInfo.fqName + [setterValueName]
        let setterValueParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: setterValueFQ) {
            setterValueParamSymbol = existing
        } else {
            setterValueParamSymbol = symbols.define(
                kind: .typeParameter,
                name: setterValueName,
                fqName: setterValueFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(setterSymbol, for: setterValueParamSymbol)
        }
        types.setNominalTypeParameterSymbols([setterValueParamSymbol], for: setterSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: setterSymbol)

        let setterValueType = types.make(.typeParam(TypeParamType(
            symbol: setterValueParamSymbol,
            nullability: .nonNull
        )))

        let function1FQName = [interner.intern("kotlin"), interner.intern("Function"), interner.intern("Function1")]
        if let function1Symbol = symbols.lookup(fqName: function1FQName) {
            addSyntheticDirectSupertypes([function1Symbol], to: setterSymbol, symbols: symbols, types: types)
            // Function1<in V, out Unit>: args order is [out R, in P1] per codebase convention.
            let function1Args: [TypeArg] = [.out(types.unitType), .in(setterValueType)]
            symbols.setSupertypeTypeArgs(function1Args, for: setterSymbol, supertype: function1Symbol)
            types.setNominalSupertypeTypeArgs(function1Args, for: setterSymbol, supertype: function1Symbol)
        }

        let setterPropName = interner.intern("setter")
        let setterPropFQ = kMutablePropertyInfo.fqName + [setterPropName]
        if symbols.lookup(fqName: setterPropFQ) == nil {
            let setterPropSymbol = symbols.define(
                kind: .property,
                name: setterPropName,
                fqName: setterPropFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(kMutablePropertySymbol, for: setterPropSymbol)
            let setterType = types.make(.classType(ClassType(
                classSymbol: setterSymbol,
                args: [.invariant(valueType)],
                nullability: .nonNull
            )))
            symbols.setPropertyType(setterType, for: setterPropSymbol)
        }
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
        if let kProperty0Symbol = symbols.lookup(fqName: reflectPkg + [interner.intern("KProperty0")]),
           let function0Symbol = symbols.lookup(fqName: functionPkg + [interner.intern("Function0")])
        {
            let typeParams = types.nominalTypeParameterSymbols(for: kProperty0Symbol)
            if typeParams.count == 1 {
                let valueType = types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
                addSyntheticDirectSupertypes([function0Symbol], to: kProperty0Symbol, symbols: symbols, types: types)
                let function0Args: [TypeArg] = [.out(valueType)]
                symbols.setSupertypeTypeArgs(function0Args, for: kProperty0Symbol, supertype: function0Symbol)
                types.setNominalSupertypeTypeArgs(function0Args, for: kProperty0Symbol, supertype: function0Symbol)
            }
        }
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
        kotlinPkg: [InternedString]
    ) {
        let anyType = types.anyType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let kTypeSymbol = ensureInterfaceSymbol(
            named: "KType", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let kTypeType = types.make(.classType(ClassType(
            classSymbol: kTypeSymbol, args: [], nullability: .nonNull
        )))

        if let kTypeInfo = symbols.symbol(kTypeSymbol) {
            let isMarkedNullableName = interner.intern("isMarkedNullable")
            let isMarkedNullableFQ = kTypeInfo.fqName + [isMarkedNullableName]
            if symbols.lookup(fqName: isMarkedNullableFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: isMarkedNullableName, fqName: isMarkedNullableFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(boolType, for: propSym)
                symbols.setExternalLinkName("__kk_ktype_isMarkedNullable", for: propSym)
            }

            let classifierName = interner.intern("classifier")
            let classifierFQ = kTypeInfo.fqName + [classifierName]
            if symbols.lookup(fqName: classifierFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: classifierName, fqName: classifierFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(types.makeNullable(anyType), for: propSym)
                symbols.setExternalLinkName("__kk_ktype_classifier", for: propSym)
            }

            let argumentsName = interner.intern("arguments")
            let argumentsFQ = kTypeInfo.fqName + [argumentsName]
            if symbols.lookup(fqName: argumentsFQ) == nil {
                let propSym = symbols.define(
                    kind: .property, name: argumentsName, fqName: argumentsFQ,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(kTypeSymbol, for: propSym)
                symbols.setPropertyType(anyType, for: propSym)
                symbols.setExternalLinkName("__kk_ktype_arguments", for: propSym)
            }
        }

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

        let kClassifierSymbol = ensureInterfaceSymbol(
            named: "KClassifier", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        registerSyntheticKTypeParameterStub(
            kClassifierSymbol: kClassifierSymbol,
            kTypeSymbol: kTypeSymbol,
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinReflectPkg: kotlinReflectPkg
        )

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
        let stringType = types.stringType
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
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinReflectPkg: [InternedString]
    ) {
        let kParameterSymbol = ensureInterfaceSymbol(
            named: "KParameter", in: kotlinReflectPkg, symbols: symbols, interner: interner
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
            ("index", types.intType, "__kk_kparameter_get_index"),
            ("name", types.makeNullable(types.stringType), "__kk_kparameter_get_name"),
            ("type", kTypeType, "__kk_kparameter_get_type"),
            ("isOptional", types.booleanType, "__kk_kparameter_is_optional"),
            ("kind", types.intType, "__kk_kparameter_get_kind"),
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
        // The bundled declaration owns its real enum entry symbols. Keep the
        // synthetic entries only for --no-stdlib compatibility.
        if !symbols.isSourceBackedSymbol(enumSymbol) {
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
    }

    private func registerAssociatedObjectKeyAnnotation(
        kotlinReflectPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let symbol = ensureAnnotationClassSymbol(
            named: "AssociatedObjectKey", in: kotlinReflectPkg, symbols: symbols, interner: interner
        )
        let annotationType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        let constructorName = interner.intern("<init>")
        let annotationFQName = symbols.symbol(symbol)?.fqName
            ?? (kotlinReflectPkg + [interner.intern("AssociatedObjectKey")])
        let constructorFQName = annotationFQName + [constructorName]
        if symbols.lookupAll(fqName: constructorFQName).isEmpty {
            let constructor = symbols.define(
                kind: .constructor,
                name: constructorName,
                fqName: constructorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: constructor)
            symbols.setFunctionSignature(FunctionSignature(
                parameterTypes: [],
                returnType: annotationType
            ), for: constructor)
        }
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
            // swiftlint:disable:next for_where
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
        symbols.setExternalLinkName("__kk_kclass_find_associated_object", for: functionSymbol)
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

    /// Patches KFunction.parameters to `List<Any?>` (STDLIB-REFLECT-063).
    func patchKFunctionParametersType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName),
              let kFunctionSymbol = types.kFunctionInterfaceSymbol
        else {
            return
        }
        let nullableAny = types.makeNullable(types.anyType)
        let listOfAnyNullable = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(nullableAny)],
            nullability: .nonNull
        )))

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
