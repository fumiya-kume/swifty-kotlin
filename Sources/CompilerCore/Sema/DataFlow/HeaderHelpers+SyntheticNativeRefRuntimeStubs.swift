import Foundation

/// STDLIB-NATIVE-REF-002: Synthetic sema stubs for `kotlin.native.ref` and
/// `kotlin.native.runtime`.
///
/// Exposes the following symbols at the sema level so that name-resolution,
/// type-checking, and opt-in diagnostics work correctly without any runtime
/// edits:
///
/// - `kotlin.native.ref.WeakReference<T>` — generic weak-reference wrapper.
/// - `kotlin.native.ref.createCleaner` — top-level factory function tagged
///   with `@ExperimentalNativeApi`.
/// - `kotlin.native.runtime.NativeRuntimeApi` — runtime opt-in marker.
/// - `kotlin.native.runtime.GC` — object providing GC controls, tagged with
///   `@NativeRuntimeApi`.
/// - `kotlin.native.runtime.RootSetStatistics` — GC root-set statistics DTO.
/// - `kotlin.native.runtime.SweepStatistics` — GC sweep statistics DTO.
/// - `kotlin.native.runtime.GCInfo` — GC statistics DTO surface.
/// - `kotlin.native.runtime.Debugging` — object exposing debug helpers, tagged
///   with `@NativeRuntimeApi`.
///
/// All symbols are compile-time stubs only.  No runtime code is generated or
/// modified by this registration.
extension DataFlowSemaPhase {
    func registerSyntheticNativeRefRuntimeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativeRefPkg = ensurePackage(
            path: ["kotlin", "native", "ref"],
            symbols: symbols,
            interner: interner
        )
        let nativeRuntimePkg = ensurePackage(
            path: ["kotlin", "native", "runtime"],
            symbols: symbols,
            interner: interner
        )

        let experimentalNativeApiSymbol = lookupOrRegisterExperimentalNativeApiAnnotation(
            symbols: symbols,
            interner: interner
        )
        let nativeRuntimeApiSymbol = registerNativeRuntimeApiAnnotation(
            packageFQName: nativeRuntimePkg,
            symbols: symbols,
            interner: interner
        )

        // Ensure ExperimentalNativeApi is a RequiresOptIn marker so that
        // opt-in diagnostics fire when symbols tagged with it are used.
        ensureExperimentalNativeApiRequiresOptIn(
            markerSymbol: experimentalNativeApiSymbol,
            symbols: symbols
        )

