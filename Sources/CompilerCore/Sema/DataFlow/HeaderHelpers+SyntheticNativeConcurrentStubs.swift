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
}
