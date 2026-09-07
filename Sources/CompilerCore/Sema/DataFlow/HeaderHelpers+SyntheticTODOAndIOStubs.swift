import RuntimeABI

/// Synthetic fallback registrations kept in the historical TODO/IO bucket.
/// TODO and console APIs are source-backed; this file now owns only the
/// remaining sequence and Kotlin/Native compatibility surfaces.
extension DataFlowSemaPhase {
    func registerSyntheticTODOAndIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        let kotlinIOPkg = ensureSyntheticPackageHierarchy(fqName: [interner.intern("kotlin"), interner.intern("io")], symbols: symbols)

        // KSP-614: print / println are implemented in Stdlib/kotlin/io/Console.kt.
        // KSP-615: readLine / readln / readlnOrNull are implemented in Stdlib/kotlin/io/Console.kt.

        // --- Sequence factory functions (STDLIB-097) ---
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        _ = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Sequence factory functions are source-backed (KSP-651).
        // STDLIB-331/564: iterator {} builder → Iterator<T>
        // Registered with SequenceScope<T> receiver so yield() resolves inside the lambda.
        registerSyntheticIteratorBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-330: sequence { yield(x) } builder
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticSequenceResidualMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
        )

        // --- kotlin.native.Platform (STDLIB-NATIVE-169) ---
        let kotlinNativePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("native")],
            symbols: symbols
        )
        // KSP-1210: use the bundled declaration when available so enum entry
        // order and generated enum APIs come from the Kotlin source contract.
        let osFamilyFQName = kotlinNativePkg + [interner.intern("OsFamily")]
        let osFamilySymbol = symbols.lookup(fqName: osFamilyFQName)
            ?? ensureSyntheticPlatformEnumClass(
                named: "OsFamily",
                entries: [
                    "UNKNOWN", "MACOSX", "IOS", "LINUX", "WINDOWS",
                    "ANDROID", "WASM", "TVOS", "WATCHOS",
                ],
                in: kotlinNativePkg,
                symbols: symbols,
                interner: interner
            )
        let osFamilyType = types.make(.classType(ClassType(
            classSymbol: osFamilySymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: osFamilySymbol,
            enumType: osFamilyType,
            symbols: symbols
        )

        let cpuArchitectureSymbol = ensureSyntheticPlatformEnumClass(
            named: "CpuArchitecture",
            entries: [
                "UNKNOWN", "X86", "X64", "ARM32",
                "ARM64", "MIPS32", "MIPSEL32", "WASM32",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let cpuArchitectureType = types.make(.classType(ClassType(
            classSymbol: cpuArchitectureSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: cpuArchitectureSymbol,
            enumType: cpuArchitectureType,
            symbols: symbols
        )
        let memoryModelSymbol = ensureSyntheticPlatformEnumClass(
            named: "MemoryModel",
            entries: [
                "STRICT", "RELAXED", "EXPERIMENTAL",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let memoryModelType = types.make(.classType(ClassType(
            classSymbol: memoryModelSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: memoryModelSymbol,
            enumType: memoryModelType,
            symbols: symbols
        )

        // KSP-1211: Platform's public surface is source-backed. The synthetic
        // registration pass runs before bundled headers are collected, so use
        // the declaration index rather than the symbol table to keep the
        // source-backed object and its members authoritative.
        let platformFQName = kotlinNativePkg + [interner.intern("Platform")]
        let hasSourceBackedPlatform = bundledIndex.contains(
            ownerFQName: platformFQName,
            name: interner.intern("canAccessUnaligned"),
            arity: 0
        )
        if !hasSourceBackedPlatform {
            let platformSymbol = ensureSyntheticObjectSymbol(
                named: "Platform",
                in: kotlinNativePkg,
                symbols: symbols,
                interner: interner
            )
            let platformType = types.make(.classType(ClassType(
                classSymbol: platformSymbol,
                args: [],
                nullability: .nonNull
            )))
            let booleanType = types.make(.primitive(.boolean, .nonNull))
            symbols.setPropertyType(platformType, for: platformSymbol)
            registerSyntheticObjectProperty(
                ownerSymbol: platformSymbol,
                name: "canAccessUnaligned",
                propertyType: booleanType,
                externalLinkName: "kk_platform_canAccessUnaligned",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticObjectProperty(
                ownerSymbol: platformSymbol,
                name: "isLittleEndian",
                propertyType: booleanType,
                externalLinkName: "kk_platform_isLittleEndian",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticObjectProperty(
                ownerSymbol: platformSymbol,
                name: "osFamily",
                propertyType: osFamilyType,
                externalLinkName: "kk_platform_osFamily",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticObjectProperty(
                ownerSymbol: platformSymbol,
                name: "cpuArchitecture",
                propertyType: cpuArchitectureType,
                externalLinkName: "kk_platform_cpuArchitecture",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticObjectProperty(
                ownerSymbol: platformSymbol,
                name: "memoryModel",
                propertyType: memoryModelType,
                externalLinkName: "kk_platform_memoryModel",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticSystemMember(
                ownerSymbol: platformSymbol,
                ownerType: platformType,
                name: "getAvailableProcessors",
                externalLinkName: "kk_platform_getAvailableProcessors",
                returnType: types.intType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }

        // KSP-618: kotlin.synchronized is Kotlin source
        // (Stdlib/kotlin/Synchronized.kt) over the demoted __kk_synchronized
        // bridge, so no synthetic stub is registered here.

        registerSyntheticFileIOBootstrap(
            kotlinIOPkg: kotlinIOPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // measureTime / measureTimedValue live in bundled Kotlin source
        // (Stdlib/kotlin/time/MeasureTime.kt).

        // --- STDLIB-HOF-029: 関数型完全実装 ---
        registerSyntheticFunctionTypes(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSequenceScopeMember(
        named name: String,
        sequenceScopeSymbol: SymbolID,
        sequenceScopeFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = sequenceScopeFQName + [memberName]
        let parameterTypes = parameters.map(\.type)
        if symbols.lookupAll(fqName: memberFQName).contains(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameterTypes
        }) {
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
        symbols.setParentSymbol(sequenceScopeSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func registerSequenceMemberStub(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        sequenceSymbol: SymbolID,
        sequenceFQName: [InternedString],
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner,
        annotations: [MetadataAnnotationRecord] = [],
        canThrow: Bool = false,
        typeParameterUpperBounds: [TypeID] = [],
        typeParameterUpperBoundsList: [[TypeID]]? = nil,
        additionalTypeParameterSymbols: [SymbolID] = [],
        additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
        flags: SymbolFlags = [.synthetic, .operatorFunction]
    ) {
        if BundledSyntheticStubRegistration.preBundledPass {
            return
        }

        let memberName = interner.intern(name)
        let memberFQName = sequenceFQName + [memberName]
        let requestedParameterTypes = parameters.map(\.type)
        let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .sequence,
            memberName: name,
            arity: parameters.count,
            fallback: externalLinkName
        )

        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == requestedParameterTypes
                && signature.returnType == returnType
        }) {
            // KSP-441〜447: source Sequence 関数が存在すれば、合成外部リンクで上書きしない。
            if symbols.symbol(existing)?.declSite != nil {
                return
            }
            symbols.setExternalLinkName(resolvedExternalLinkName, for: existing)
            return
        }

        if let types = BundledSyntheticStubRegistration.types,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: sequenceFQName,
               receiverType: receiverType,
               name: memberName,
               arity: parameters.count,
               symbols: symbols,
               types: types,
               interner: interner
           )
        {
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
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: memberSymbol)
        }

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        let allTypeParameterSymbols = [typeParamSymbol] + additionalTypeParameterSymbols
        let reifiedTypeParameterIndices = Set(
            allTypeParameterSymbols.enumerated().compactMap { index, symbolID in
                symbols.symbol(symbolID)?.flags.contains(.reifiedTypeParameter) == true ? index : nil
            }
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: allTypeParameterSymbols,
                reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: (typeParameterUpperBoundsList ?? [typeParameterUpperBounds]) + additionalTypeParameterUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func ensureSyntheticPlatformEnumClass(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
                symbols.setParentSymbol(pkgSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
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

    private func setSyntheticPlatformEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            symbols.setPropertyType(enumType, for: child)
        }
    }

    /// Registers the generated enum APIs for the synthetic Native MemoryModel.
    /// The generic enum lowering pass reuses these symbols when it emits the
    /// values(), entries, and valueOf() bodies for the nominal enum owner.
    func registerSyntheticMemoryModelEnumMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let memoryModelFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("MemoryModel"),
        ]
        guard let enumSymbol = symbols.lookup(fqName: memoryModelFQName),
              let enumInfo = symbols.symbol(enumSymbol)
        else {
            return
        }
        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.experimental.ExperimentalNativeApi"
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"The only possible value returned in runtime is MemoryModel.EXPERIMENTAL now. The usages of this enum can be safely removed.\"",
                ]
            ),
        ]
        var existingAnnotations = symbols.annotations(for: enumSymbol)
        for annotation in annotations where !existingAnnotations.contains(annotation) {
            existingAnnotations.append(annotation)
        }
        symbols.setAnnotations(existingAnnotations, for: enumSymbol)

        let valuesName = interner.intern("values")
        let valuesFQName = enumInfo.fqName + [valuesName]
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        if let arraySymbol = symbols.lookup(fqName: arrayFQName),
           symbols.lookupAll(fqName: valuesFQName).allSatisfy({ symbols.symbol($0)?.kind != .function })
        {
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let valuesSymbol = symbols.define(
                kind: .function,
                name: valuesName,
                fqName: valuesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: valuesSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [],
                    returnType: arrayType,
                    isSuspend: false
                ),
                for: valuesSymbol
            )
        }

        let valueOfName = interner.intern("valueOf")
        let valueOfFQName = enumInfo.fqName + [valueOfName]
        if symbols.lookupAll(fqName: valueOfFQName).allSatisfy({ symbols.symbol($0)?.kind != .function }) {
            let parameterName = interner.intern("value")
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: valueOfFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let valueOfSymbol = symbols.define(
                kind: .function,
                name: valueOfName,
                fqName: valueOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: valueOfSymbol)
            symbols.setParentSymbol(valueOfSymbol, for: parameterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [types.stringType],
                    returnType: enumType,
                    isSuspend: false,
                    valueParameterSymbols: [parameterSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: valueOfSymbol
            )
        }

        let enumEntriesFQName = [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]
        let entriesName = interner.intern("entries")
        let entriesFQName = enumInfo.fqName + [entriesName]
        if let enumEntriesSymbol = symbols.lookup(fqName: enumEntriesFQName),
           symbols.lookupAll(fqName: entriesFQName).allSatisfy({ symbols.symbol($0)?.kind != .property })
        {
            let entriesType = types.make(.classType(ClassType(
                classSymbol: enumEntriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let entriesSymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: entriesSymbol)
            symbols.setPropertyType(entriesType, for: entriesSymbol)
        }
    }

}
