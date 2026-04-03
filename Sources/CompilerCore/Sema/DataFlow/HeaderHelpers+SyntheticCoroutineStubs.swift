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

        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
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
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: coroutinesPkg,
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
        let rootCancellationType = types.make(.classType(ClassType(
            classSymbol: rootCancellationSymbol,
            args: [],
            nullability: .nonNull
        )))

        symbols.setPropertyType(jobType, for: jobSymbol)
        symbols.setPropertyType(deferredType, for: deferredSymbol)
        symbols.setPropertyType(dispatchersType, for: dispatchersSymbol)
        symbols.setPropertyType(flowRawType, for: flowInterfaceSymbol)
        symbols.setPropertyType(dispatcherType, for: dispatcherSymbol)
        symbols.setPropertyType(channelType, for: channelSymbol)
        symbols.setPropertyType(cancellationType, for: cancellationSymbol)
        symbols.setPropertyType(rootCancellationType, for: rootCancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: rootCancellationSymbol)

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

        // STDLIB-CORO-077: CoroutineContext, CoroutineName, CoroutineExceptionHandler
        let coroutineContextSymbol = ensureClassSymbol(
            named: "CoroutineContext",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineContextType = types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextType, for: coroutineContextSymbol)

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

        // Make CoroutineDispatcher a subtype of CoroutineContext
        symbols.setDirectSupertypes([coroutineContextSymbol], for: dispatcherSymbol)

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
                params: [coroutineContextType, types.anyType],
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
                params: [coroutineContextType, types.anyType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            symbols: symbols,
            interner: interner
        )

        // withContext overload accepting CoroutineContext (not just dispatcher)
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: coroutineContextType),
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

        // CoroutineContext.plus(other: CoroutineContext): CoroutineContext
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineContextSymbol,
            ownerType: coroutineContextType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: coroutineContextType,
            parameters: [(name: "context", type: coroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: dispatcherSymbol,
            ownerType: dispatcherType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: coroutineContextType,
            parameters: [(name: "context", type: coroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineNameSymbol,
            ownerType: coroutineNameType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: coroutineContextType,
            parameters: [(name: "context", type: coroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: coroutineExceptionHandlerSymbol,
            ownerType: coroutineExceptionHandlerType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: coroutineContextType,
            parameters: [(name: "context", type: coroutineContextType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "plus",
            externalLinkName: "kk_context_plus",
            returnType: coroutineContextType,
            parameters: [(name: "context", type: coroutineContextType)],
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
            name: "join",
            externalLinkName: "kk_job_join",
            returnType: types.unitType,
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

    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticCoroutineTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        syntheticTypeParameterNames: [String] = [],
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
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        var typeParameterSymbols: [SymbolID] = []
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
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
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
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
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
        let functionFQName = packageFQName + [functionName]
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
}
