// Consolidated residual coroutine Sema registry (RF-STUB-005).
// Keeps coroutine package, ABI, and helper registration in one file so similarly
// named residual files do not drift apart.

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
        let kotlinCoroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesIntrinsicsPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        let cancellationPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )
        let kotlinxPkg = ensureSyntheticCoroutinePackage(
            [interner.intern("kotlinx")],
            symbols: symbols,
            interner: interner
        )
        let coroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinxPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesCancellationPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )
        let restrictsSuspensionSymbol = ensureAnnotationClassSymbol(
            named: "RestrictsSuspension",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinCoroutinesPkgSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
            symbols.setParentSymbol(kotlinCoroutinesPkgSymbol, for: restrictsSuspensionSymbol)
        }
        attachRestrictsSuspensionAnnotationMetadata(
            to: restrictsSuspensionSymbol,
            symbols: symbols
        )
        let restrictsSuspensionFQName = kotlinCoroutinesPkg + [interner.intern("RestrictsSuspension")]
        registerSyntheticConstructorStubs(
            [SyntheticConstructorStubSpec()],
            ownerType: .classType(
                fqName: ["kotlin", "coroutines", "RestrictsSuspension"],
                args: [],
                nullability: .nonNull
            ),
            context: SyntheticStubRegistrationContext(
                ownerFQName: restrictsSuspensionFQName,
                parentSymbol: restrictsSuspensionSymbol
            ),
            symbols: symbols,
            types: types,
            interner: interner
        )
        let channelsPkg = ensureSyntheticCoroutinePackage(
            coroutinesPkg + [interner.intern("channels")],
            symbols: symbols,
            interner: interner
        )
        let flowPkg = ensureSyntheticCoroutinePackage(
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
            args: [.invariant(kotlinResultTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([kotlinResultTypeParamSymbol], for: kotlinResultSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: kotlinResultSymbol)
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
        let suspendFunctionSymbol = ensureInterfaceSymbol(
            named: "SuspendFunction",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let suspendFunctionTypeParamName = interner.intern("R")
        let suspendFunctionTypeParamFQName = kotlinCoroutinesPkg + [
            interner.intern("SuspendFunction"),
            suspendFunctionTypeParamName,
        ]
        let suspendFunctionTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: suspendFunctionTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: suspendFunctionTypeParamName,
                fqName: suspendFunctionTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(suspendFunctionSymbol, for: suspendFunctionTypeParamSymbol)
        let suspendFunctionReturnType = types.make(.typeParam(TypeParamType(
            symbol: suspendFunctionTypeParamSymbol,
            nullability: .nonNull
        )))
        let suspendFunctionType = types.make(.classType(ClassType(
            classSymbol: suspendFunctionSymbol,
            args: [.out(suspendFunctionReturnType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([suspendFunctionTypeParamSymbol], for: suspendFunctionSymbol)
        types.setNominalTypeParameterVariances([.out], for: suspendFunctionSymbol)
        symbols.setPropertyType(suspendFunctionType, for: suspendFunctionSymbol)
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
        let continuationFactoryTypeParamName = interner.intern("T")
        let continuationFactoryTypeParamFQName = kotlinCoroutinesPkg + [
            interner.intern("Continuation"),
            interner.intern("$factory"),
            continuationFactoryTypeParamName,
        ]
        let continuationFactoryTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: continuationFactoryTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: continuationFactoryTypeParamName,
                fqName: continuationFactoryTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let continuationFactoryTType = types.make(.typeParam(TypeParamType(
            symbol: continuationFactoryTypeParamSymbol,
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
        // STDLIB-CORO-076: `CoroutineScope` is registered as an empty marker
        // interface so extension functions declared as `fun CoroutineScope.foo()`
        // (a common pattern for user-defined producer/consumer helpers) type-check.
        // Builder blocks (runBlocking/launch/coroutineScope/...) do not yet carry
        // this as their lambda receiver type, so such extensions only resolve when
        // called with an explicit receiver.
        _ = ensureInterfaceSymbol(
            named: "CoroutineScope",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
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
        let dispatchersSymbol = ensureSyntheticObjectSymbol(
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
        // KSP-675: SharedFlow / MutableSharedFlow are declared by bundled Kotlin
        // source (Sources/CompilerCore/Stdlib/kotlinx/coroutines/flow/SharedFlow.kt),
        // so no synthetic symbols are registered for them here.
        // KSP-676: StateFlow / MutableStateFlow are also bundled Kotlin source
        // (StateFlow.kt), so no synthetic symbols are registered for them either.
        // KSP-499 Stage 2: give the Flow interface a real generic type parameter
        // (previously `args: []` on every ClassType use, with the element type
        // tracked only in the Sema side-tables `flowElementTypesByExpr`/`BySymbol`
        // — see SemanticsModels.swift). Flow is read-only and covariant
        // (`Flow<out T>` in kotlinx.coroutines).
        // Pattern mirrors `registerSyntheticIterableStub` in
        // HeaderHelpers+SyntheticCollectionTypeFallbacks.swift.
        func declareFlowFamilyTypeParameter(
            owner: SymbolID,
            ownerFQName: [InternedString],
            variance: TypeVariance
        ) -> SymbolID {
            let typeParamName = interner.intern("T")
            let typeParamFQName = ownerFQName + [typeParamName]
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
            types.setNominalTypeParameterSymbols([typeParamSymbol], for: owner)
            types.setNominalTypeParameterVariances([variance], for: owner)
            return typeParamSymbol
        }
        let flowTypeParamSymbol = declareFlowFamilyTypeParameter(
            owner: flowInterfaceSymbol,
            ownerFQName: flowPkg + [interner.intern("Flow")],
            variance: .out
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
        // KSP-678: `ChannelIterator<T>` is the runtime handle returned by
        // `Channel<T>.iterator()`. Registered as a synthetic handle type (like
        // Channel itself) so the bundled Kotlin iterator/hasNext/next extension
        // operators in Channels.kt can bridge to the residual
        // kk_channel_iterator{,_hasNext,_next} runtime entry points.
        let channelIteratorSymbol = ensureClassSymbol(
            named: "ChannelIterator",
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
        let cancellationIsSourceBacked = !(symbols.symbol(cancellationSymbol)?.flags.contains(.synthetic) ?? true)
        let illegalStateExceptionSymbol: SymbolID?
        if cancellationIsSourceBacked {
            illegalStateExceptionSymbol = nil
        } else {
            illegalStateExceptionSymbol = ensureClassSymbol(
                named: "IllegalStateException",
                in: kotlinPkg,
                symbols: symbols,
                interner: interner
            )
        }
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
        // KSP-499 Stage 2: use each class's own type parameter as the receiver
        // "self type" (matching `iterableReceiverType` in
        // HeaderHelpers+SyntheticCollectionTypeFallbacks.swift) instead of a raw,
        // argument-less ClassType. This is the generic *declaration* shape used
        // as an owner/receiver/return type placeholder throughout this file —
        // callers substitute concrete element types at actual call sites.
        let flowRawType = types.make(.classType(ClassType(
            classSymbol: flowInterfaceSymbol,
            args: [.out(types.make(.typeParam(TypeParamType(symbol: flowTypeParamSymbol, nullability: .nonNull))))],
            nullability: .nonNull
        )))
        let dispatcherType = types.make(.classType(ClassType(
            classSymbol: dispatcherSymbol,
            args: [],
            nullability: .nonNull
        )))
        // STDLIB-CORO-001: CoroutineStart enum for launch(start:) overload.
        let coroutineStartSymbol = ensureEnumClassSymbol(
            named: "CoroutineStart",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineStartType = types.make(.classType(ClassType(
            classSymbol: coroutineStartSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineStartFQName = coroutinesPkg + [interner.intern("CoroutineStart")]
        for entryName in ["DEFAULT", "LAZY", "ATOMIC", "UNDISPATCHED"] {
            let entryInterned = interner.intern(entryName)
            let entryFQName = coroutineStartFQName + [entryInterned]
            if symbols.lookup(fqName: entryFQName) == nil {
                let entrySymbol = symbols.define(
                    kind: .field,
                    name: entryInterned,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineStartSymbol, for: entrySymbol)
                symbols.setPropertyType(coroutineStartType, for: entrySymbol)
            }
        }
        let channelType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [],
            nullability: .nonNull
        )))
        let channelIteratorType = types.make(.classType(ClassType(
            classSymbol: channelIteratorSymbol,
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

        let resultOfContinuationFactoryTType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        let continuationFactoryResumeWithType = types.make(.functionType(FunctionType(
            params: [resultOfContinuationFactoryTType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let continuationFactoryReturnType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "Continuation",
            packageFQName: kotlinCoroutinesPkg,
            parameters: [
                (name: "context", type: kotlinCoroutineContextType),
                (name: "resumeWith", type: continuationFactoryResumeWithType),
            ],
            returnType: continuationFactoryReturnType,
            externalLinkName: "kk_coroutine_continuation_factory",
            explicitTypeParameterSymbols: [continuationFactoryTypeParamSymbol],
            valueParameterFQNameSuffixes: ["$factoryContext", "$factoryResumeWith"],
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
        registerSyntheticCoroutineTopLevelProperty(
            named: "coroutineContext",
            packageFQName: kotlinCoroutinesPkg,
            returnType: kotlinCoroutineContextType,
            externalLinkName: "kk_coroutine_current_context",
            symbols: symbols,
            interner: interner
        )
        // kotlinx.coroutines.currentCoroutineContext() is the suspend-function
        // equivalent of the kotlin.coroutines.coroutineContext property above;
        // both read the same ambient context, so they share a backing primitive.
        registerSyntheticCoroutineTopLevelFunction(
            named: "currentCoroutineContext",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: kotlinCoroutineContextType,
            externalLinkName: "kk_coroutine_current_context",
            isSuspend: true,
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
            args: [.invariant(continuationTType)],
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
        let invariantContinuationOfUnitType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(types.unitType)],
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
        symbols.setPropertyType(dispatcherType, for: dispatcherSymbol)
        symbols.setPropertyType(coroutineStartType, for: coroutineStartSymbol)
        symbols.setPropertyType(channelType, for: channelSymbol)
        symbols.setPropertyType(channelIteratorType, for: channelIteratorSymbol)
        symbols.setPropertyType(cancellationType, for: cancellationSymbol)
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        symbols.setPropertyType(continuationInterceptorType, for: continuationInterceptorSymbol)
        symbols.setPropertyType(rootCancellationType, for: rootCancellationSymbol)
        if !cancellationIsSourceBacked, let illegalStateExceptionSymbol {
            symbols.setDirectSupertypes([illegalStateExceptionSymbol], for: cancellationSymbol)
            types.setNominalDirectSupertypes([illegalStateExceptionSymbol], for: cancellationSymbol)
        }
        symbols.setDirectSupertypes([exceptionSymbol], for: rootCancellationSymbol)
        symbols.setDirectSupertypes([continuationInterceptorSymbol], for: dispatcherSymbol)
        types.setNominalTypeParameterSymbols([continuationTypeParameterSymbol], for: continuationSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: continuationSymbol)

        // KSP-499: Flow's cold core remains a compiler/runtime bridge. Keep
        // `collect` and `collectLatest` as synthetic source-visible members so
        // bundled operator bodies lower them to the retained kk_flow_* ABI
        // instead of emitting the parameter name as a native symbol.
        let flowElementType = types.make(.typeParam(TypeParamType(
            symbol: flowTypeParamSymbol,
            nullability: .nonNull
        )))
        let flowCollectorType = types.make(.functionType(FunctionType(
            params: [flowElementType],
            returnType: types.unitType,
            isSuspend: true,
            nullability: .nonNull
        )))
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "collect",
            externalLinkName: "kk_flow_collect",
            returnType: types.unitType,
            parameters: [(name: "collector", type: flowCollectorType)],
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: flowInterfaceSymbol,
            ownerType: flowRawType,
            name: "collectLatest",
            externalLinkName: "__kk_flow_collectLatest",
            returnType: types.unitType,
            parameters: [(name: "collector", type: flowCollectorType)],
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )

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

        if !cancellationIsSourceBacked {
            registerSyntheticPlatformExceptionConstructors(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol,
                noArgLinkName: "__kk_cancellation_exception_new",
                messageLinkName: "__kk_cancellation_exception_new_message",
                messageCauseLinkName: "__kk_cancellation_exception_new_message_cause"
            )
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol,
                args: [],
                nullability: .nullable
            )))
            registerSyntheticPlatformExceptionConstructor(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                parameters: [("cause", nullableThrowableType)],
                externalLinkName: "__kk_cancellation_exception_new_cause",
                symbols: symbols,
                interner: interner
            )
        }

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
        // STDLIB-CORO-001: launch(start: CoroutineStart, block:) overload.
        registerSyntheticCoroutineTopLevelFunction(
            named: "launch",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "start", type: coroutineStartType),
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
        // STDLIB-CORO-001: CoroutineStart enum and launch(start:, block:) overload.
        // rewriteLauncherCall disambiguates the 2-arg launch overloads by the
        // first argument's type: CoroutineDispatcher goes to the dispatcher-
        // aware runtime, CoroutineStart goes to the lazy-start runtime.
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
        let startCoroutineName = interner.intern("startCoroutineUninterceptedOrReturn")
        let startCoroutineReceiverTypeParameterName = interner.intern("R")
        let startCoroutineReceiverTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: startCoroutineReceiverTypeParameterName,
            fqName: kotlinCoroutinesIntrinsicsPkg + [startCoroutineName, interner.intern("$synthetic"), startCoroutineReceiverTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let startCoroutineReceiverTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: startCoroutineReceiverTypeParameterSymbol,
            nullability: .nonNull
        )))
        let startCoroutineTypeParameterName = interner.intern("T")
        let startCoroutineTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: startCoroutineTypeParameterName,
            fqName: kotlinCoroutinesIntrinsicsPkg + [startCoroutineName, interner.intern("$synthetic"), startCoroutineTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let startCoroutineTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: startCoroutineTypeParameterSymbol,
            nullability: .nonNull
        )))
        let startCoroutineContinuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(startCoroutineTypeParameterType)],
            nullability: .nonNull
        )))
        let startCoroutineNoReceiverFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: startCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let startCoroutineWithReceiverFunctionType = types.make(.functionType(FunctionType(
            receiver: startCoroutineReceiverTypeParameterType,
            params: [],
            returnType: startCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let publicStartCoroutineName = interner.intern("startCoroutine")
        let publicStartCoroutineReceiverTypeParameterName = interner.intern("R")
        let publicStartCoroutineReceiverTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: publicStartCoroutineReceiverTypeParameterName,
            fqName: kotlinCoroutinesPkg + [publicStartCoroutineName, interner.intern("$synthetic"), publicStartCoroutineReceiverTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let publicStartCoroutineReceiverTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: publicStartCoroutineReceiverTypeParameterSymbol,
            nullability: .nonNull
        )))
        let publicStartCoroutineTypeParameterName = interner.intern("T")
        let publicStartCoroutineTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: publicStartCoroutineTypeParameterName,
            fqName: kotlinCoroutinesPkg + [publicStartCoroutineName, interner.intern("$synthetic"), publicStartCoroutineTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let publicStartCoroutineTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: publicStartCoroutineTypeParameterSymbol,
            nullability: .nonNull
        )))
        let publicStartCoroutineContinuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(publicStartCoroutineTypeParameterType)],
            nullability: .nonNull
        )))
        let publicStartCoroutineNoReceiverFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: publicStartCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let publicStartCoroutineWithReceiverFunctionType = types.make(.functionType(FunctionType(
            receiver: publicStartCoroutineReceiverTypeParameterType,
            params: [],
            returnType: publicStartCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let publicCreateCoroutineName = interner.intern("createCoroutine")
        let publicCreateCoroutineReceiverTypeParameterName = interner.intern("R")
        let publicCreateCoroutineReceiverTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: publicCreateCoroutineReceiverTypeParameterName,
            fqName: kotlinCoroutinesPkg + [publicCreateCoroutineName, interner.intern("$synthetic"), publicCreateCoroutineReceiverTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let publicCreateCoroutineReceiverTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: publicCreateCoroutineReceiverTypeParameterSymbol,
            nullability: .nonNull
        )))
        let publicCreateCoroutineTypeParameterName = interner.intern("T")
        let publicCreateCoroutineTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: publicCreateCoroutineTypeParameterName,
            fqName: kotlinCoroutinesPkg + [publicCreateCoroutineName, interner.intern("$synthetic"), publicCreateCoroutineTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let publicCreateCoroutineTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: publicCreateCoroutineTypeParameterSymbol,
            nullability: .nonNull
        )))
        let publicCreateCoroutineContinuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(publicCreateCoroutineTypeParameterType)],
            nullability: .nonNull
        )))
        let publicCreateCoroutineNoReceiverFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: publicCreateCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        let publicCreateCoroutineWithReceiverFunctionType = types.make(.functionType(FunctionType(
            receiver: publicCreateCoroutineReceiverTypeParameterType,
            params: [],
            returnType: publicCreateCoroutineTypeParameterType,
            isSuspend: true,
            nullability: .nonNull
        )))
        registerSyntheticCoroutineExtensionFunction(
            named: "createCoroutine",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: publicCreateCoroutineNoReceiverFunctionType,
            parameters: [(name: "completion", type: publicCreateCoroutineContinuationType)],
            returnType: invariantContinuationOfUnitType,
            typeParameterSymbols: [publicCreateCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "createCoroutine",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: publicCreateCoroutineWithReceiverFunctionType,
            parameters: [
                (name: "receiver", type: publicCreateCoroutineReceiverTypeParameterType),
                (name: "completion", type: publicCreateCoroutineContinuationType),
            ],
            returnType: invariantContinuationOfUnitType,
            typeParameterSymbols: [
                publicCreateCoroutineReceiverTypeParameterSymbol,
                publicCreateCoroutineTypeParameterSymbol,
            ],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "startCoroutine",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: publicStartCoroutineNoReceiverFunctionType,
            parameters: [(name: "completion", type: publicStartCoroutineContinuationType)],
            returnType: types.unitType,
            typeParameterSymbols: [publicStartCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "startCoroutine",
            packageFQName: kotlinCoroutinesPkg,
            receiverType: publicStartCoroutineWithReceiverFunctionType,
            parameters: [
                (name: "receiver", type: publicStartCoroutineReceiverTypeParameterType),
                (name: "completion", type: publicStartCoroutineContinuationType),
            ],
            returnType: types.unitType,
            typeParameterSymbols: [
                publicStartCoroutineReceiverTypeParameterSymbol,
                publicStartCoroutineTypeParameterSymbol,
            ],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "startCoroutineUninterceptedOrReturn",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            receiverType: startCoroutineNoReceiverFunctionType,
            parameters: [(name: "completion", type: startCoroutineContinuationType)],
            returnType: types.nullableAnyType,
            flags: [.synthetic, .inlineFunction],
            typeParameterSymbols: [startCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineExtensionFunction(
            named: "startCoroutineUninterceptedOrReturn",
            packageFQName: kotlinCoroutinesIntrinsicsPkg,
            receiverType: startCoroutineWithReceiverFunctionType,
            parameters: [
                (name: "receiver", type: startCoroutineReceiverTypeParameterType),
                (name: "completion", type: startCoroutineContinuationType),
            ],
            returnType: types.nullableAnyType,
            flags: [.synthetic, .inlineFunction],
            typeParameterSymbols: [startCoroutineReceiverTypeParameterSymbol, startCoroutineTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
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
        // KSP-679: `coroutineScope` / `supervisorScope` are now real suspend
        // functions in bundled Kotlin (Stdlib/kotlinx/coroutines/
        // CoroutineScope.kt), delegating to the residual (c) scope primitives.
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
            named: "ensureActive",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_ensure_active",
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
        // withContext accepts any CoroutineContext (e.g. NonCancellable, not just a
        // dispatcher), matching kotlinx.coroutines' actual signature. `ensureInterfaceSymbol`
        // is idempotent, so calling it here ahead of the "STDLIB-CORO-077" block below (which
        // defines the canonical `coroutineContextSymbol`/`coroutineContextType` local bindings)
        // just returns the same already-registered symbol -- this only widens the accepted
        // argument type; CoroutineDispatcher already has CoroutineContext as a supertype (see
        // below), so existing `withContext(Dispatchers.IO) { }`-style calls are unaffected.
        let withContextContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let withContextContextType = types.make(.classType(ClassType(
            classSymbol: withContextContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: withContextContextType),
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
        types.setNominalDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)
        symbols.setDirectSupertypes([coroutineContextElementSymbol], for: jobSymbol)
        types.setNominalDirectSupertypes([coroutineContextElementSymbol], for: jobSymbol)

        // `kotlinx.coroutines.isActive`: an extension on CoroutineContext (not just
        // CoroutineScope/Job) so `currentCoroutineContext().isActive` resolves.
        // Mirrors `this[Job]?.isActive ?: true` -- a context with no Job element is
        // considered active.
        registerSyntheticObjectProperty(
            ownerSymbol: coroutineContextSymbol,
            ownerType: coroutineContextType,
            name: "isActive",
            propertyType: types.booleanType,
            externalLinkName: "kk_context_is_active",
            symbols: symbols,
            interner: interner
        )

        // `kotlinx.coroutines.NonCancellable`: a CoroutineContext.Element used with
        // `withContext(NonCancellable) { ... }` to run cleanup code that ignores the
        // enclosing job's cancellation. Referenced bare (not via member access), so it
        // resolves through the object-with-externalLinkName path in ExprLowerer.
        let nonCancellableSymbol = ensureSyntheticObjectSymbol(
            named: "NonCancellable",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let nonCancellableType = types.make(.classType(ClassType(
            classSymbol: nonCancellableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nonCancellableType, for: nonCancellableSymbol)
        symbols.setDirectSupertypes([coroutineContextElementSymbol], for: nonCancellableSymbol)
        types.setNominalDirectSupertypes([coroutineContextElementSymbol], for: nonCancellableSymbol)
        symbols.setExternalLinkName("kk_non_cancellable_instance", for: nonCancellableSymbol)

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

        // CoroutineContext.Element.getPolymorphicElement(key: Key<E>): E?
        do {
            let functionName = interner.intern("getPolymorphicElement")
            let functionFQName = kotlinCoroutinesPkg + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
                    symbols.setParentSymbol(packageSymbol, for: functionSymbol)
                }
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
                        receiverType: coroutineContextElementType,
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
                attachCoroutineExperimentalStdlibApiAnnotation(to: functionSymbol, symbols: symbols)
            }
        }

        // CoroutineContext.Element.minusPolymorphicKey(key: Key<*>): CoroutineContext
        do {
            let functionName = interner.intern("minusPolymorphicKey")
            let functionFQName = kotlinCoroutinesPkg + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
                    symbols.setParentSymbol(packageSymbol, for: functionSymbol)
                }
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
                        receiverType: coroutineContextElementType,
                        parameterTypes: [keyType],
                        returnType: coroutineContextType,
                        valueParameterSymbols: [keyParamSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_minusKey", for: functionSymbol)
                attachCoroutineExperimentalStdlibApiAnnotation(to: functionSymbol, symbols: symbols)
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
        // KSP-674: flowOf / emptyFlow / Iterable.asFlow are now Kotlin source
        // (Stdlib/kotlinx/coroutines/flow/Builders.kt), composed from the
        // retained `flow { }` (kk_flow_create) + `emit` (kk_flow_emit) core.

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

        // KSP-678: the `Channel()` / `Channel(capacity)` factories are now
        // provided by bundled Kotlin source
        // (Sources/CompilerCore/Stdlib/kotlin/coroutines/channels/Channels.kt),
        // which bridges to the residual kk_channel_create runtime entry point via
        // @KsSymbolName. No synthetic constructor or factory bridges are
        // registered here.

        // STDLIB-CORO-078: `ReceiveChannel<T>` is the read-only view of `Channel<T>`
        // that `produce { }` returns in real kotlinx.coroutines. Registered as a
        // type alias (rather than a separate interface) so send/receive/close/
        // isClosedForReceive/for-loop iteration resolve through the same Channel
        // member lookup instead of duplicating it for a second symbol.
        let receiveChannelName = interner.intern("ReceiveChannel")
        let receiveChannelFQName = channelsPkg + [receiveChannelName]
        if symbols.lookup(fqName: receiveChannelFQName) == nil {
            let receiveChannelAliasSymbol = symbols.define(
                kind: .typeAlias,
                name: receiveChannelName,
                fqName: receiveChannelFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            let receiveChannelTypeParamName = interner.intern("T")
            let receiveChannelTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: receiveChannelTypeParamName,
                fqName: receiveChannelFQName + [receiveChannelTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setTypeAliasTypeParameters([receiveChannelTypeParamSymbol], for: receiveChannelAliasSymbol)
            let receiveChannelTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: receiveChannelTypeParamSymbol,
                nullability: .nonNull
            )))
            let receiveChannelUnderlyingType = types.make(.classType(ClassType(
                classSymbol: channelSymbol,
                args: [.invariant(receiveChannelTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setTypeAliasUnderlyingType(receiveChannelUnderlyingType, for: receiveChannelAliasSymbol)
        }

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

        // STDLIB-CORO-BUG-04: bare `isActive` reference (no explicit
        // CoroutineScope receiver) inside a coroutine builder body, e.g.
        // `launch { if (isActive) { ... } }`.
        registerSyntheticCoroutineTopLevelProperty(
            named: "isActive",
            packageFQName: coroutinesPkg,
            returnType: types.booleanType,
            externalLinkName: "kk_coroutine_current_is_active",
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

        // `kotlinx.coroutines.Job()` / `SupervisorJob()`: bare factory functions sharing
        // their name with the `Job` interface (the same "nominal type + eponymous
        // factory-style function" pattern already used for e.g. `Channel(...)`).
        registerSyntheticCoroutineTopLevelFunction(
            named: "Job",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: jobType,
            externalLinkName: "kk_job_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "SupervisorJob",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: jobType,
            externalLinkName: "kk_supervisor_job_new",
            symbols: symbols,
            interner: interner
        )

        // `kotlinx.coroutines.CoroutineScope`: an interface (real Kotlin declares
        // `val coroutineContext: CoroutineContext` as its only member) plus the
        // eponymous `CoroutineScope(context): CoroutineScope` factory function.
        let coroutineScopeSymbol = ensureInterfaceSymbol(
            named: "CoroutineScope",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineScopeType = types.make(.classType(ClassType(
            classSymbol: coroutineScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineScopeType, for: coroutineScopeSymbol)
        registerSyntheticCoroutineTopLevelFunction(
            named: "CoroutineScope",
            packageFQName: coroutinesPkg,
            parameters: [(name: "context", type: coroutineContextType)],
            returnType: coroutineScopeType,
            externalLinkName: "kk_coroutine_scope_new_with_context",
            symbols: symbols,
            interner: interner
        )
        // `CoroutineScope.launch { block }`: a receiver-bearing member call. The general
        // member-call emission path (appendReceiverToMemberArguments in
        // CallLowerer+MemberCallEmission.swift) already prepends the receiver as
        // arguments[0] whenever the chosen callee's FunctionSignature.receiverType is
        // set, so this call reaches CoroutineLoweringPass as a 2-argument call
        // [receiverExpr, blockRef] -- the same shape as the dispatcher-aware top-level
        // `launch(dispatcher) { }`. CoroutineLoweringPass+LauncherSupport.swift's
        // rewriteLauncherCall special-cases this externalLinkName up front and routes
        // it through rewriteCoroutineScopeLaunchCall, which threads the receiver through
        // to a dedicated `kk_coroutine_scope_launch(scopeHandle, entryPointRaw,
        // functionID)` runtime entry point.
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineScopeSymbol,
            ownerType: coroutineScopeType,
            name: "launch",
            externalLinkName: "kk_coroutine_scope_launch",
            returnType: jobType,
            parameters: [(
                name: "block",
                type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.unitType,
                    isSuspend: true,
                    nullability: .nonNull
                )))
            )],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineScopeSymbol,
            ownerType: coroutineScopeType,
            name: "cancel",
            externalLinkName: "kk_coroutine_scope_cancel",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: coroutineScopeSymbol,
            ownerType: coroutineScopeType,
            name: "isActive",
            propertyType: types.booleanType,
            externalLinkName: "kk_coroutine_scope_is_active",
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
        // KSP-676: StateFlow / MutableStateFlow and Flow.stateIn are bundled
        // Kotlin source (StateFlow.kt), so no synthetic constructor or member
        // stubs are registered here.
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
        // KSP-678: Channel.close / isClosedForSend / isClosedForReceive are now
        // provided by bundled Kotlin source
        // (Sources/CompilerCore/Stdlib/kotlin/coroutines/channels/Channels.kt),
        // which bridges to the residual kk_channel_close /
        // kk_channel_is_closed_for_send / kk_channel_is_closed_for_receive
        // runtime entry points via @KsSymbolName. No synthetic stubs are
        // registered for them here.

        let emptyCoroutineContextSymbol = ensureSyntheticObjectSymbol(
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
        let syncPkg = ensureSyntheticCoroutinePackage(
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

        // Mutex() factory is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_create bridge.

        // Mutex.lock() suspend
        registerSyntheticCoroutineMember(
            ownerSymbol: mutexSymbol,
            ownerType: mutexType,
            name: "lock",
            externalLinkName: "kk_mutex_lock",
            returnType: types.unitType,
            isSuspend: true,
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

        // Mutex.tryLock is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_tryLock bridge.

        // Mutex.isLocked is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_isLocked bridge.

        // Mutex.withLock is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) as a suspend
        // extension that composes lock()/unlock(); no synthetic stub remains.

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

        // Semaphore(permits) factory is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_create bridge.

        // Semaphore.acquire() suspend
        registerSyntheticCoroutineMember(
            ownerSymbol: semaphoreSymbol,
            ownerType: semaphoreType,
            name: "acquire",
            externalLinkName: "kk_semaphore_acquire",
            returnType: types.unitType,
            isSuspend: true,
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

        // Semaphore.tryAcquire is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_tryAcquire bridge.

        // Semaphore.availablePermits is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_availablePermits bridge.

        // Semaphore.withPermit is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) as a suspend
        // extension that composes acquire()/release(); no synthetic stub remains.

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

}
/// `registerSyntheticCoroutineCancellationStubs` and the private
/// helpers used by the synthetic Coroutine stub registration
/// (top-level functions, extension functions, members, constructors,
/// channel factory bridges, intrinsics stubs, annotation attachment).
///
/// Consolidated here with the coroutine package registry for RF-STUB-005.
extension DataFlowSemaPhase {
    // STDLIB-CORO-BUG-04: this used to also register a `Job.cancel()`
    // extension function under kotlin.coroutines.cancellation, duplicating
    // the member declared in registerSyntheticCoroutineStubs (same receiver,
    // arity, and external link name) and making `job.cancel()` ambiguous.
    // Removed; kept as a no-op since the SyntheticStubRegistryEntry bucket
    // table references this function by name.
    func registerSyntheticCoroutineCancellationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {}

    func registerSyntheticCoroutineTopLevelFunction(
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

    func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        flags: SymbolFlags = [.synthetic],
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
            flags: flags
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

    func registerSyntheticCoroutineTopLevelFunction(
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
        valueParameterFQNameSuffixes: [String]? = nil,
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
        for (index, parameter) in parameters.enumerated() {
            let paramNameID = interner.intern(parameter.name)
            let paramFQNameSuffix = if let valueParameterFQNameSuffixes,
                                       valueParameterFQNameSuffixes.indices.contains(index) {
                interner.intern(valueParameterFQNameSuffixes[index])
            } else {
                paramNameID
            }
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramFQNameSuffix],
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

    func registerSyntheticCoroutineTopLevelProperty(
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

    func registerSyntheticCoroutineExtensionFunction(
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

    func registerSyntheticCoroutineMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String? = nil,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        isSuspend: Bool = false,
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
                isSuspend: isSuspend,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    func registerSyntheticCoroutineExtensionFunction(
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

    func registerSyntheticCoroutineConstructor(
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

    func registerSyntheticObjectProperty(
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


    func ensureSyntheticCoroutinePackage(
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
        let kotlinCoroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let intrinsicsPkg = ensureSyntheticCoroutinePackage(
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

    func attachRestrictsSuspensionAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.CLASS"]
        )
        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )
        let sinceKotlinRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.SinceKotlin",
            arguments: ["1.3"]
        )
        var annotations = symbols.annotations(for: symbol)
        for record in [targetRecord, retentionRecord, sinceKotlinRecord] where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    func attachCoroutineExperimentalStdlibApiAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi")
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
// jscpd:ignore-end