        registerWeakReferenceStub(
            packageFQName: nativeRefPkg,
            experimentalNativeApiSymbol: experimentalNativeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCreateCleanerStub(
            packageFQName: nativeRefPkg,
            experimentalNativeApiSymbol: experimentalNativeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerGCObjectStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerRootSetStatisticsStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSweepStatisticsStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerGCInfoStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerDebuggingObjectStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - WeakReference<T>

    private func registerWeakReferenceStub(
        packageFQName: [InternedString],
        experimentalNativeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("WeakReference")
        let classFQName = packageFQName + [className]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
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

        // Tag WeakReference itself with @ExperimentalNativeApi so that
        // callers must opt in.
        if let experimentalNativeApiSymbol {
            attachExperimentalNativeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(experimentalNativeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // Set up the single type-parameter T (inline, as the NativeInterop
        // helper is private).
        let parameterInternedName = interner.intern("T")
        let typeParameterFQName = classFQName + [parameterInternedName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: parameterInternedName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)

        let tType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: classSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)

        // Register constructor: WeakReference<T>(value: T)
        registerWeakReferenceConstructor(
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: ownerType,
            valueType: tType,
            typeParameterSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // Register get() member: WeakReference<T>.get(): T?
        let nullableTType = types.makeNullable(tType)
        registerSimpleMember(
            named: "get",
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: ownerType,
            parameterTypes: [],
            parameterNames: [],
            returnType: nullableTType,
            externalLinkName: "kk_weak_ref_get",
            symbols: symbols,
            interner: interner
        )

        // Register clear() member: WeakReference<T>.clear(): Unit
        registerSimpleMember(
            named: "clear",
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: ownerType,
            parameterTypes: [],
            parameterNames: [],
            returnType: types.unitType,
            externalLinkName: "kk_weak_ref_clear",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerWeakReferenceConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        valueType: TypeID,
        typeParameterSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let hasMatch = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [valueType]
                && signature.returnType == ownerType
        }
        guard !hasMatch else {
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
        symbols.setExternalLinkName("kk_weak_ref_create", for: ctorSymbol)

        let valueParamName = interner.intern("value")
        let valueParamSymbol = symbols.define(
            kind: .valueParameter,
            name: valueParamName,
            fqName: ctorFQName + [valueParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: valueParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [valueType],
                returnType: ownerType,
                valueParameterSymbols: [valueParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParameterSymbol],
                classTypeParameterCount: 1
            ),
            for: ctorSymbol
        )
    }

    // MARK: - createCleaner

    private func registerCreateCleanerStub(
        packageFQName: [InternedString],
        experimentalNativeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("createCleaner")
        let functionFQName = packageFQName + [functionName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        // Avoid double-registration.
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else {
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
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_cleaner_create", for: functionSymbol)

        // Tag with @ExperimentalNativeApi.
        if let experimentalNativeApiSymbol {
            attachExperimentalNativeApi(
                to: functionSymbol,
                markerFQName: symbols.symbol(experimentalNativeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // createCleaner<T>(value: T, block: (T) -> Unit): Cleaner
        // We use `Any` as a simple approximation for T and the Cleaner return type.
        let anyType = types.anyType
        let blockType = types.make(.functionType(FunctionType(
            params: [anyType],
            returnType: types.unitType
        )))

        let parameterSpecs: [(name: String, type: TypeID)] = [
            ("value", anyType),
            ("block", blockType),
        ]
        var valueParameterSymbols: [SymbolID] = []
        for spec in parameterSpecs {
            let paramName = interner.intern(spec.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterSpecs.map(\.type),
                returnType: anyType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSpecs.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSpecs.count)
            ),
            for: functionSymbol
        )
    }

    // MARK: - GC object

    private func registerGCObjectStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let objectName = interner.intern("GC")
        let objectFQName = packageFQName + [objectName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let objectSymbol: SymbolID
        if let existing = symbols.lookup(fqName: objectFQName) {
            objectSymbol = existing
        } else {
            objectSymbol = symbols.define(
                kind: .object,
                name: objectName,
                fqName: objectFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: objectSymbol)
        }

        let objectType = types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(objectType, for: objectSymbol)

        // Tag with @NativeRuntimeApi.
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: objectSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // GC.collect(): Unit
        registerSimpleMember(
            named: "collect",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            ownerType: objectType,
            parameterTypes: [],
            parameterNames: [],
            returnType: types.unitType,
            externalLinkName: "kk_gc_collect",
            symbols: symbols,
            interner: interner
        )

        // GC.schedule(): Unit
        registerSimpleMember(
            named: "schedule",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            ownerType: objectType,
            parameterTypes: [],
            parameterNames: [],
            returnType: types.unitType,
            externalLinkName: "kk_gc_schedule",
            symbols: symbols,
            interner: interner
        )

        // GC.targetHeapBytes: Long
        registerSimpleProperty(
            named: "targetHeapBytes",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.longType,
            externalLinkName: "kk_gc_target_heap_bytes",
            symbols: symbols,
            interner: interner
        )

        // GC.targetHeapUtilization: Double
        registerSimpleProperty(
            named: "targetHeapUtilization",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.doubleType,
            externalLinkName: "kk_gc_target_heap_utilization",
            symbols: symbols,
            interner: interner
        )

        // GC.maxHeapBytes: Long
        registerSimpleProperty(
            named: "maxHeapBytes",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.longType,
            externalLinkName: "kk_gc_max_heap_bytes",
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - RootSetStatistics class

    private func registerRootSetStatisticsStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureNativeRuntimeClassStub(
            named: "RootSetStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let classFQName = packageFQName + [interner.intern("RootSetStatistics")]
        let classType = nominalType(classSymbol, types: types)
        let properties: [(name: String, type: TypeID)] = [
            ("threadLocalReferences", types.longType),
            ("stackReferences", types.longType),
            ("globalReferences", types.longType),
            ("stableReferences", types.longType),
        ]

        registerSimpleConstructor(
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: classType,
            parameters: properties,
            symbols: symbols,
            interner: interner
        )
        for property in properties {
            registerSimpleProperty(
                named: property.name,
                ownerSymbol: classSymbol,
                ownerFQName: classFQName,
                propertyType: property.type,
                symbols: symbols,
                interner: interner
            )
        }
    }

    // MARK: - SweepStatistics class

    private func registerSweepStatisticsStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureNativeRuntimeClassStub(
            named: "SweepStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let classFQName = packageFQName + [interner.intern("SweepStatistics")]
        let classType = nominalType(classSymbol, types: types)
        let properties: [(name: String, type: TypeID)] = [
            ("sweptCount", types.longType),
            ("keptCount", types.longType),
        ]

        registerSimpleConstructor(
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: classType,
            parameters: properties,
            symbols: symbols,
            interner: interner
        )
        for property in properties {
            registerSimpleProperty(
                named: property.name,
                ownerSymbol: classSymbol,
                ownerFQName: classFQName,
                propertyType: property.type,
                symbols: symbols,
                interner: interner
            )
        }
    }

    // MARK: - GCInfo class

    private func registerGCInfoStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let gcInfoSymbol = ensureNativeRuntimeClassStub(
            named: "GCInfo",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let rootSetStatisticsSymbol = ensureNativeRuntimeClassStub(
            named: "RootSetStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let sweepStatisticsSymbol = ensureNativeRuntimeClassStub(
            named: "SweepStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let memoryUsageSymbol = ensureNativeRuntimeClassStub(
            named: "MemoryUsage",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: gcInfoSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
            attachNativeRuntimeApi(
                to: memoryUsageSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let gcInfoFQName = packageFQName + [interner.intern("GCInfo")]
        let memoryUsageFQName = packageFQName + [interner.intern("MemoryUsage")]
        let gcInfoType = nominalType(gcInfoSymbol, types: types)
        let rootSetStatisticsType = nominalType(rootSetStatisticsSymbol, types: types)
        let sweepStatisticsType = nominalType(sweepStatisticsSymbol, types: types)
        let memoryUsageType = nominalType(memoryUsageSymbol, types: types)
        let nullableLongType = types.makeNullable(types.longType)
        let sweepStatisticsMapType = mapOfStringTo(
            sweepStatisticsType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let memoryUsageMapType = mapOfStringTo(
            memoryUsageType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let gcInfoProperties: [(name: String, type: TypeID)] = [
            ("epoch", types.longType),
            ("startTimeNs", types.longType),
            ("endTimeNs", types.longType),
            ("firstPauseRequestTimeNs", types.longType),
            ("firstPauseStartTimeNs", types.longType),
            ("firstPauseEndTimeNs", types.longType),
            ("secondPauseRequestTimeNs", nullableLongType),
            ("secondPauseStartTimeNs", nullableLongType),
            ("secondPauseEndTimeNs", nullableLongType),
            ("postGcCleanupTimeNs", nullableLongType),
            ("rootSet", rootSetStatisticsType),
            ("markedCount", types.longType),
            ("sweepStatistics", sweepStatisticsMapType),
            ("memoryUsageBefore", memoryUsageMapType),
            ("memoryUsageAfter", memoryUsageMapType),
        ]

        registerSimpleConstructor(
            ownerSymbol: gcInfoSymbol,
            ownerFQName: gcInfoFQName,
            ownerType: gcInfoType,
            parameters: gcInfoProperties,
            symbols: symbols,
            interner: interner
        )
        for property in gcInfoProperties {
            registerSimpleProperty(
                named: property.name,
                ownerSymbol: gcInfoSymbol,
                ownerFQName: gcInfoFQName,
                propertyType: property.type,
                symbols: symbols,
                interner: interner
            )
        }

        let memoryUsageProperties: [(name: String, type: TypeID)] = [
            ("totalObjectsSizeBytes", types.longType),
        ]
        registerSimpleConstructor(
            ownerSymbol: memoryUsageSymbol,
            ownerFQName: memoryUsageFQName,
            ownerType: memoryUsageType,
            parameters: memoryUsageProperties,
            symbols: symbols,
            interner: interner
        )
        for property in memoryUsageProperties {
            registerSimpleProperty(
                named: property.name,
                ownerSymbol: memoryUsageSymbol,
                ownerFQName: memoryUsageFQName,
                propertyType: property.type,
                symbols: symbols,
                interner: interner
            )
        }
    }

    // MARK: - Debugging object

    private func registerDebuggingObjectStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let objectName = interner.intern("Debugging")
        let objectFQName = packageFQName + [objectName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let objectSymbol: SymbolID
        if let existing = symbols.lookup(fqName: objectFQName) {
            objectSymbol = existing
        } else {
            objectSymbol = symbols.define(
                kind: .object,
                name: objectName,
                fqName: objectFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: objectSymbol)
        }

        let objectType = types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(objectType, for: objectSymbol)

        // Tag with @NativeRuntimeApi.
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: objectSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // Debugging.isThreadStateRunnable: Boolean
        registerSimpleProperty(
            named: "isThreadStateRunnable",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.booleanType,
            externalLinkName: "kk_debugging_is_thread_state_runnable",
            symbols: symbols,
            interner: interner
        )

        // Debugging.gcSuspendCount: Int
        registerSimpleProperty(
            named: "gcSuspendCount",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.intType,
            externalLinkName: "kk_debugging_gc_suspend_count",
            symbols: symbols,
            interner: interner
        )

        // Debugging.threadCount: Int
        registerSimpleProperty(
            named: "threadCount",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.intType,
            externalLinkName: "kk_debugging_thread_count",
            symbols: symbols,
            interner: interner
        )

        // Debugging.globalObjectCount: Int
        registerSimpleProperty(
            named: "globalObjectCount",
            ownerSymbol: objectSymbol,
            ownerFQName: objectFQName,
            propertyType: types.intType,
            externalLinkName: "kk_debugging_global_object_count",
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    /// Attaches `@RequiresOptIn` to `ExperimentalNativeApi` so the opt-in
    /// machinery treats it as an opt-in marker.  Safe to call multiple times.
    private func ensureExperimentalNativeApiRequiresOptIn(
        markerSymbol: SymbolID?,
        symbols: SymbolTable
    ) {
        guard let markerSymbol else {
            return
        }
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn"
        )
        var annotations = symbols.annotations(for: markerSymbol)
        guard !annotations.contains(where: { $0.annotationFQName == requiresOptInRecord.annotationFQName }) else {
            return
        }
        annotations.append(requiresOptInRecord)
        symbols.setAnnotations(annotations, for: markerSymbol)
    }

    /// Returns the `kotlin.experimental.ExperimentalNativeApi` annotation
    /// class symbol, looking it up from an earlier registration.
    private func lookupOrRegisterExperimentalNativeApiAnnotation(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "experimental", "ExperimentalNativeApi"]
            .map { interner.intern($0) }
        return symbols.lookup(fqName: fqName)
    }

    private func registerNativeRuntimeApiAnnotation(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "NativeRuntimeApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: annotationSymbol)
        }

        var annotations = symbols.annotations(for: annotationSymbol)
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.ERROR"]
        )
        if !annotations.contains(requiresOptInRecord) {
            annotations.append(requiresOptInRecord)
        }

        let targetRecord = MetadataAnnotationRecord(
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
        )
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }

        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )
        if !annotations.contains(retentionRecord) {
            annotations.append(retentionRecord)
        }
        symbols.setAnnotations(annotations, for: annotationSymbol)
        return annotationSymbol
    }

    /// Attaches a `@ExperimentalNativeApi` annotation record to the given
    /// symbol so that opt-in checks fire when the symbol is used.
    private func attachExperimentalNativeApi(
        to symbol: SymbolID,
        markerFQName: String,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(
            annotationFQName: markerFQName.isEmpty
                ? "kotlin.experimental.ExperimentalNativeApi"
                : markerFQName
        )
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }

    /// Attaches a `@NativeRuntimeApi` annotation record to a runtime symbol.
    private func attachNativeRuntimeApi(
        to symbol: SymbolID,
        markerFQName: String,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(
            annotationFQName: markerFQName.isEmpty
                ? "kotlin.native.runtime.NativeRuntimeApi"
                : markerFQName
        )
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func ensureNativeRuntimeClassStub(
        named name: String,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
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
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }
        symbols.setPropertyType(nominalType(classSymbol, types: types), for: classSymbol)
        return classSymbol
    }

    private func mapOfStringTo(
        _ valueType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let mapFQName = ["kotlin", "collections", "Map"].map { interner.intern($0) }
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(types.stringType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    private func registerSimpleConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let parameterTypes = parameters.map(\.type)
        let existing = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == ownerType
        }
        guard !existing else {
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

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: ctorFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: ctorSymbol
        )
    }

    /// Registers a simple property on `ownerSymbol`.
    private func registerSimpleProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyType: TypeID,
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]

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

    /// Registers a simple member function on `ownerSymbol`.
    private func registerSimpleMember(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        parameterTypes: [TypeID],
        parameterNames: [String],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = ownerFQName + [memberName]

        guard symbols.lookupAll(fqName: memberFQName).first(where: { symID in
            guard let sig = symbols.functionSignature(for: symID) else {
                return false
            }
            return sig.receiverType == ownerType
                && sig.parameterTypes == parameterTypes
                && sig.returnType == returnType
        }) == nil else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for (idx, paramType) in parameterTypes.enumerated() {
            let paramName = interner.intern(idx < parameterNames.count ? parameterNames[idx] : "p\(idx)")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: memberFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
            _ = paramType  // referenced in FunctionSignature below
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }
}
