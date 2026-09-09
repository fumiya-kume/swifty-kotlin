
/// Synthetic stdlib stubs for `kotlin.native.concurrent` (STDLIB-NATIVE-CONCURRENT-002).
///
/// Registers:
///   - KSP-1216 package-level nominal anchors whose constructors and members are owned by follow-up tasks
///   - `Continuation0` / `Continuation1` / `Continuation2` classes
///   - `callContinuation0` / `callContinuation1` / `callContinuation2` extensions
///   - `FreezingException` class with native constructor surface
///   - `InvalidMutabilityException` class with native constructor surface
///   - `Worker` class with `execute`, `requestTermination`, `isTerminated`, `name` members
///   - `Future<T>` value class with `result`, `consume`, `getState` members and the `FutureState` anchor
///   - `@ObsoleteWorkersApi` marker annotation
///   - `TransferMode` nominal anchor for the early `Worker.execute` registration
///   - `@ThreadLocal` annotation (PROPERTY/CLASS target, native variant)

private enum NativeConcurrentRegistrationStep: CaseIterable {
    case topLevelNominalAnchors
    case continuationTypes
    case callContinuationFunctions
    case freezingException
    case invalidMutabilityException
    case worker
    case future
    case markerAnnotations
}

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

        // TransferMode is source-backed. Keep only the early nominal anchor
        // because Worker.execute is registered before bundled headers are collected.
        let transferModeSymbol = ensureNativeConcurrentEnum(
            named: "TransferMode",
            entries: [],
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
        // FutureState is source-backed. Keep only its early nominal anchor here
        // because Future.getState is registered before bundled headers are collected.
        let futureStateSymbol = ensureNativeConcurrentEnum(
            named: "FutureState",
            entries: [],
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
        for step in NativeConcurrentRegistrationStep.allCases {
            registerNativeConcurrentStep(
                step,
                packageFQName: nativeConcurrentPkg,
                pkgSymbol: nativeConcurrentPkgSymbol,
                transferModeType: transferModeType,
                futureStateType: futureStateType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
        registerNativeThreadLocalAnnotationConstructor(
            packageFQName: nativeConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}


extension DataFlowSemaPhase {
    private func registerNativeConcurrentStep(
        _ step: NativeConcurrentRegistrationStep,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        futureStateType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        switch step {
        case .topLevelNominalAnchors:
            registerNativeConcurrentTopLevelNominalAnchors(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .continuationTypes:
            registerNativeConcurrentContinuationTypes(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .callContinuationFunctions:
            registerNativeConcurrentCallContinuationFunctions(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .freezingException:
            registerNativeConcurrentFreezingException(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .invalidMutabilityException:
            registerNativeConcurrentInvalidMutabilityException(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .worker:
            registerNativeConcurrentWorker(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                transferModeType: transferModeType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .future:
            registerNativeConcurrentFuture(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                futureStateType: futureStateType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .markerAnnotations:
            registerNativeConcurrentMarkerAnnotations(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    /// Registers only the package-level class identity required by KSP-1216.
    /// Constructors and receiver members remain owned by KSP-1219 onward.
    private func registerNativeConcurrentTopLevelNominalAnchors(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for (name, replacement) in [
            ("AtomicInt", "kotlin.concurrent.atomics.AtomicInt"),
            ("AtomicLong", "kotlin.concurrent.atomics.AtomicLong"),
            ("AtomicNativePtr", "kotlin.concurrent.atomics.AtomicNativePtr"),
        ] {
            registerNativeConcurrentNominalAnchor(
                named: name,
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                annotations: [
                    nativeConcurrentDeprecatedErrorAnnotation(
                        message: "Use \(replacement) instead.",
                        replaceWith: replacement
                    ),
                ],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        for name in ["AtomicReference", "FreezableAtomicReference"] {
            registerNativeConcurrentNominalAnchor(
                named: name,
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                typeParameter: (name: "T", variance: .invariant, upperBound: types.nullableAnyType),
                annotations: [
                    nativeConcurrentDeprecatedErrorAnnotation(
                        message: "Use kotlin.concurrent.atomics.AtomicReference instead.",
                        replaceWith: "kotlin.concurrent.atomics.AtomicReference"
                    ),
                ],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        registerNativeConcurrentNominalAnchor(
            named: "DetachedObjectGraph",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            typeParameter: (name: "T", variance: .invariant, upperBound: types.nullableAnyType),
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use the pointed value directly. To pass the value through the C interop, use the StableRef class.\"",
                    ]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.DeprecatedSinceKotlin",
                    arguments: ["errorSince = \"2.1\""]
                ),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentNominalAnchor(
            named: "MutableData",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.internal.NoReorderFields"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use any regular collection instead.\"",
                    ]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.DeprecatedSinceKotlin",
                    arguments: ["errorSince = \"2.1\""]
                ),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentNominalAnchor(
            named: "WorkerBoundReference",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            typeParameter: (name: "T", variance: .out, upperBound: types.anyType),
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use the referenced value directly.\"",
                    ]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.DeprecatedSinceKotlin",
                    arguments: ["errorSince = \"2.1\""]
                ),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )

        // NativePtr is the opaque representation used by two internal KSP-1216
        // functions. Its own members remain outside this API slice.
        let nativeInternalPkg = ensurePackage(
            path: ["kotlin", "native", "internal"],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentNominalAnchor(
            named: "NativePtr",
            packageFQName: nativeInternalPkg,
            pkgSymbol: symbols.lookup(fqName: nativeInternalPkg),
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentNominalAnchor(
        named name: String,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        typeParameter: (name: String, variance: TypeVariance, upperBound: TypeID)? = nil,
        annotations: [MetadataAnnotationRecord] = [],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class
        {
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

        let classType: TypeID
        if let typeParameter {
            let typeParameterName = interner.intern(typeParameter.name)
            let typeParameterFQName = classFQName + [typeParameterName]
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
            symbols.setParentSymbol(classSymbol, for: typeParameterSymbol)
            symbols.setTypeParameterUpperBounds([typeParameter.upperBound], for: typeParameterSymbol)
            types.setNominalTypeParameterSymbols([typeParameterSymbol], for: classSymbol)
            types.setNominalTypeParameterVariances([typeParameter.variance], for: classSymbol)
            let typeParameterType = types.make(.typeParam(TypeParamType(
                symbol: typeParameterSymbol,
                nullability: .nonNull
            )))
            classType = types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
        } else {
            classType = types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: [],
                nullability: .nonNull
            )))
        }
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(annotations, to: classSymbol, symbols: symbols)
    }

    private func registerNativeConcurrentMarkerAnnotations(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let obsoleteWorkersApiSymbol = ensureAnnotationClassSymbol(
            named: "ObsoleteWorkersApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: obsoleteWorkersApiSymbol)
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
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                MetadataAnnotationRecord(annotationFQName: "kotlin.annotation.MustBeDocumented"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.SinceKotlin",
                    arguments: ["version = \"1.9\""]
                ),
            ],
            to: obsoleteWorkersApiSymbol,
            symbols: symbols
        )

        let obsoleteWorkersApiType = types.make(.classType(ClassType(
            classSymbol: obsoleteWorkersApiSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerNativeConcurrentConstructor(
            ownerSymbol: obsoleteWorkersApiSymbol,
            ownerType: obsoleteWorkersApiType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )

        let threadLocalNativeAnnotationSymbol = ensureAnnotationClassSymbol(
            named: "ThreadLocal",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: threadLocalNativeAnnotationSymbol)
        }
        appendNativeConcurrentAnnotationMetadata(
            to: threadLocalNativeAnnotationSymbol,
            targets: ["AnnotationTarget.PROPERTY", "AnnotationTarget.CLASS"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Continuation0/1/2 classes and callContinuation0/1/2 extension functions.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Continuation0 / Continuation1 / Continuation2

    func registerNativeConcurrentContinuationTypes(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableCOpaquePointerType = types.makeNullable(nativeConcurrentCOpaquePointerType(
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

    func registerNativeConcurrentCallContinuationFunctions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = nativeConcurrentCOpaquePointerType(
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
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: FreezingException and InvalidMutabilityException classes.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - FreezingException

    func registerNativeConcurrentFreezingException(
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
        // The exact constructor is owned by the bundled Kotlin declaration and
        // its runtime bridge. Keep only this nominal anchor for source reuse.
    }

    // MARK: - InvalidMutabilityException

    func registerNativeConcurrentInvalidMutabilityException(
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
            externalLinkName: "__kk_invalid_mutability_exception_new_message",
            parameters: [(name: "message", type: types.stringType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Worker class with Companion.start, member functions, and properties.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Worker

    func registerNativeConcurrentWorker(
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
        symbols.insertFlags(.valueType, for: workerSymbol)
        symbols.setValueClassUnderlyingType(types.intType, for: workerSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi")],
            to: workerSymbol,
            symbols: symbols
        )
        registerNativeConcurrentWorkerConstructor(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            symbols: symbols,
            types: types,
            interner: interner
        )

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
        symbols.setCompanionObjectSymbol(companionSymbol, for: workerSymbol)
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

        // Worker.execute(mode: TransferMode, producer: () -> T1, job: (T1) -> T2): Future<T2>
        let executeName = interner.intern("execute")
        let executeFQName = workerFQName + [executeName]
        let executeT1Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T1",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT2Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T2",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT1Type = types.make(.typeParam(TypeParamType(
            symbol: executeT1Symbol,
            nullability: .nonNull
        )))
        let executeT2Type = types.make(.typeParam(TypeParamType(
            symbol: executeT2Symbol,
            nullability: .nonNull
        )))
        let executeProducerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: executeT1Type
        )))
        let executeJobType = types.make(.functionType(FunctionType(
            params: [executeT1Type],
            returnType: executeT2Type
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "execute",
            externalLinkName: "kk_worker_execute",
            returnType: nativeConcurrentFutureType(
                elementType: executeT2Type,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: executeProducerType),
                (name: "job", type: executeJobType),
            ],
            defaultValues: [false, false, false],
            typeParameterSymbols: [executeT1Symbol, executeT2Symbol],
            symbols: symbols,
            interner: interner
        )

        // Worker.requestTermination(processScheduled: Boolean = true): Future<Boolean>
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "requestTermination",
            externalLinkName: "kk_worker_request_termination",
            returnType: nativeConcurrentFutureType(
                elementType: types.booleanType,
                symbols: symbols,
                types: types,
                interner: interner
            ),
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

    private func registerNativeConcurrentWorkerConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = [types.intType]
        guard symbols.lookupAll(fqName: constructorFQName).first(where: { id in
            guard symbols.symbol(id)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }) == nil else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .internal,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let idName = interner.intern("id")
        let idSymbol = symbols.define(
            kind: .valueParameter,
            name: idName,
            fqName: constructorFQName + [idName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: idSymbol)
        symbols.setPropertyType(types.intType, for: idSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: [idSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.PublishedApi")],
            to: constructorSymbol,
            symbols: symbols
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: `<T>.freeze()` and
/// `Any?.isFrozen` legacy-memory-manager surfaces.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - freeze / isFrozen

    func registerNativeConcurrentFreezeAndIsFrozen(
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

        let getterAccessorName = interner.intern("$get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterAccessorName,
            fqName: propertyFQName + [getterAccessorName],
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
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Future<T> value class with result, consume, getState members.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Future<T>

    func registerNativeConcurrentFuture(
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

        // Future is a value class over the runtime handle. Its constructor must
        // preserve the supplied Int instead of allocating a separate object.
        symbols.insertFlags(.valueType, for: futureSymbol)
        symbols.setValueClassUnderlyingType(types.intType, for: futureSymbol)

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

        // The runtime creates handles with kk_future_new(); this constructor
        // wraps an existing handle and therefore has no runtime link.
        registerNativeConcurrentConstructor(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            visibility: .internal,
            annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.PublishedApi")],
            parameters: [(name: "id", type: types.intType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

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
}
