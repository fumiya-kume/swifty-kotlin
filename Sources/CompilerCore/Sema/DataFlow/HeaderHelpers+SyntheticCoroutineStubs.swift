import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticCoroutineStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Build the synthetic package tree explicitly so the coroutine stubs
        // stay stable across incremental rebuilds.
        let kotlinCoroutinesPkg = ensureSyntheticPackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesIntrinsicsPkg = ensureSyntheticPackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        let cancellationPkg = ensureSyntheticPackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )
        let kotlinxPkg = ensureSyntheticPackage(
            [interner.intern("kotlinx")],
            symbols: symbols,
            interner: interner
        )
        let coroutinesPkg = ensureSyntheticPackage(
            kotlinxPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesCancellationPkg = ensureSyntheticPackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )
        let channelsPkg = ensureSyntheticPackage(
            coroutinesPkg + [interner.intern("channels")],
            symbols: symbols,
            interner: interner
        )
        let flowPkg = ensureSyntheticPackage(
            coroutinesPkg + [interner.intern("flow")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutineContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutineContextType = types.make(.classType(ClassType(
            classSymbol: kotlinCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(kotlinCoroutineContextType, for: kotlinCoroutineContextSymbol)

        let kotlinResultSymbol = ensureClassSymbol(
            named: "Result",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinResultTypeParamName = interner.intern("T")
        let kotlinResultFQName = kotlinPkg + [interner.intern("Result")]
        let kotlinResultTypeParamFQName = kotlinResultFQName + [kotlinResultTypeParamName]
        let kotlinResultTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: kotlinResultTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: kotlinResultTypeParamName,
                fqName: kotlinResultTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(kotlinResultSymbol, for: kotlinResultTypeParamSymbol)
        let kotlinResultTType = types.make(.typeParam(TypeParamType(
            symbol: kotlinResultTypeParamSymbol,
            nullability: .nonNull
        )))
        let kotlinResultType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.out(kotlinResultTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([kotlinResultTypeParamSymbol], for: kotlinResultSymbol)
        types.setNominalTypeParameterVariances([.out], for: kotlinResultSymbol)
        symbols.setPropertyType(kotlinResultType, for: kotlinResultSymbol)


        let continuationSymbol = ensureInterfaceSymbol(
            named: "Continuation",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
            symbols.setParentSymbol(packageSymbol, for: continuationSymbol)
        }
        let continuationInterceptorSymbol = ensureInterfaceSymbol(
            named: "ContinuationInterceptor",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let continuationTypeParamName = interner.intern("T")
        let continuationTypeParamFQName = kotlinCoroutinesPkg + [interner.intern("Continuation"), continuationTypeParamName]
        let continuationTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: continuationTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: continuationTypeParamName,
                fqName: continuationTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(continuationSymbol, for: continuationTypeParamSymbol)
        let continuationTType = types.make(.typeParam(TypeParamType(
            symbol: continuationTypeParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([continuationTypeParamSymbol], for: continuationSymbol)
        types.setNominalTypeParameterVariances([], for: continuationSymbol)
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        let continuationTypeParameterSymbol = continuationTypeParamSymbol
        let continuationInterceptorType = types.make(.classType(ClassType(
            classSymbol: continuationInterceptorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(continuationInterceptorType, for: continuationInterceptorSymbol)

        let suspendCoroutineTypeParamName = interner.intern("T")
        let suspendCoroutineTypeParamFQName = kotlinCoroutinesPkg + [interner.intern("suspendCoroutine"), suspendCoroutineTypeParamName]
        let suspendCoroutineTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: suspendCoroutineTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: suspendCoroutineTypeParamName,
                fqName: suspendCoroutineTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let suspendCoroutineTType = types.make(.typeParam(TypeParamType(
            symbol: suspendCoroutineTypeParamSymbol,
            nullability: .nonNull
        )))

        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let jobSymbol = ensureClassSymbol(
            named: "Job",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let deferredSymbol = ensureClassSymbol(
            named: "Deferred",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let dispatchersSymbol = ensureObjectSymbol(
            named: "Dispatchers",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let flowInterfaceSymbol = ensureInterfaceSymbol(
            named: "Flow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let sharedFlowSymbol = ensureInterfaceSymbol(
            named: "SharedFlow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let stateFlowSymbol = ensureInterfaceSymbol(
            named: "StateFlow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let mutableSharedFlowSymbol = ensureClassSymbol(
            named: "MutableSharedFlow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let mutableStateFlowSymbol = ensureClassSymbol(
            named: "MutableStateFlow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let dispatcherSymbol = ensureClassSymbol(
            named: "CoroutineDispatcher",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let channelSymbol = ensureClassSymbol(
            named: "Channel",
            in: channelsPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationName = interner.intern("CancellationException")
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: kotlinCoroutinesCancellationPkg,
            symbols: symbols,
            interner: interner
        )
        let rootCancellationSymbol: SymbolID = if let existing = symbols.lookup(fqName: [interner.intern("CancellationException")]) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("CancellationException"),
                fqName: [interner.intern("CancellationException")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let jobType = types.make(.classType(ClassType(
            classSymbol: jobSymbol,
            args: [],
            nullability: .nonNull
        )))
        let deferredType = types.make(.classType(ClassType(
            classSymbol: deferredSymbol,
            args: [],
            nullability: .nonNull
        )))
        let dispatchersType = types.make(.classType(ClassType(
            classSymbol: dispatchersSymbol,
            args: [],
            nullability: .nonNull
        )))
        let flowRawType = types.make(.classType(ClassType(
            classSymbol: flowInterfaceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let sharedFlowRawType = types.make(.classType(ClassType(
            classSymbol: sharedFlowSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stateFlowRawType = types.make(.classType(ClassType(
            classSymbol: stateFlowSymbol,
            args: [],
            nullability: .nonNull
        )))
        let mutableSharedFlowType = types.make(.classType(ClassType(
            classSymbol: mutableSharedFlowSymbol,
            args: [],
            nullability: .nonNull
        )))
        let mutableStateFlowType = types.make(.classType(ClassType(
            classSymbol: mutableStateFlowSymbol,
            args: [],
            nullability: .nonNull
        )))
        let dispatcherType = types.make(.classType(ClassType(
            classSymbol: dispatcherSymbol,
            args: [],
            nullability: .nonNull
        )))
        let channelType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cancellationType = types.make(.classType(ClassType(
            classSymbol: cancellationSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "suspendCoroutine",
            packageFQName: kotlinCoroutinesPkg,
            parameters: [(
                name: "block",
                type: types.make(.functionType(FunctionType(
                        params: [types.make(.classType(ClassType(
                            classSymbol: continuationSymbol,
                            args: [.invariant(suspendCoroutineTType)],
                            nullability: .nonNull
                        )))],
                    returnType: types.unitType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            )],
            returnType: suspendCoroutineTType,
            externalLinkName: "kk_suspend_coroutine",
            isSuspend: true,
            flags: [.synthetic, .inlineFunction],
            explicitTypeParameterSymbols: [suspendCoroutineTypeParamSymbol],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticObjectProperty(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "context",
            propertyType: kotlinCoroutineContextType,
            externalLinkName: "kk_coroutine_continuation_context",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "resume",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: continuationType,
            externalLinkName: "kk_coroutine_continuation_resume",
            returnType: types.unitType,
            parameters: [(
                name: "value",
                type: continuationTType
            )],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "resumeWithException",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: continuationType,
            externalLinkName: "kk_coroutine_continuation_resume_with_exception",
            returnType: types.unitType,
            parameters: [(
                name: "exception",
                type: exceptionType
            )],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        let resultOfContinuationTType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.out(continuationTType)],
            nullability: .nonNull
        )))
        registerSyntheticCoroutineMember(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "resumeWith",
            externalLinkName: "kk_coroutine_continuation_resume_with",
            returnType: types.unitType,
            parameters: [(
                name: "result",
                type: resultOfContinuationTType
            )],
            typeParameterSymbols: [continuationTypeParameterSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        let continuationOfUnitType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.in(types.unitType)],
            nullability: .nonNull
        )))
        let rootCancellationType = types.make(.classType(ClassType(
            classSymbol: rootCancellationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineSuspendedType = types.nullableAnyType

        symbols.setPropertyType(jobType, for: jobSymbol)
        symbols.setPropertyType(deferredType, for: deferredSymbol)
        symbols.setPropertyType(dispatchersType, for: dispatchersSymbol)
        symbols.setPropertyType(flowRawType, for: flowInterfaceSymbol)
        symbols.setPropertyType(sharedFlowRawType, for: sharedFlowSymbol)
        symbols.setPropertyType(stateFlowRawType, for: stateFlowSymbol)
        symbols.setPropertyType(mutableSharedFlowType, for: mutableSharedFlowSymbol)
        symbols.setPropertyType(mutableStateFlowType, for: mutableStateFlowSymbol)
        symbols.setPropertyType(dispatcherType, for: dispatcherSymbol)
        symbols.setPropertyType(channelType, for: channelSymbol)
        symbols.setPropertyType(cancellationType, for: cancellationSymbol)
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        symbols.setPropertyType(continuationInterceptorType, for: continuationInterceptorSymbol)
        symbols.setPropertyType(rootCancellationType, for: rootCancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: rootCancellationSymbol)
        symbols.setDirectSupertypes([continuationInterceptorSymbol], for: dispatcherSymbol)
        types.setNominalTypeParameterSymbols([continuationTypeParameterSymbol], for: continuationSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: continuationSymbol)
        symbols.setDirectSupertypes([flowInterfaceSymbol], for: sharedFlowSymbol)
        symbols.setDirectSupertypes([sharedFlowSymbol], for: stateFlowSymbol)
        symbols.setDirectSupertypes([sharedFlowSymbol], for: mutableSharedFlowSymbol)
        symbols.setDirectSupertypes([stateFlowSymbol, mutableSharedFlowSymbol], for: mutableStateFlowSymbol)

        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "onErrorReturn",
            externalLinkName: "",
            returnType: flowRawType,
            parameters: [(name: "fallback", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "onErrorResume",
            externalLinkName: "",
            returnType: flowRawType,
            parameters: [(name: "fallback", type: flowRawType)],
            symbols: symbols,
            interner: interner
        )

        let suspendIntrinsicName = interner.intern("suspendCoroutineUninterceptedOrReturn")
        let suspendIntrinsicFQName = kotlinCoroutinesIntrinsicsPkg + [suspendIntrinsicName]
        if symbols.lookup(fqName: suspendIntrinsicFQName) == nil {
            let suspendIntrinsicSymbol = symbols.define(
                kind: .function,
                name: suspendIntrinsicName,
                fqName: suspendIntrinsicFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction, .suspendFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesIntrinsicsPkg) {
                symbols.setParentSymbol(packageSymbol, for: suspendIntrinsicSymbol)
            }

            let functionTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: suspendIntrinsicFQName + [interner.intern("$synthetic"), interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let functionTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: functionTypeParameterSymbol,
                nullability: .nonNull
            )))
            let continuationType = types.make(.classType(ClassType(
                classSymbol: continuationSymbol,
                args: [.invariant(functionTypeParameterType)],
                nullability: .nonNull
            )))

            let blockParameterSymbol = symbols.define(
                kind: .valueParameter,
                name: interner.intern("block"),
                fqName: suspendIntrinsicFQName + [interner.intern("block")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(suspendIntrinsicSymbol, for: blockParameterSymbol)

            let blockType = types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [blockType],
                    returnType: functionTypeParameterType,
                    isSuspend: true,
                    valueParameterSymbols: [blockParameterSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [functionTypeParameterSymbol]
                ),
                for: suspendIntrinsicSymbol
            )
        }

        registerSyntheticExceptionConstructors(
            ownerSymbol: cancellationSymbol,
            ownerType: cancellationType,
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )

        if symbols.lookup(fqName: coroutinesPkg + [cancellationName]) == nil {
            let kotlinxCancellationSymbol = symbols.define(
                kind: .typeAlias,
                name: cancellationName,
                fqName: coroutinesPkg + [cancellationName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setTypeAliasUnderlyingType(cancellationType, for: kotlinxCancellationSymbol)
        }

        registerSyntheticCoroutineTopLevelFunction(
            named: "runBlocking",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "launch",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: jobType,
            symbols: symbols,
            interner: interner
        )
        // STDLIB-CORO-072: Dispatcher-aware overload: launch(context, block)
        registerSyntheticCoroutineTopLevelFunction(
            named: "launch",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: dispatcherType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.unitType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: jobType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "intercepted",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            receiverType: continuationType,
            parameters: [],
            returnType: continuationType,
            externalLinkName: "kk_continuation_intercepted",
            typeParameterSymbols: [continuationTypeParameterSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        let createCoroutineReceiverTypeParameterName = interner.intern("R")
        let createCoroutineReceiverTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: createCoroutineReceiverTypeParameterName,
            fqName: kotlinCoroutinesIntrinsicsPkg + [interner.intern("createCoroutineUnintercepted"), interner.intern("$synthetic"), createCoroutineReceiverTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let createCoroutineReceiverTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: createCoroutineReceiverTypeParameterSymbol,
            nullability: .nonNull
        )))
        let createCoroutineTypeParameterName = interner.intern("T")
        let createCoroutineTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: createCoroutineTypeParameterName,
            fqName: kotlinCoroutinesIntrinsicsPkg + [interner.intern("createCoroutineUnintercepted"), interner.intern("$synthetic"), createCoroutineTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let createCoroutineTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: createCoroutineTypeParameterSymbol,
            nullability: .nonNull
        )))
        let createCoroutineNoReceiverFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: createCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let createCoroutineWithReceiverFunctionType = types.make(.functionType(FunctionType(
            receiver: createCoroutineReceiverTypeParameterType,
            params: [],
            returnType: createCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        registerSyntheticCoroutineExtensionFunction(
            named: "createCoroutineUnintercepted",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            receiverType: createCoroutineNoReceiverFunctionType,
            parameters: [(name: "completion", type: continuationType)],
            returnType: continuationOfUnitType,
            typeParameterSymbols: [createCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "createCoroutineUnintercepted",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            receiverType: createCoroutineWithReceiverFunctionType,
            parameters: [
                (name: "receiver", type: createCoroutineReceiverTypeParameterType),
                (name: "completion", type: continuationType),
            ],
            returnType: continuationOfUnitType,
            typeParameterSymbols: [createCoroutineReceiverTypeParameterSymbol, createCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: continuationInterceptorSymbol,
            ownerType: continuationInterceptorType,
            name: "interceptContinuation",
            externalLinkName: "kk_continuation_interceptor_intercept_continuation",
            returnType: continuationType,
            parameters: [(name: "continuation", type: continuationType)],
            typeParameterSymbols: [continuationTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "async",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: deferredType,
            symbols: symbols,
            interner: interner
        )
        // STDLIB-CORO-075: `produce { ... }` returns a `Channel<T>` and runs the
        // block with a `Channel<T>` receiver so channel sends resolve correctly.
        let functionName = interner.intern("produce")
        let functionFQName = channelsPkg + [functionName]
        if symbols.lookup(fqName: functionFQName) == nil {
            let typeParamName = interner.intern("T")
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let produceChannelType = types.make(.classType(ClassType(
                classSymbol: channelSymbol,
                args: [.invariant(typeParamType)],
                nullability: .nonNull
            )))
            let blockType = types.make(.functionType(FunctionType(
                receiver: produceChannelType,
                params: [],
                returnType: types.unitType,
                isSuspend: true,
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
            if let packageSymbol = symbols.lookup(fqName: channelsPkg) {
                symbols.setParentSymbol(packageSymbol, for: functionSymbol)
            }
            symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
            let paramName = interner.intern("block")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setExternalLinkName("kk_produce", for: functionSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [blockType],
                    returnType: produceChannelType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol]
                ),
                for: functionSymbol
            )
        }
        registerSyntheticCoroutineTopLevelFunction(
            named: "coroutineScope",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "supervisorScope",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "delay",
            packageFQName: coroutinesPkg,
            parameterName: "timeMillis",
            parameterType: types.longType,
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "yield",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "withTimeout",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "timeMillis", type: types.longType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "withTimeoutOrNull",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "timeMillis", type: types.longType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.nullableAnyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: dispatcherType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-CORO-077: CoroutineContext, CoroutineContext.Element, CoroutineContext.Key
        let coroutineContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineContextType = types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextType, for: coroutineContextSymbol)

        let coroutineContextFQName = kotlinCoroutinesPkg + [interner.intern("CoroutineContext")]
        let coroutineContextElementSymbol = ensureInterfaceSymbol(
            named: "Element",
            in: coroutineContextFQName,
            symbols: symbols,
            interner: interner,
            visibility: .internal
        )
        symbols.setParentSymbol(coroutineContextSymbol, for: coroutineContextElementSymbol)
        let coroutineContextElementType = types.make(.classType(ClassType(
            classSymbol: coroutineContextElementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextElementType, for: coroutineContextElementSymbol)
        symbols.setDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)
        symbols.setDirectSupertypes([coroutineContextElementSymbol], for: jobSymbol)

        let coroutineContextKeySymbol = ensureInterfaceSymbol(
            named: "Key",
            in: coroutineContextFQName,
            symbols: symbols,
            interner: interner,
            visibility: .internal
        )
        symbols.setParentSymbol(coroutineContextSymbol, for: coroutineContextKeySymbol)
        let coroutineContextKeyTypeParamName = interner.intern("E")
        let coroutineContextKeyTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: coroutineContextKeyTypeParamName,
            fqName: coroutineContextFQName + [interner.intern("Key"), interner.intern("$synthetic"), coroutineContextKeyTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(coroutineContextKeySymbol, for: coroutineContextKeyTypeParamSymbol)
        let coroutineContextKeyTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: coroutineContextKeyTypeParamSymbol,
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([coroutineContextElementType], for: coroutineContextKeyTypeParamSymbol)
        let coroutineContextKeyType = types.make(.classType(ClassType(
            classSymbol: coroutineContextKeySymbol,
            args: [.invariant(coroutineContextKeyTypeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextKeyType, for: coroutineContextKeySymbol)

        let coroutineContextKeyTypeParamBound = coroutineContextElementType

        // CoroutineContext.get(key: Key<E>): E?
        do {
            let functionName = interner.intern("get")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let functionTypeParamName = interner.intern("E")
                let functionTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: functionTypeParamName,
                    fqName: functionFQName + [interner.intern("$synthetic"), functionTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let functionTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: functionTypeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([coroutineContextKeyTypeParamBound], for: functionTypeParamSymbol)

                let keyType = types.make(.classType(ClassType(
                    classSymbol: coroutineContextKeySymbol,
                    args: [.invariant(functionTypeParamType)],
                    nullability: .nonNull
                )))
                let keyParamName = interner.intern("key")
                let keyParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: keyParamName,
                    fqName: functionFQName + [keyParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: keyParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [keyType],
                        returnType: types.makeNullable(functionTypeParamType),
                        valueParameterSymbols: [keyParamSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: [functionTypeParamSymbol],
                        typeParameterUpperBoundsList: [[coroutineContextKeyTypeParamBound]]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_get", for: functionSymbol)
            }
        }

        // CoroutineContext.fold(initial: R, operation: (R, Element) -> R): R
        do {
            let functionName = interner.intern("fold")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let rTypeParamName = interner.intern("R")
                let rTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: rTypeParamName,
                    fqName: functionFQName + [interner.intern("$synthetic"), rTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let rType = types.make(.typeParam(TypeParamType(
                    symbol: rTypeParamSymbol,
                    nullability: .nonNull
                )))
                let operationType = types.make(.functionType(FunctionType(
                    params: [rType, coroutineContextElementType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let initialParamName = interner.intern("initial")
                let initialParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: initialParamName,
                    fqName: functionFQName + [initialParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let operationParamName = interner.intern("operation")
                let operationParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: operationParamName,
                    fqName: functionFQName + [operationParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: initialParamSymbol)
                symbols.setParentSymbol(functionSymbol, for: operationParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [rType, operationType],
                        returnType: rType,
                        valueParameterSymbols: [initialParamSymbol, operationParamSymbol],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [rTypeParamSymbol]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_fold", for: functionSymbol)
            }
        }

        // CoroutineContext.minusKey(key: Key<*>): CoroutineContext
        do {
            let functionName = interner.intern("minusKey")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let keyType = types.make(.classType(ClassType(
                    classSymbol: coroutineContextKeySymbol,
                    args: [.star],
                    nullability: .nonNull
                )))
                let keyParamName = interner.intern("key")
                let keyParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: keyParamName,
                    fqName: functionFQName + [keyParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: keyParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [keyType],
                        returnType: coroutineContextType,
                        valueParameterSymbols: [keyParamSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_minusKey", for: functionSymbol)
            }
        }

        // CoroutineContext.cancel() and CoroutineContext.cancel(cause)
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineContextSymbol,
            ownerType: coroutineContextType,
            name: "cancel",
            externalLinkName: "kk_context_cancel_no_cause",
            returnType: types.unitType,
            parameters: [],
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineContextSymbol,
            ownerType: coroutineContextType,
            name: "cancel",
            externalLinkName: "kk_context_cancel",
            returnType: types.unitType,
            parameters: [(name: "cause", type: types.makeNullable(rootCancellationType))],
            flags: [.synthetic],
            symbols: symbols,
            interner: interner
        )

        let coroutineNameSymbol = ensureClassSymbol(
            named: "CoroutineName",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineNameType = types.make(.classType(ClassType(
            classSymbol: coroutineNameSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineNameType, for: coroutineNameSymbol)
        symbols.setDirectSupertypes([coroutineContextSymbol], for: coroutineNameSymbol)
        types.setNominalDirectSupertypes([coroutineContextSymbol], for: coroutineNameSymbol)

        let coroutineExceptionHandlerSymbol = ensureClassSymbol(
            named: "CoroutineExceptionHandler",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineExceptionHandlerType = types.make(.classType(ClassType(
            classSymbol: coroutineExceptionHandlerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineExceptionHandlerType, for: coroutineExceptionHandlerSymbol)
        symbols.setDirectSupertypes([coroutineContextSymbol], for: coroutineExceptionHandlerSymbol)
        types.setNominalDirectSupertypes([coroutineContextSymbol], for: coroutineExceptionHandlerSymbol)

        // Make CoroutineDispatcher a subtype of CoroutineContext and ContinuationInterceptor.
        symbols.setDirectSupertypes([coroutineContextSymbol, continuationInterceptorSymbol], for: dispatcherSymbol)
        types.setNominalDirectSupertypes([coroutineContextSymbol, continuationInterceptorSymbol], for: dispatcherSymbol)

        let flowBuilderLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType,
            isSuspend: true,
            nullability: .nonNull
        )))

        // CoroutineName(name: String) constructor
        registerSyntheticCoroutineTopLevelFunction(
            named: "CoroutineName",
            packageFQName: coroutinesPkg,
            parameters: [(name: "name", type: types.stringType)],
            returnType: coroutineNameType,
            externalLinkName: "kk_coroutine_name_create",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineConstructor(
            ownerSymbol: coroutineNameSymbol,
            ownerType: coroutineNameType,
            externalLinkName: "kk_coroutine_name_create",
            parameters: [(name: "name", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // CoroutineExceptionHandler { context, exception -> } factory
        registerSyntheticCoroutineTopLevelFunction(
            named: "CoroutineExceptionHandler",
            packageFQName: coroutinesPkg,
            parameters: [(name: "handler", type: types.make(.functionType(FunctionType(
                params: [kotlinCoroutineContextType, types.anyType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            returnType: coroutineExceptionHandlerType,
            externalLinkName: "kk_exception_handler_create",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineConstructor(
            ownerSymbol: coroutineExceptionHandlerSymbol,
            ownerType: coroutineExceptionHandlerType,
            externalLinkName: "kk_exception_handler_create",
            parameters: [(name: "handler", type: types.make(.functionType(FunctionType(
                params: [kotlinCoroutineContextType, types.anyType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            symbols: symbols,
            interner: interner
        )

        // Flow builders
        registerSyntheticCoroutineTopLevelFunction(
            named: "flow",
            packageFQName: flowPkg,
            parameters: [(name: "block", type: flowBuilderLambdaType)],
            returnType: flowRawType,
            externalLinkName: "kk_flow_create",
            syntheticTypeParameterNames: ["T"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "channelFlow",
            packageFQName: flowPkg,
            parameters: [(name: "block", type: flowBuilderLambdaType)],
            returnType: flowRawType,
            externalLinkName: "kk_flow_create",
            syntheticTypeParameterNames: ["T"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "callbackFlow",
            packageFQName: flowPkg,
            parameters: [(name: "block", type: flowBuilderLambdaType)],
            returnType: flowRawType,
            externalLinkName: "kk_flow_create",
            syntheticTypeParameterNames: ["T"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "flowOf",
            packageFQName: flowPkg,
            parameters: [(name: "values", type: types.anyType)],
            returnType: flowRawType,
            externalLinkName: "kk_flow_of",
            syntheticTypeParameterNames: ["T"],
            syntheticVarargParameterIndices: [0],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "emptyFlow",
            packageFQName: flowPkg,
            parameters: [],
            returnType: flowRawType,
            externalLinkName: "kk_flow_empty",
            syntheticTypeParameterNames: ["T"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "asFlow",
            externalLinkName: "kk_flow_as_flow",
            returnType: flowRawType,
            symbols: symbols,
            interner: interner
        )

        // withContext overload accepting CoroutineContext (not just dispatcher)
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: kotlinCoroutineContextType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineTopLevelProperty(
            named: "COROUTINE_SUSPENDED",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            returnType: coroutineSuspendedType,
            externalLinkName: "kk_coroutine_suspended",
            symbols: symbols,
            interner: interner
        )
        let suspendCoroutineName = interner.intern("suspendCoroutineUninterceptedOrReturn")
        let suspendCoroutineFQName = kotlinCoroutinesIntrinsicsPkg + [suspendCoroutineName]
        if symbols.lookup(fqName: suspendCoroutineFQName) == nil {
            let suspendCoroutineTypeParamName = interner.intern("T")
            let suspendCoroutineTypeParamFQName = suspendCoroutineFQName + [suspendCoroutineTypeParamName]
            let suspendCoroutineTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: suspendCoroutineTypeParamName,
                fqName: suspendCoroutineTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let suspendCoroutineTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: suspendCoroutineTypeParamSymbol,
                nullability: .nonNull
            )))
            let suspendCoroutineContinuationType = types.make(.classType(ClassType(
                classSymbol: continuationSymbol,
                args: [.invariant(suspendCoroutineTypeParamType)],
                nullability: .nonNull
            )))
            let suspendCoroutineBlockType = types.make(.functionType(FunctionType(
                params: [suspendCoroutineContinuationType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let suspendCoroutineBlockName = interner.intern("block")
            let suspendCoroutineBlockSymbol = symbols.define(
                kind: .valueParameter,
                name: suspendCoroutineBlockName,
                fqName: suspendCoroutineFQName + [suspendCoroutineBlockName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let suspendCoroutineSymbol = symbols.define(
                kind: .function,
                name: suspendCoroutineName,
                fqName: suspendCoroutineFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesIntrinsicsPkg) {
                symbols.setParentSymbol(packageSymbol, for: suspendCoroutineSymbol)
            }
            symbols.setParentSymbol(suspendCoroutineSymbol, for: suspendCoroutineTypeParamSymbol)
            symbols.setParentSymbol(suspendCoroutineSymbol, for: suspendCoroutineBlockSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [suspendCoroutineBlockType],
                    returnType: suspendCoroutineTypeParamType,
                    isSuspend: true,
                    valueParameterSymbols: [suspendCoroutineBlockSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [suspendCoroutineTypeParamSymbol],
                    classTypeParameterCount: 0
                ),
                for: suspendCoroutineSymbol
            )
        }

        registerSyntheticCoroutineTopLevelFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            parameters: [(name: "message", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_coroutine_cancel_current",
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineTopLevelFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            parameters: [
                (name: "message", type: types.stringType),
                (name: "cause", type: types.makeNullable(types.anyType)),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_coroutine_cancel_current",
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )

        // CoroutineContext.plus(other: CoroutineContext): CoroutineContext
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineContextSymbol,
            ownerType: coroutineContextType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: kotlinCoroutineContextType,
            parameters: [(name: "context", type: kotlinCoroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: dispatcherSymbol,
            ownerType: dispatcherType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: kotlinCoroutineContextType,
            parameters: [(name: "context", type: kotlinCoroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineNameSymbol,
            ownerType: coroutineNameType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: kotlinCoroutineContextType,
            parameters: [(name: "context", type: kotlinCoroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineExceptionHandlerSymbol,
            ownerType: coroutineExceptionHandlerType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: kotlinCoroutineContextType,
            parameters: [(name: "context", type: kotlinCoroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: kotlinCoroutineContextType,
            parameters: [(name: "context", type: kotlinCoroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineConstructor(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            externalLinkName: "kk_channel_create",
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticChannelFactoryBridge(
            packageFQName: channelsPkg,
            channelSymbol: channelSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticChannelFactoryBridgeWithCapacity(
            packageFQName: channelsPkg,
            channelSymbol: channelSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "Default",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "IO",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "Main",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "cancel",
            externalLinkName: "kk_job_cancel",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "cancel",
            externalLinkName: "kk_job_cancel_with_cause",
            returnType: types.unitType,
            parameters: [(name: "cause", type: types.nullableAnyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "join",
            externalLinkName: "kk_job_join",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "awaitCompletion",
            externalLinkName: "kk_job_await_completion",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "complete",
            externalLinkName: "kk_job_complete",
            returnType: types.booleanType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "completeExceptionally",
            externalLinkName: "kk_job_complete_exceptionally",
            returnType: types.booleanType,
            parameters: [(name: "exception", type: types.nullableAnyType)],
            symbols: symbols,
            interner: interner
        )

        // STDLIB-CORO-070: Job state properties
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isActive",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_active",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isCompleted",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_completed",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isCancelled",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_cancelled",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: deferredSymbol,
            ownerType: deferredType,
            name: "await",
            externalLinkName: "kk_kxmini_async_await",
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        let listAnyType: TypeID = if let listSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]) {
            types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(types.anyType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        registerSyntheticCoroutineConstructor(
            ownerSymbol: mutableSharedFlowSymbol,
            ownerType: mutableSharedFlowType,
            externalLinkName: "kk_mutable_shared_flow_create",
            parameters: [(name: "replay", type: types.intType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineConstructor(
            ownerSymbol: mutableStateFlowSymbol,
            ownerType: mutableStateFlowType,
            externalLinkName: "kk_mutable_state_flow_create",
            parameters: [(name: "initialValue", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "shareIn",
            externalLinkName: "kk_flow_share_in",
            returnType: sharedFlowRawType,
            parameters: [(name: "replay", type: types.intType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "stateIn",
            externalLinkName: "kk_flow_state_in",
            returnType: stateFlowRawType,
            parameters: [(name: "initialValue", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: sharedFlowSymbol,
            ownerType: sharedFlowRawType,
            name: "collect",
            externalLinkName: "kk_shared_flow_collect",
            returnType: types.unitType,
            parameters: [(name: "collector", type: types.make(.functionType(FunctionType(
                params: [types.anyType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: sharedFlowSymbol,
            ownerType: sharedFlowRawType,
            name: "replayCache",
            propertyType: listAnyType,
            externalLinkName: "kk_shared_flow_replay_cache",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: stateFlowSymbol,
            ownerType: stateFlowRawType,
            name: "value",
            propertyType: types.anyType,
            externalLinkName: "kk_state_flow_value",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: mutableSharedFlowSymbol,
            ownerType: mutableSharedFlowType,
            name: "emit",
            externalLinkName: "kk_mutable_shared_flow_emit",
            returnType: types.unitType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: mutableSharedFlowSymbol,
            ownerType: mutableSharedFlowType,
            name: "tryEmit",
            externalLinkName: "kk_mutable_shared_flow_try_emit",
            returnType: types.booleanType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: mutableStateFlowSymbol,
            ownerType: mutableStateFlowType,
            name: "emit",
            externalLinkName: "kk_mutable_state_flow_emit",
            returnType: types.unitType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: mutableStateFlowSymbol,
            ownerType: mutableStateFlowType,
            name: "tryEmit",
            externalLinkName: "kk_mutable_state_flow_try_emit",
            returnType: types.booleanType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "send",
            externalLinkName: "kk_channel_send",
            returnType: types.unitType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "receive",
            externalLinkName: "kk_channel_receive",
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "close",
            externalLinkName: "kk_channel_close",
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
        // Channel.isClosedForReceive: Boolean (CORO-075)
        registerSyntheticObjectProperty(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "isClosedForReceive",
            propertyType: types.booleanType,
            externalLinkName: "kk_channel_is_closed_for_receive",
            symbols: symbols,
            interner: interner
        )

        // Channel.isClosedForSend: Boolean (CORO-075)
        registerSyntheticObjectProperty(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "isClosedForSend",
            propertyType: types.booleanType,
            externalLinkName: "kk_channel_is_closed_for_send",
            symbols: symbols,
            interner: interner
        )

        // Channel.isClosedForReceive: Boolean (CORO-075)
        registerSyntheticObjectProperty(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "isClosedForReceive",
            propertyType: types.booleanType,
            externalLinkName: "kk_channel_is_closed_for_receive",
            symbols: symbols,
            interner: interner
        )

        // Channel.isClosedForSend: Boolean (CORO-075)
        registerSyntheticObjectProperty(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "isClosedForSend",
            propertyType: types.booleanType,
            externalLinkName: "kk_channel_is_closed_for_send",
            symbols: symbols,
            interner: interner
        )

        let emptyCoroutineContextSymbol = ensureObjectSymbol(
            named: "EmptyCoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let emptyCoroutineContextType = types.make(.classType(ClassType(
            classSymbol: emptyCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(emptyCoroutineContextType, for: emptyCoroutineContextSymbol)
        symbols.setDirectSupertypes([kotlinCoroutineContextSymbol], for: emptyCoroutineContextSymbol)
        types.setNominalDirectSupertypes([kotlinCoroutineContextSymbol], for: emptyCoroutineContextSymbol)

        // Mutex (kotlinx.coroutines.sync.Mutex)
        let syncPkg = ensureSyntheticPackage(
            coroutinesPkg + [interner.intern("sync")],
            symbols: symbols,
            interner: interner
        )
        let mutexSymbol = ensureInterfaceSymbol(
            named: "Mutex",
            in: syncPkg,
            symbols: symbols,
            interner: interner
        )
        let mutexType = types.make(.classType(ClassType(
            classSymbol: mutexSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(mutexType, for: mutexSymbol)

        // Mutex() factory function
        registerSyntheticCoroutineTopLevelFunction(
            named: "Mutex",
            packageFQName: syncPkg,
            parameters: [],
            returnType: mutexType,
            externalLinkName: "kk_mutex_create",
            symbols: symbols,
            interner: interner
        )

        // Mutex.lock() suspend
        registerSyntheticCoroutineMember(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "lock",
            externalLinkName: "kk_mutex_lock",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Mutex.unlock()
        registerSyntheticCoroutineMember(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "unlock",
            externalLinkName: "kk_mutex_unlock",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Mutex.tryLock(): Boolean
        registerSyntheticCoroutineMember(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "tryLock",
            externalLinkName: "kk_mutex_tryLock",
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // Mutex.isLocked property
        registerSyntheticObjectProperty(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "isLocked",
            propertyType: types.booleanType,
            externalLinkName: "kk_mutex_isLocked",
            symbols: symbols,
            interner: interner
        )

        // Mutex.withLock(action: () -> T): T
        // Suspend-style helper that acquires the lock, runs action, then releases.
        registerSyntheticCoroutineMember(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "withLock",
            externalLinkName: "kk_mutex_withLock",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            )],
            symbols: symbols,
            interner: interner
        )

        // Semaphore (kotlinx.coroutines.sync.Semaphore)
        let semaphoreSymbol = ensureInterfaceSymbol(
            named: "Semaphore",
            in: syncPkg,
            symbols: symbols,
            interner: interner
        )
        let semaphoreType = types.make(.classType(ClassType(
            classSymbol: semaphoreSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(semaphoreType, for: semaphoreSymbol)

        // Semaphore(permits) factory function
        registerSyntheticCoroutineTopLevelFunction(
            named: "Semaphore",
            packageFQName: syncPkg,
            parameters: [(name: "permits", type: types.intType)],
            returnType: semaphoreType,
            externalLinkName: "kk_semaphore_create",
            symbols: symbols,
            interner: interner
        )

        // Semaphore.acquire() suspend
        registerSyntheticCoroutineMember(
            ownerSymbol: semaphoreSymbol,
            ownerType: semaphoreType,
            name: "acquire",
            externalLinkName: "kk_semaphore_acquire",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Semaphore.release()
        registerSyntheticCoroutineMember(
            ownerSymbol: semaphoreSymbol,
            ownerType: semaphoreType,
            name: "release",
            externalLinkName: "kk_semaphore_release",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Semaphore.tryAcquire(): Boolean
        registerSyntheticCoroutineMember(
            ownerSymbol: semaphoreSymbol,
            ownerType: semaphoreType,
            name: "tryAcquire",
            externalLinkName: "kk_semaphore_tryAcquire",
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // Semaphore.availablePermits property
        registerSyntheticObjectProperty(
            ownerSymbol: semaphoreSymbol,
            ownerType: semaphoreType,
            name: "availablePermits",
            propertyType: types.intType,
            externalLinkName: "kk_semaphore_availablePermits",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineExtensionFunction(
            named: "cancel",
            packageFQName: kotlinCoroutinesCancellationPkg,
            receiverType: kotlinCoroutineContextType,
            externalLinkName: "kk_context_cancel",
            returnType: types.unitType,
            parameters: [(name: "cause", type: types.makeNullable(rootCancellationType))],
            symbols: symbols,
            interner: interner
        )

    }

    func registerSyntheticCoroutineCancellationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jobFQName: [InternedString] = [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("Job")]
        guard let jobSymbol = symbols.lookup(fqName: jobFQName) else {
            return
        }
        let jobType = types.make(.classType(ClassType(
            classSymbol: jobSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cancellationPkg = ensureSyntheticPackage(
            ensurePackage(
                path: ["kotlin", "coroutines", "cancellation"],
                symbols: symbols,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineExtensionFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            receiverType: jobType,
            externalLinkName: "kk_job_cancel",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        isSuspend: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticCoroutineTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            isSuspend: isSuspend,
            flags: flags,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        syntheticTypeParameterNames: [String] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }

        var functionTypeParameterSymbols = typeParameterSymbols
        if !syntheticTypeParameterNames.isEmpty {
            let localNamespaceFQName = functionFQName + [interner.intern("$synthetic")]
            for typeParamName in syntheticTypeParameterNames {
                let internedTypeParamName = interner.intern(typeParamName)
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: internedTypeParamName,
                    fqName: localNamespaceFQName + [internedTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                functionTypeParameterSymbols.append(typeParamSymbol)
            }
        }

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: functionTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        isSuspend: Bool = false,
        syntheticTypeParameterNames: [String] = [],
        flags: SymbolFlags = [.synthetic],
        explicitTypeParameterSymbols: [SymbolID]? = nil,
        syntheticVarargParameterIndices: Set<Int> = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        // Skip only true duplicate function signatures. Allow overloads with the
        // same arity but different parameter types, and allow nominal types to
        // share the same FQName with factory-style functions.
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == nil
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        var typeParameterSymbols: [SymbolID] = []
        if let explicitTypeParameterSymbols {
            typeParameterSymbols = explicitTypeParameterSymbols
            for typeParameterSymbol in explicitTypeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }
        } else if !syntheticTypeParameterNames.isEmpty {
            let localNamespaceFQName = functionFQName + [interner.intern("$synthetic")]
            for typeParamName in syntheticTypeParameterNames {
                let internedTypeParamName = interner.intern(typeParamName)
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: internedTypeParamName,
                    fqName: localNamespaceFQName + [internedTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
                typeParameterSymbols.append(typeParamSymbol)
            }
        }
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: isSuspend,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: parameters.indices.map { syntheticVarargParameterIndices.contains($0) },
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    private func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        externalLinkName: String,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        if let existing = existingSymbols.first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String? = nil,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        guard symbols.lookup(fqName: ctorFQName) == nil else {
            return
        }
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
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
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }
    }

    private func ensureObjectSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .object,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerSyntheticChannelFactoryBridge(
        packageFQName: [InternedString],
        channelSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("Channel")
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_channel_create", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    /// Registers a synthetic `Channel(capacity: Int)` factory function that maps
    /// to `kk_channel_create` for buffered channel construction.
    private func registerSyntheticChannelFactoryBridgeWithCapacity(
        packageFQName: [InternedString],
        channelSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("Channel")
        // Use a unique synthetic suffix to distinguish from the no-arg overload.
        let overloadFQName = packageFQName + [interner.intern("Channel$capacity")]
        guard symbols.lookup(fqName: overloadFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: overloadFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_channel_create", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: overloadFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let capacityParamName = interner.intern("capacity")
        let capacityParamSymbol = symbols.define(
            kind: .valueParameter,
            name: capacityParamName,
            fqName: overloadFQName + [capacityParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: capacityParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.intType],
                returnType: returnType,
                valueParameterSymbols: [capacityParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func ensureSyntheticPackage(
        _ fqName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if symbols.lookup(fqName: fqName) == nil {
            _ = symbols.define(
                kind: .package,
                name: fqName.last ?? interner.intern("_root_"),
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return fqName
    }

    func registerSyntheticCoroutineIntrinsicsStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinCoroutinesPkg = ensureSyntheticPackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let intrinsicsPkg = ensureSyntheticPackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelProperty(
            named: "COROUTINE_SUSPENDED",
            packageFQName: intrinsicsPkg,
            returnType: types.nullableAnyType,
            externalLinkName: "kk_coroutine_suspended",
            symbols: symbols,
            interner: interner
        )
    }
}
