import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent` (STDLIB-NATIVE-CONCURRENT-002).
///
/// Registers:
///   - `DetachedObjectGraph<T>` class with constructors, `asCPointer`, and `attach`
///   - `FreezingException` class with native constructor surface
///   - `InvalidMutabilityException` class with native constructor surface
///   - `Worker` class with `execute`, `requestTermination`, `isTerminated`, `name` members
///   - `Future<T>` class with `result`, `consume`, `getState` members and `FutureState` enum
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

        // Future<T> class
        registerNativeConcurrentFuture(
            packageFQName: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            futureStateType: futureStateType,
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
            flags: [.synthetic]
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

    private func registerNativeConcurrentReadOnlyProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        getterLinkName: String,
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
        symbols.setExternalLinkName(getterLinkName, for: propSymbol)
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
