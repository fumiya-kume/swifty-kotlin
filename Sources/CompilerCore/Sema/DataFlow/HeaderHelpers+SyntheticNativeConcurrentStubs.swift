import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent` (STDLIB-NATIVE-CONCURRENT-002).
///
/// Registers:
///   - `Continuation0` / `Continuation1` / `Continuation2` classes
///   - `callContinuation0` / `callContinuation1` / `callContinuation2` extensions
///   - `DetachedObjectGraph<T>` class with constructors, `asCPointer`, and `attach`
///   - `FreezingException` class with native constructor surface
///   - `InvalidMutabilityException` class with native constructor surface
///   - `WorkerBoundReference<T>` class with constructor and read-only properties
///   - `atomicLazy` top-level function
///   - `ensureNeverFrozen` top-level extension
///   - `freeze` top-level extension and `isFrozen` extension property
///   - `waitForMultipleFutures` top-level and collection-extension functions
///   - `waitWorkerTermination(worker)` top-level function
///   - `withWorker(name, errorReporting, block)` top-level function
///   - `Worker` class with `execute`, `requestTermination`, `isTerminated`, `name` members
///   - `Future<T>` class with `result`, `consume`, `getState` members and `FutureState` enum
///   - `AtomicInt`, `AtomicLong`, and `AtomicNativePtr` legacy classes
///   - `FreezableAtomicReference<T>`
///   - `MutableData`
///   - `@ObsoleteWorkersApi` marker annotation
///   - `AtomicReference<T>` (legacy alias in `kotlin.native.concurrent`)
///   - `TransferMode` enum with `SAFE` and `UNSAFE` entries
///   - `@SharedImmutable` annotation (PROPERTY target)
///   - `@ThreadLocal` annotation (PROPERTY/CLASS target, native variant)
extension DataFlowSemaPhase {
    func registerSyntheticNativeConcurrentStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativeConcurrentPkg = ensurePackage(
            path: ["kotlin", "native", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let nativeConcurrentPkgSymbol = symbols.lookup(fqName: nativeConcurrentPkg)

        // TransferMode enum
        let transferModeSymbol = ensureNativeConcurrentEnum(
            named: "TransferMode",
            entries: ["SAFE", "UNSAFE"],
            in: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let transferModeType = types.make(.classType(ClassType(
            classSymbol: transferModeSymbol,
            args: [],
            nullability: .nonNull
        )))
        setNativeConcurrentEnumEntryTypes(
            enumSymbol: transferModeSymbol,
            enumType: transferModeType,
            symbols: symbols
        )

        // FutureState enum
        let futureStateSymbol = ensureNativeConcurrentEnum(
            named: "FutureState",
            entries: ["SCHEDULED", "COMPUTED", "THROWN", "CANCELLED"],
            in: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let futureStateType = types.make(.classType(ClassType(
            classSymbol: futureStateSymbol,
            args: [],
            nullability: .nonNull
        )))
        setNativeConcurrentEnumEntryTypes(
            enumSymbol: futureStateSymbol,
            enumType: futureStateType,
            symbols: symbols
        )

        // Continuation0/1/2 classes
        registerNativeConcurrentContinuationTypes(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // COpaquePointer.callContinuation0/1/2()
        registerNativeConcurrentCallContinuationFunctions(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // DetachedObjectGraph<T> class and attach extension
        registerNativeConcurrentDetachedObjectGraph(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            transferModeType: transferModeType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // FreezingException class
        registerNativeConcurrentFreezingException(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // InvalidMutabilityException class
        registerNativeConcurrentInvalidMutabilityException(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Worker class
        registerNativeConcurrentWorker(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            transferModeType: transferModeType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // WorkerBoundReference<T> class
        registerNativeConcurrentWorkerBoundReference(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // atomicLazy(initializer: () -> T): Lazy<T>
        registerNativeConcurrentAtomicLazy(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Any.ensureNeverFrozen(): Unit
        registerNativeConcurrentEnsureNeverFrozen(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // T.freeze(): T and Any?.isFrozen
        registerNativeConcurrentFreezeAndIsFrozen(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Future<T> class
        registerNativeConcurrentFuture(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            futureStateType: futureStateType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // waitForMultipleFutures(futures, timeoutMillis) and collection extension
        registerNativeConcurrentWaitForMultipleFutures(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // waitWorkerTermination(worker)
        registerNativeConcurrentWaitWorkerTermination(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // withWorker(name, errorReporting, block)
        registerNativeConcurrentWithWorker(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // AtomicInt / AtomicLong / AtomicNativePtr legacy classes
        registerNativeConcurrentLegacyAtomicScalars(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // FreezableAtomicReference<T>
        registerNativeConcurrentFreezableAtomicReference(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // MutableData
        registerNativeConcurrentMutableData(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // AtomicReference<T> (legacy alias, re-registered under kotlin.native.concurrent)
        registerNativeConcurrentAtomicReference(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // @ObsoleteWorkersApi marker annotation
        let obsoleteWorkersApiSymbol = ensureAnnotationClassSymbol(
            named: "ObsoleteWorkersApi",
            in: nativeConcurrentPkg,
            symbols: symbols,
            interner: interner
        )
        if let nativeConcurrentPkgSymbol {
            symbols.setParentSymbol(nativeConcurrentPkgSymbol, for: obsoleteWorkersApiSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.RequiresOptIn",
                    arguments: [
                        "message = \"Workers API is obsolete and will be replaced with threads eventually\"",
                        "level = RequiresOptIn.Level.WARNING",
                    ]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.ANNOTATION_CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
            ],
            to: obsoleteWorkersApiSymbol,
            symbols: symbols
        )

        // @SharedImmutable annotation
        let sharedImmutableSymbol = ensureAnnotationClassSymbol(
            named: "SharedImmutable",
            in: nativeConcurrentPkg,
            symbols: symbols,
            interner: interner
        )
        if let nativeConcurrentPkgSymbol {
            symbols.setParentSymbol(nativeConcurrentPkgSymbol, for: sharedImmutableSymbol)
        }
        appendNativeConcurrentAnnotationMetadata(
            to: sharedImmutableSymbol,
            targets: ["AnnotationTarget.PROPERTY"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )

        // @ThreadLocal annotation (Kotlin/Native variant, distinct from java.lang.ThreadLocal)
        let threadLocalNativeAnnotationSymbol = ensureAnnotationClassSymbol(
            named: "ThreadLocal",
            in: nativeConcurrentPkg,
            symbols: symbols,
            interner: interner
        )
        if let nativeConcurrentPkgSymbol {
            symbols.setParentSymbol(nativeConcurrentPkgSymbol, for: threadLocalNativeAnnotationSymbol)
        }
        appendNativeConcurrentAnnotationMetadata(
            to: threadLocalNativeAnnotationSymbol,
            targets: ["AnnotationTarget.PROPERTY", "AnnotationTarget.CLASS"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
    }

    // MARK: - Continuation0 / Continuation1 / Continuation2

    private func registerNativeConcurrentContinuationTypes(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableCOpaquePointerType = types.makeNullable(nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "COpaquePointer",
            symbols: symbols,
            types: types,
            interner: interner
        ))
        let invokerCallbackType = types.make(.functionType(FunctionType(
            params: [nullableCOpaquePointerType],
            returnType: types.unitType
        )))
        let cFunctionType = nativeConcurrentCFunctionType(
            functionType: invokerCallbackType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let invokerType = nativeConcurrentCPointerType(
            pointeeType: cFunctionType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentContinuationType(
            name: "Continuation0",
            typeParameterNames: [],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation1",
            typeParameterNames: ["T1"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation2",
            typeParameterNames: ["T1", "T2"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentContinuationType(
        name: String,
        typeParameterNames: [String],
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        invokerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let continuationName = interner.intern(name)
        let continuationFQName = packageFQName + [continuationName]
        let continuationSymbol: SymbolID
        if let existing = symbols.lookup(fqName: continuationFQName), symbols.symbol(existing)?.kind == .class {
            continuationSymbol = existing
        } else {
            continuationSymbol = symbols.define(
                kind: .class,
                name: continuationName,
                fqName: continuationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: continuationSymbol)
        }

        let typeParameterSymbols = typeParameterNames.map { typeParameterName in
            let internedName = interner.intern(typeParameterName)
            let fqName = continuationFQName + [internedName]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(continuationSymbol, for: symbol)
            return symbol
        }
        let typeParameterTypes = typeParameterSymbols.map { symbol in
            types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
        }
        let continuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: typeParameterTypes.map { .invariant($0) },
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: continuationSymbol)
        types.setNominalTypeParameterVariances(
            Array(repeating: .invariant, count: typeParameterSymbols.count),
            for: continuationSymbol
        )
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: continuationSymbol,
            symbols: symbols
        )

        let blockType = types.make(.functionType(FunctionType(
            params: typeParameterTypes,
            returnType: types.unitType
        )))
        registerNativeConcurrentContinuationFunctionSupertype(
            ownerSymbol: continuationSymbol,
            functionArity: typeParameterTypes.count,
            functionArgumentTypes: typeParameterTypes,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            parameters: [
                (name: "block", type: blockType),
                (name: "invoker", type: invokerType),
                (name: "singleShot", type: types.booleanType),
            ],
            defaultValues: [false, false, true],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "dispose",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "invoke",
            returnType: types.unitType,
            parameters: typeParameterTypes.enumerated().map { index, type in
                (name: "p\(index + 1)", type: type)
            },
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            flags: [.synthetic, .operatorFunction, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNativeConcurrentCallContinuationFunctions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "COpaquePointer",
            symbols: symbols,
            types: types,
            interner: interner
        )

        for arity in 0...2 {
            registerNativeConcurrentCallContinuationFunction(
                arity: arity,
                packageFQName: packageFQName,
                receiverType: receiverType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func registerNativeConcurrentCallContinuationFunction(
        arity: Int,
        packageFQName: [InternedString],
        receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("callContinuation\(arity)")
        let functionFQName = packageFQName + [functionName]
        let typeParameterSymbols: [SymbolID] = arity == 0 ? [] : (1...arity).map { index in
            let typeParameterName = interner.intern("T\(index)")
            let typeParameterFQName = functionFQName + [typeParameterName]
            if let existing = symbols.lookup(fqName: typeParameterFQName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            return symbol
        }

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) == nil else {
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
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: functionSymbol,
            symbols: symbols
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    // MARK: - DetachedObjectGraph<T>

    private func registerNativeConcurrentDetachedObjectGraph(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let graphName = interner.intern("DetachedObjectGraph")
        let graphFQName = packageFQName + [graphName]

        let graphSymbol: SymbolID
        if let existing = symbols.lookup(fqName: graphFQName), symbols.symbol(existing)?.kind == .class {
            graphSymbol = existing
        } else {
            graphSymbol = symbols.define(
                kind: .class,
                name: graphName,
                fqName: graphFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: graphSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = graphFQName + [typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let graphType = types.make(.classType(ClassType(
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: graphSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: graphSymbol)
        symbols.setPropertyType(graphType, for: graphSymbol)

        let cOpaquePointerType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "COpaquePointer",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)
        let producerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))

        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: producerType),
            ],
            defaultValues: [true, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [(name: "pointer", type: nullableCOpaquePointerType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            name: "asCPointer",
            returnType: nullableCOpaquePointerType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAttachExtension(
            packageFQName: packageFQName,
            graphSymbol: graphSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAttachExtension(
        packageFQName: [InternedString],
        graphSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("attach")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == typeParamType
        }) == nil else {
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    // MARK: - FreezingException

    private func registerNativeConcurrentFreezingException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("FreezingException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [
                (name: "toFreeze", type: types.anyType),
                (name: "blocker", type: types.anyType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - InvalidMutabilityException

    private func registerNativeConcurrentInvalidMutabilityException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("InvalidMutabilityException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [(name: "message", type: types.stringType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Worker

    private func registerNativeConcurrentWorker(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerName = interner.intern("Worker")
        let workerFQName = packageFQName + [workerName]

        let workerSymbol: SymbolID
        if let existing = symbols.lookup(fqName: workerFQName), symbols.symbol(existing)?.kind == .class {
            workerSymbol = existing
        } else {
            workerSymbol = symbols.define(
                kind: .class,
                name: workerName,
                fqName: workerFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: workerSymbol)
        }
        let workerType = types.make(.classType(ClassType(
            classSymbol: workerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(workerType, for: workerSymbol)

        // Worker companion: start(name: String? = null): Worker
        let companionName = interner.intern("Companion")
        let companionFQName = workerFQName + [companionName]
        let companionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: companionFQName) {
            companionSymbol = existing
        } else {
            companionSymbol = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(workerSymbol, for: companionSymbol)
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)

        // Worker.Companion.start(name: String? = null): Worker
        registerNativeConcurrentMemberFunction(
            ownerSymbol: companionSymbol,
            ownerType: companionType,
            name: "start",
            externalLinkName: "kk_worker_new",
            returnType: workerType,
            parameters: [(name: "name", type: types.makeNullable(types.stringType))],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.execute(mode: TransferMode, producer: () -> T): Future<T>
        // Since Future<T> is registered later (no type param yet), register a simpler version
        // returning Any for now (the full generic version requires Future to exist first).
        // We register the execute signature with the intType placeholder in tests.
        // Instead, omit the full generic execute and register the simpler transfer-mode-free version.

        // Worker.requestTermination(processScheduled: Boolean = true): Future<Boolean>
        // Simplified: returns unitType (we do not have Future yet here)
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "requestTermination",
            externalLinkName: "kk_worker_request_termination",
            returnType: types.unitType,
            parameters: [(name: "processScheduled", type: types.booleanType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.isTerminated: Boolean (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "isTerminated",
            propertyType: types.booleanType,
            getterLinkName: "kk_worker_is_terminated",
            symbols: symbols,
            interner: interner
        )

        // Worker.name: String (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "name",
            propertyType: types.stringType,
            getterLinkName: "kk_worker_name",
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - WorkerBoundReference<T>

    private func registerNativeConcurrentWorkerBoundReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let referenceName = interner.intern("WorkerBoundReference")
        let referenceFQName = packageFQName + [referenceName]
        let referenceSymbol: SymbolID
        if let existing = symbols.lookup(fqName: referenceFQName), symbols.symbol(existing)?.kind == .class {
            referenceSymbol = existing
        } else {
            referenceSymbol = symbols.define(
                kind: .class,
                name: referenceName,
                fqName: referenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: referenceSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = referenceFQName + [typeParamName]
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
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let referenceType = types.make(.classType(ClassType(
            classSymbol: referenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: referenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: referenceSymbol)
        symbols.setPropertyType(referenceType, for: referenceSymbol)

        registerNativeConcurrentConstructor(
            ownerSymbol: referenceSymbol,
            ownerType: referenceType,
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "value",
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "valueOrNull",
            propertyType: types.makeNullable(typeParamType),
            symbols: symbols,
            interner: interner
        )

        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "worker",
            propertyType: workerType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - atomicLazy

    private func registerNativeConcurrentAtomicLazy(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("atomicLazy")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
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
                flags: [.synthetic]
            )
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let initializerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))
        let lazyType = nativeConcurrentLazyType(
            elementType: typeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.parameterTypes == [initializerType]
                && signature.returnType == lazyType
        }) == nil else {
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

        let initializerName = interner.intern("initializer")
        let initializerSymbol = symbols.define(
            kind: .valueParameter,
            name: initializerName,
            fqName: functionFQName + [initializerName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: initializerSymbol)
        symbols.setPropertyType(initializerType, for: initializerSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [initializerType],
                returnType: lazyType,
                isSuspend: false,
                valueParameterSymbols: [initializerSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    // MARK: - ensureNeverFrozen

    private func registerNativeConcurrentEnsureNeverFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("ensureNeverFrozen")
        let functionFQName = packageFQName + [functionName]
        let receiverType = types.anyType

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .throwingFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                canThrow: true,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    // MARK: - freeze / isFrozen

    private func registerNativeConcurrentFreezeAndIsFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let freezeName = interner.intern("freeze")
        let freezeFQName = packageFQName + [freezeName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = freezeFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))

        registerNativeConcurrentPackageFunction(
            named: "freeze",
            packageFQName: packageFQName,
            receiverType: typeParameterType,
            returnType: typeParameterType,
            parameters: [],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Usages of this function can be safely dropped.",
                    replaceWith: "this"
                ),
            ],
            externalLinkName: "kk_freeze_object",
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentPackageExtensionProperty(
            named: "isFrozen",
            packageFQName: packageFQName,
            receiverType: types.nullableAnyType,
            returnType: types.booleanType,
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Consequently, this property is always `false`.",
                    replaceWith: "false"
                ),
            ],
            externalLinkName: "kk_is_frozen",
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Future<T>

    private func registerNativeConcurrentFuture(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        futureStateType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let futureName = interner.intern("Future")
        let futureFQName = packageFQName + [futureName]

        let futureSymbol: SymbolID
        if let existing = symbols.lookup(fqName: futureFQName), symbols.symbol(existing)?.kind == .class {
            futureSymbol = existing
        } else {
            futureSymbol = symbols.define(
                kind: .class,
                name: futureName,
                fqName: futureFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: futureSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = futureFQName + [typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let futureType = types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: futureSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: futureSymbol)
        symbols.setPropertyType(futureType, for: futureSymbol)

        // Future.result: T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: futureSymbol,
            name: "result",
            propertyType: typeParamType,
            getterLinkName: "kk_future_result",
            symbols: symbols,
            interner: interner
        )

        // Future.consume(): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "consume",
            externalLinkName: "kk_future_consume",
            returnType: typeParamType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // Future.getState(): FutureState
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "getState",
            externalLinkName: "kk_future_getState",
            returnType: futureStateType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - waitForMultipleFutures

    private func registerNativeConcurrentWaitForMultipleFutures(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("waitForMultipleFutures")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let futureType = nativeConcurrentFutureType(
            elementType: typeParameterType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futuresCollectionType = nativeConcurrentCollectionType(
            named: "Collection",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futureSetType = nativeConcurrentCollectionType(
            named: "Set",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: futureSetType,
            parameters: [
                (name: "futures", type: futuresCollectionType),
                (name: "timeoutMillis", type: types.intType),
            ],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: futuresCollectionType,
            returnType: futureSetType,
            parameters: [(name: "millis", type: types.intType)],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use 'waitForMultipleFutures' top-level function instead\"",
                        "replaceWith = \"waitForMultipleFutures(this, millis)\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - waitWorkerTermination

    private func registerNativeConcurrentWaitWorkerTermination(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitWorkerTermination",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: types.unitType,
            parameters: [(name: "worker", type: workerType)],
            typeParameterSymbols: [],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - withWorker

    private func registerNativeConcurrentWithWorker(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("withWorker")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("R")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let blockType = types.make(.functionType(FunctionType(
            receiver: workerType,
            params: [],
            returnType: typeParameterType
        )))

        registerNativeConcurrentPackageFunction(
            named: "withWorker",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: typeParameterType,
            parameters: [
                (name: "name", type: types.makeNullable(types.stringType)),
                (name: "errorReporting", type: types.booleanType),
                (name: "block", type: blockType),
            ],
            defaultValues: [true, true, false],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - AtomicInt / AtomicLong / AtomicNativePtr

    private func registerNativeConcurrentLegacyAtomicScalars(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentLegacyAtomicInt(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicLong(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicNativePtr(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicInt(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicInt",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.intType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicInt",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.intType,
            addAndGetParameterTypes: [types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicLong(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicLong",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.longType,
            constructorDefault: true,
            replacement: "kotlin.concurrent.atomics.AtomicLong",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.longType,
            addAndGetParameterTypes: [types.intType, types.longType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicNativePtr(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePtrType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "NativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicNativePtr",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: nativePtrType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicNativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: nativePtrType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: nativePtrType,
            parameters: [(name: "newValue", type: nativePtrType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicClass(
        named name: String,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        valueType: TypeID,
        constructorDefault: Bool,
        replacement: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> ClassType {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull)
        let ownerType = types.make(.classType(classType))
        symbols.setPropertyType(ownerType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use \(replacement) instead.",
                    replaceWith: replacement
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            parameters: [(name: "value", type: valueType)],
            defaultValues: [constructorDefault],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: valueType,
            symbols: symbols,
            interner: interner
        )
        return classType
    }

    private func registerNativeConcurrentAtomicNumericMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        addAndGetParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: valueType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: valueType,
            parameters: [(name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for parameterType in addAndGetParameterTypes {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: "addAndGet",
                returnType: valueType,
                parameters: [(name: "delta", type: parameterType)],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndAdd",
            returnType: valueType,
            parameters: [(name: "delta", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for name in ["getAndIncrement", "getAndDecrement", "incrementAndGet", "decrementAndGet"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: valueType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        for name in ["increment", "decrement"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: types.unitType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAtomicCoreMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: returnType,
            parameters: parameters,
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNativeConcurrentToStringMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "toString",
            returnType: types.stringType,
            parameters: [],
            defaultValues: [],
            flags: [.synthetic, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - MutableData

    private func registerNativeConcurrentMutableData(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("MutableData")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use any regular collection instead.\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        let byteArrayType = nativeConcurrentClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cOpaquePointerType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "COpaquePointer",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [(name: "capacity", type: types.intType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: classSymbol,
            name: "size",
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [(name: "data", type: classType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: nullableCOpaquePointerType),
                (name: "count", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: byteArrayType),
                (name: "fromIndex", type: types.intType),
                (name: "toIndex", type: types.intType),
            ],
            defaultValues: [false, true, true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "copyInto",
            returnType: types.unitType,
            parameters: [
                (name: "output", type: byteArrayType),
                (name: "destinationIndex", type: types.intType),
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            defaultValues: [false, false, false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "get",
            returnType: types.intType,
            parameters: [(name: "index", type: types.intType)],
            defaultValues: [false],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "reset",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withBufferLocked",
            blockParameterTypes: [byteArrayType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withPointerLocked",
            blockParameterTypes: [cOpaquePointerType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentMutableDataLockedMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        ownerFQName: [InternedString],
        name: String,
        blockParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let typeParameterSymbol = nativeConcurrentSyntheticTypeParameter(
            named: "R",
            ownerFQName: ownerFQName + [interner.intern(name)],
            symbols: symbols,
            interner: interner
        )
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: blockParameterTypes,
            returnType: typeParameterType
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: typeParameterType,
            parameters: [(name: "block", type: blockType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - FreezableAtomicReference<T>

    private func registerNativeConcurrentFreezableAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("FreezableAtomicReference")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
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
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use kotlin.concurrent.atomics.AtomicReference instead.",
                    replaceWith: "kotlin.concurrent.atomics.AtomicReference"
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            externalLinkName: "kk_freezable_atomic_ref_create",
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_freezable_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSet",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSwap",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - AtomicReference<T> (legacy kotlin.native.concurrent)

    private func registerNativeConcurrentAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicRefName = interner.intern("AtomicReference")
        let atomicRefFQName = packageFQName + [atomicRefName]

        let atomicRefSymbol: SymbolID
        if let existing = symbols.lookup(fqName: atomicRefFQName), symbols.symbol(existing)?.kind == .class {
            atomicRefSymbol = existing
        } else {
            atomicRefSymbol = symbols.define(
                kind: .class,
                name: atomicRefName,
                fqName: atomicRefFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: atomicRefSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = atomicRefFQName + [typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // constructor(value: T): AtomicReference<T>
        let initName = interner.intern("<init>")
        let initFQName = atomicRefFQName + [initName]
        if symbols.lookupAll(fqName: initFQName).isEmpty {
            let initSymbol = symbols.define(
                kind: .function,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(atomicRefSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_native_atomic_ref_create", for: initSymbol)
            let paramName = interner.intern("value")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: initFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: paramSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [typeParamType],
                    returnType: atomicRefType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        // value property: var T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: atomicRefSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_native_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        // compareAndSwap(expected: T, new: T): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSwap",
            externalLinkName: "kk_native_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndSet(expected: T, new: T): Boolean
        let boolType = types.make(.primitive(.boolean, .nonNull))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSet",
            externalLinkName: "kk_native_atomic_ref_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    private func ensureNativeConcurrentEnum(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol {
                symbols.setParentSymbol(pkgSymbol, for: enumSymbol)
            }
        }
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil { continue }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }
        return enumSymbol
    }

    private func setNativeConcurrentEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else { continue }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func registerNativeConcurrentMemberFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String? = nil,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) && sig.returnType == returnType
        }) == nil else { return }

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
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: memberFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            symbols.setPropertyType(parameter.type, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        let defaults = defaultValues.isEmpty
            ? Array(repeating: false, count: parameters.count)
            : defaultValues
        let varargs = Array(repeating: false, count: parameters.count)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaults,
                valueParameterIsVararg: varargs,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    private func registerNativeConcurrentConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String? = nil,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        guard symbols.lookupAll(fqName: constructorFQName).first(where: { id in
            guard symbols.symbol(id)?.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.parameterTypes == parameterTypes
        }) == nil else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
        }

        let valueParameterSymbols = parameters.map { parameter in
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: constructorFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: paramSymbol)
            symbols.setPropertyType(parameter.type, for: paramSymbol)
            return paramSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameterTypes,
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues,
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: constructorSymbol
        )
    }

    private func nativeConcurrentClassType(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let classSymbol = nativeConcurrentClassSymbol(
            packagePath: packagePath,
            name: name,
            symbols: symbols,
            interner: interner
        )
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        if symbols.propertyType(for: classSymbol) == nil {
            symbols.setPropertyType(classType, for: classSymbol)
        }
        return classType
    }

    private func nativeConcurrentClassSymbol(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let packageFQName = ensurePackage(
            path: packagePath,
            symbols: symbols,
            interner: interner
        )
        let packageSymbol = symbols.lookup(fqName: packageFQName)
        let classSymbol = ensureClassSymbol(
            named: name,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        return classSymbol
    }

    private func nativeConcurrentSyntheticTypeParameter(
        named name: String,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeParamName = interner.intern(name)
        let typeParamFQName = ownerFQName + [typeParamName]
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    private func nativeConcurrentFutureType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let futureSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Future",
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func nativeConcurrentCollectionType(
        named name: String,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let collectionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin", "collections"],
            name: name,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func nativeConcurrentCPointerType(
        pointeeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cPointerSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlinx", "cinterop"],
            name: "CPointer",
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointeeType)],
            nullability: .nonNull
        )))
    }

    private func nativeConcurrentCFunctionType(
        functionType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        let cinteropPkgSymbol = symbols.lookup(fqName: cinteropPkg)
        let cFunctionSymbol = ensureClassSymbol(
            named: "CFunction",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: cFunctionSymbol)
        }

        let typeParameterName = interner.intern("T")
        let typeParameterFQName = cinteropPkg + [interner.intern("CFunction"), typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(cFunctionSymbol, for: typeParameterSymbol)
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        types.setNominalTypeParameterSymbols([typeParameterSymbol], for: cFunctionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: cFunctionSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let cFunctionDeclarationType = types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cFunctionDeclarationType, for: cFunctionSymbol)

        let cPointedSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlinx", "cinterop"],
            name: "CPointed",
            symbols: symbols,
            interner: interner
        )
        if !symbols.directSupertypes(for: cFunctionSymbol).contains(cPointedSymbol) {
            symbols.setDirectSupertypes(
                symbols.directSupertypes(for: cFunctionSymbol) + [cPointedSymbol],
                for: cFunctionSymbol
            )
        }
        if !types.directNominalSupertypes(for: cFunctionSymbol).contains(cPointedSymbol) {
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: cFunctionSymbol) + [cPointedSymbol],
                for: cFunctionSymbol
            )
        }

        return types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(functionType)],
            nullability: .nonNull
        )))
    }

    private func registerNativeConcurrentContinuationFunctionSupertype(
        ownerSymbol: SymbolID,
        functionArity: Int,
        functionArgumentTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionSymbol = nativeConcurrentFunctionInterfaceSymbol(
            arity: functionArity,
            symbols: symbols,
            interner: interner
        )
        if !symbols.directSupertypes(for: ownerSymbol).contains(functionSymbol) {
            symbols.setDirectSupertypes(
                symbols.directSupertypes(for: ownerSymbol) + [functionSymbol],
                for: ownerSymbol
            )
        }
        if !types.directNominalSupertypes(for: ownerSymbol).contains(functionSymbol) {
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: ownerSymbol) + [functionSymbol],
                for: ownerSymbol
            )
        }

        let supertypeArgs: [TypeArg] = [.out(types.unitType)]
            + functionArgumentTypes.map { .in($0) }
        symbols.setSupertypeTypeArgs(supertypeArgs, for: ownerSymbol, supertype: functionSymbol)
        types.setNominalSupertypeTypeArgs(supertypeArgs, for: ownerSymbol, supertype: functionSymbol)
    }

    private func nativeConcurrentFunctionInterfaceSymbol(
        arity: Int,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let functionPkg = ensurePackage(
            path: ["kotlin", "Function"],
            symbols: symbols,
            interner: interner
        )
        let functionPkgSymbol = symbols.lookup(fqName: functionPkg)
        let functionSymbol = ensureInterfaceSymbol(
            named: "Function\(arity)",
            in: functionPkg,
            symbols: symbols,
            interner: interner
        )
        if let functionPkgSymbol {
            symbols.setParentSymbol(functionPkgSymbol, for: functionSymbol)
        }
        return functionSymbol
    }

    private func registerNativeConcurrentPackageFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID?,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool]? = nil,
        typeParameterSymbols: [SymbolID],
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) {
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            appendNativeConcurrentMetadataAnnotations(annotations, to: existing, symbols: symbols)
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

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(annotations, to: functionSymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues
                    ?? Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func registerNativeConcurrentPackageExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: id) == receiverType
        }) {
            symbols.setPropertyType(returnType, for: existing)
            appendNativeConcurrentMetadataAnnotations(annotations, to: existing, symbols: symbols)
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
                if let externalLinkName {
                    symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
                }
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
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        appendNativeConcurrentMetadataAnnotations(annotations, to: propertySymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }

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
                returnType: returnType
            ),
            for: getterSymbol
        )
        appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
        }
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
    }

    private func nativeConcurrentLazyType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let lazySymbol = ensureInterfaceSymbol(
            named: "Lazy",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: lazySymbol)
        }
        let lazyTypeParamName = interner.intern("T")
        let lazyTypeParamFQName = kotlinPkg + [interner.intern("Lazy"), lazyTypeParamName]
        let lazyTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: lazyTypeParamFQName) {
            lazyTypeParamSymbol = existing
        } else {
            lazyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: lazyTypeParamName,
                fqName: lazyTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(lazySymbol, for: lazyTypeParamSymbol)
        }
        types.setNominalTypeParameterSymbols([lazyTypeParamSymbol], for: lazySymbol)
        types.setNominalTypeParameterVariances([.out], for: lazySymbol)
        return types.make(.classType(ClassType(
            classSymbol: lazySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func appendNativeConcurrentMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in records where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    private func nativeConcurrentDeprecatedErrorAnnotation(
        message: String,
        replaceWith: String
    ) -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: [
                "message = \"\(message)\"",
                "replaceWith = ReplaceWith(\"\(replaceWith)\")",
                "level = DeprecationLevel.ERROR",
            ]
        )
    }

    private func registerNativeConcurrentReadOnlyProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        getterLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propName = interner.intern(name)
        let propFQName = ownerInfo.fqName + [propName]
        if symbols.lookup(fqName: propFQName) != nil { return }

        let propSymbol = symbols.define(
            kind: .property,
            name: propName,
            fqName: propFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propSymbol)
        symbols.setPropertyType(propertyType, for: propSymbol)
        if let getterLinkName {
            symbols.setExternalLinkName(getterLinkName, for: propSymbol)
        }
    }

    private func registerNativeConcurrentMutableProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        getterLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propName = interner.intern(name)
        let propFQName = ownerInfo.fqName + [propName]
        if let existing = symbols.lookup(fqName: propFQName) {
            symbols.insertFlags([.synthetic, .mutable], for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            if let getterLinkName {
                symbols.setExternalLinkName(getterLinkName, for: existing)
            }
            return
        }

        let propSymbol = symbols.define(
            kind: .property,
            name: propName,
            fqName: propFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .mutable]
        )
        symbols.setParentSymbol(ownerSymbol, for: propSymbol)
        symbols.setPropertyType(propertyType, for: propSymbol)
        if let getterLinkName {
            symbols.setExternalLinkName(getterLinkName, for: propSymbol)
        }
    }

    private func appendNativeConcurrentAnnotationMetadata(
        to symbol: SymbolID,
        targets: [String],
        retention: String,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: targets
        )
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }
        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: [retention]
        )
        if !annotations.contains(retentionRecord) {
            annotations.append(retentionRecord)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
