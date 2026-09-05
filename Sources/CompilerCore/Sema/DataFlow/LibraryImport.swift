import Foundation

extension DataFlowSemaPhase {
    struct LibraryManifestInfo {
        let metadataPath: String
        let inlineKIRDir: String?
        let moduleName: String?
        let isValid: Bool
    }

    struct LibraryImportDeferredWork {
        let pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])]
        let importedBindings: [ImportedLibraryBinding]
    }

    func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        cache: LibraryMetadataCache? = nil
    ) -> LibraryImportDeferredWork {
        // Imported function bounds may refer to java.io.Closeable before the
        // synthetic FileIO registration phase creates its compatibility anchor.
        _ = ensureJavaIOCloseableCompatibilityAnchor(
            symbols: symbols,
            interner: interner
        )
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.effectiveLibrarySearchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        var importedBindings: [ImportedLibraryBinding] = []
        var stdlibArtifactLoaded = false

        func isStdlibArtifact(_ libraryDir: String) -> Bool {
            guard let stdlibLibraryPath = options.stdlibLibraryPath else { return false }
            return URL(fileURLWithPath: libraryDir).standardizedFileURL.path
                == URL(fileURLWithPath: stdlibLibraryPath).standardizedFileURL.path
        }

        for libraryDir in libraryDirs {
            let stdlibArtifact = isStdlibArtifact(libraryDir)
            let manifestInfo: LibraryManifestInfo
            if let cached = cache?.cachedManifestInfo(libraryDir: libraryDir, target: options.target) {
                manifestInfo = cached
            } else {
                manifestInfo = resolveLibraryManifestInfo(
                    libraryDir: libraryDir,
                    currentTarget: options.target,
                    diagnostics: diagnostics,
                    isStdlibArtifact: stdlibArtifact
                )
                cache?.cacheManifestInfo(manifestInfo, libraryDir: libraryDir, target: options.target)
            }
            if stdlibArtifact {
                stdlibArtifactLoaded = manifestInfo.isValid
            }
            guard manifestInfo.isValid else {
                continue
            }
            let metadataPath = manifestInfo.metadataPath
            let libraryModuleFQN: InternedString? = manifestInfo.moduleName.map { interner.intern($0) }
            let records: [ImportedLibrarySymbolRecord]
            if let cached = cache?.cachedMetadataRecords(metadataPath: metadataPath, interner: interner) {
                records = cached
            } else {
                guard let parsed = parseLibraryMetadata(
                    path: metadataPath,
                    diagnostics: diagnostics,
                    interner: interner
                ) else {
                    continue
                }
                records = parsed
                cache?.cacheMetadataRecords(records, metadataPath: metadataPath, interner: interner)
            }

            for record in records {
                guard !record.fqName.isEmpty else {
                    continue
                }
                let name = record.fqName.last ?? interner.intern("_")
                var flags: SymbolFlags = [.synthetic, .importedLibrary]
                if record.isSuspend, record.kind == .function {
                    flags.insert(.suspendFunction)
                }
                if record.isInline, record.kind == .function {
                    flags.insert(.inlineFunction)
                }
                if record.isOperator, record.kind == .function {
                    flags.insert(.operatorFunction)
                }
                // Overrides must stay marked so member lookup can shadow the
                // supertype declaration instead of reporting an ambiguity.
                if record.isOverride, record.kind == .function {
                    flags.insert(.overrideMember)
                }
                if record.isDataClass {
                    flags.insert(.dataType)
                }
                if record.isOpenClass {
                    flags.insert(.openType)
                }
                switch record.modality {
                case .abstract:
                    flags.insert(.abstractType)
                case .open:
                    flags.insert(.openType)
                case .final:
                    break
                }
                if record.isSealedClass {
                    flags.insert(.sealedType)
                }
                if record.isFunInterface, record.kind == .interface {
                    flags.insert(.funInterface)
                }
                if record.isValueClass {
                    flags.insert(.valueType)
                }
                if record.isFunInterface {
                    flags.insert(.funInterface)
                }
                if record.isExpect {
                    flags.insert(.expectDeclaration)
                }
                if record.isActual {
                    flags.insert(.actualDeclaration)
                }
                if record.isMutable, record.kind == .property || record.kind == .field {
                    flags.insert(.mutable)
                }
                let symbol = symbols.define(
                    kind: record.kind,
                    name: name,
                    fqName: record.fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                if let libraryModuleFQN {
                    symbols.setModuleFQN(libraryModuleFQN, for: symbol)
                }
                importedBindings.append(ImportedLibraryBinding(
                    record: record,
                    symbol: symbol,
                    metadataPath: metadataPath,
                    inlineKIRDir: manifestInfo.inlineKIRDir,
                    isStdlibArtifact: stdlibArtifact
                ))
            }
        }

        if options.stdlibLibraryPath != nil && !stdlibArtifactLoaded {
            diagnostics.error(
                "KSWIFTK-LIB-0020",
                "Stdlib library artifact '\(options.stdlibLibraryPath!)' could not be loaded",
                range: nil
            )
            return LibraryImportDeferredWork(pendingSupertypeEdges: [], importedBindings: [])
        }

        var externalLinkNameToSymbol: [String: SymbolID] = [:]
        var importedSymbolByFQName: [String: SymbolID] = [:]
        for binding in importedBindings {
            if let linkName = binding.record.externalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = binding.symbol
            }
            let fQName = binding.record.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")
            if !fQName.isEmpty {
                importedSymbolByFQName[fQName] = binding.symbol
            }
        }

        for binding in importedBindings {
            applyImportedBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &importedInlineFunctions,
                pendingSupertypeEdges: &pendingSupertypeEdges,
                cache: cache,
                isStdlibArtifact: binding.isStdlibArtifact,
                externalLinkNameToSymbol: externalLinkNameToSymbol,
                importedSymbolByFQName: importedSymbolByFQName
            )
        }

        var syntheticPackagePaths: Set<[InternedString]> = []
        var syntheticPackageModules: [[InternedString]: InternedString] = [:]
        // STDLIB-SHARED-011: Type/value parameters and local symbols belong to a
        // real owner; their FQ name prefixes must not be synthesised as packages.
        let packageOwnerRecordKinds: Set<SymbolKind> = [
            .class, .interface, .object, .enumClass, .annotationClass,
            .typeAlias, .function, .property, .constructor
        ]
        for binding in importedBindings
            where binding.record.kind != .package
            && packageOwnerRecordKinds.contains(binding.record.kind)
        {
            let fq = binding.record.fqName
            let moduleFQN = symbols.moduleFQN(for: binding.symbol)
            for length in 1 ..< fq.count {
                let prefix = Array(fq.prefix(length))
                // Constructors are named below their nominal owner (for
                // example, `pkg.Type.<init>`). Keep that owner path nominal
                // when it already exists; package-level functions may legally
                // share the same FQ-name prefix as a class and still require
                // a package symbol for import resolution.
                if binding.record.kind == .constructor,
                   prefix == Array(fq.dropLast()),
                   symbols.lookupAll(fqName: prefix).contains(where: { id in
                    symbols.symbol(id)?.kind != .package
                }) {
                    continue
                }
                syntheticPackagePaths.insert(prefix)
                if let moduleFQN {
                    syntheticPackageModules[prefix] = moduleFQN
                }
            }
        }
        for packagePath in syntheticPackagePaths {
            let existing = symbols.lookupAll(fqName: packagePath)
            let alreadyHasPackage = existing.contains { id in
                symbols.symbol(id)?.kind == .package
            }
            if !alreadyHasPackage {
                let name = packagePath.last ?? interner.intern("_")
                let packageSymbol = symbols.define(
                    kind: .package,
                    name: name,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                if let moduleFQN = syntheticPackageModules[packagePath] {
                    symbols.setModuleFQN(moduleFQN, for: packageSymbol)
                }
            }
        }

        return LibraryImportDeferredWork(
            pendingSupertypeEdges: pendingSupertypeEdges,
            importedBindings: importedBindings
        )
    }

    func applyImportedLibraryDeferredWork(
        _ work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for edge in work.pendingSupertypeEdges {
            guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            else {
                continue
            }
            var supertypes = symbols.directSupertypes(for: edge.subtype)
            if !supertypes.contains(superSymbol) {
                supertypes.append(superSymbol)
                supertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(supertypes, for: edge.subtype)
                types.setNominalDirectSupertypes(supertypes, for: edge.subtype)
            }
        }

        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            applyImportedNominalGenerics(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        // Resolve companion object references so ClassName.member() shorthand works.
        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            if let companionFQName = binding.record.companionObjectFQName,
               let companionSymbol = symbols.lookupAll(fqName: companionFQName)
                   .compactMap({ symbols.symbol($0) })
                   .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })?.id
            {
                symbols.setCompanionObjectSymbol(companionSymbol, for: binding.symbol)
            }
        }

        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            applyImportedNominalLayout(
                record: binding.record,
                symbol: binding.symbol,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath,
                interner: interner
            )
        }

        applyImportedObjectAndCompanionInitializerSymbols(
            work: work,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // P5-78: resolve sealed subclass FQ names to SymbolIDs for cross-module exhaustiveness
        for binding in work.importedBindings where binding.record.isSealedClass && !binding.record.sealedSubclassFQNames.isEmpty {
            let resolvedSubclasses: [SymbolID] = binding.record.sealedSubclassFQNames.compactMap { subFQName in
                symbols.lookupAll(fqName: subFQName)
                    .compactMap { symbols.symbol($0) }
                    .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            }
            // Only record concrete sealed subclasses when all declared subclass FQ names could be resolved.
            // If any subclass fails to resolve, mark the sealed type as having unknown/incomplete subclasses
            // by recording an empty sealed-subclass list as a sentinel, preventing the directSubtypes fallback
            // from incorrectly treating an incomplete set as exhaustive.
            if resolvedSubclasses.count == binding.record.sealedSubclassFQNames.count {
                symbols.setSealedSubclasses(resolvedSubclasses, for: binding.symbol)
            } else {
                symbols.setSealedSubclasses([], for: binding.symbol)
            }
        }
    }

    /// Normalizes imported member signatures after synthetic bundled anchors
    /// have been registered. Those anchors may provide the consumer's actual
    /// owner type-parameter symbols, which are not available during the
    /// initial library-record pass.
    func normalizeImportedLibraryMemberSignatures(
        _ work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let cache = LibraryMetadataCache()
        for binding in work.importedBindings {
            switch binding.record.kind {
            case .function, .constructor:
                guard let signature = symbols.functionSignature(for: binding.symbol) else {
                    continue
                }
                let normalize: (TypeID) -> TypeID = { type in
                    self.normalizeImportedOwnerTypeParameters(
                        type,
                        record: binding.record,
                        symbols: symbols,
                        types: types,
                        diagnostics: diagnostics,
                        interner: interner,
                        metadataPath: binding.metadataPath,
                        cache: cache,
                        allowPlaceholders: binding.isStdlibArtifact
                    )
                }
                let ownerTypeParameters = symbols.parentSymbol(for: binding.symbol)
                    .map { types.nominalTypeParameterSymbols(for: $0) } ?? []
                let ownerCount = min(signature.classTypeParameterCount, ownerTypeParameters.count)
                let normalizedTypeParameterSymbols = ownerCount == 0
                    ? signature.typeParameterSymbols
                    : Array(ownerTypeParameters.prefix(ownerCount))
                        + signature.typeParameterSymbols.dropFirst(ownerCount)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: signature.receiverType.map(normalize),
                        parameterTypes: signature.parameterTypes.map(normalize),
                        returnType: normalize(signature.returnType),
                        isSuspend: signature.isSuspend,
                        canThrow: signature.canThrow,
                        valueParameterSymbols: signature.valueParameterSymbols,
                        valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: signature.valueParameterIsVararg,
                        typeParameterSymbols: normalizedTypeParameterSymbols,
                        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                        typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList.map { $0.map(normalize) },
                        classTypeParameterCount: signature.classTypeParameterCount
                    ),
                    for: binding.symbol
                )
            case .property, .field:
                let propertyType = importedPropertyType(
                    record: binding.record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: binding.metadataPath,
                    cache: cache,
                    allowPlaceholders: binding.isStdlibArtifact
                )
                symbols.setPropertyType(propertyType, for: binding.symbol)
            default:
                continue
            }
        }
    }

    /// Restores the generic shape of an imported nominal type: its own type
    /// parameters (with declared variance) and the type arguments it passes to
    /// each generic supertype. Without them a `class Sub<T> : Base<T>` read back
    /// from metadata behaves like a raw type, so `Sub<Int>` neither lifts to
    /// `Base<Int>` nor substitutes `T` in its members' signatures.
    private func applyImportedNominalGenerics(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let record = binding.record
        let decode: (String) -> ClassType? = { token in
            guard let decoded = self.decodeImportedTypeSignature(
                token: token,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath,
                ownerFQName: record.fqName,
                allowPlaceholders: binding.isStdlibArtifact
            ), case let .classType(classType) = types.kind(of: decoded) else {
                return nil
            }
            return classType
        }

        if types.nominalTypeParameterSymbols(for: binding.symbol).isEmpty,
           let selfSignature = record.nominalTypeParametersSignature,
           let selfType = decode(selfSignature)
        {
            var typeParameterSymbols: [SymbolID] = []
            var variances: [TypeVariance] = []
            var isValid = true
            arguments: for arg in selfType.args {
                let argType: TypeID
                switch arg {
                case let .invariant(type):
                    argType = type
                    variances.append(.invariant)
                case let .out(type):
                    argType = type
                    variances.append(.out)
                case let .in(type):
                    argType = type
                    variances.append(.in)
                case .star:
                    isValid = false
                    break arguments
                }
                guard case let .typeParam(typeParam) = types.kind(of: argType) else {
                    isValid = false
                    break arguments
                }
                typeParameterSymbols.append(typeParam.symbol)
            }
            if isValid && !typeParameterSymbols.isEmpty {
                types.setNominalTypeParameterSymbols(typeParameterSymbols, for: binding.symbol)
                if variances.contains(where: { $0 != .invariant }) {
                    types.setNominalTypeParameterVariances(variances, for: binding.symbol)
                }
            }
        }

        for supertypeSignature in record.nominalSupertypeSignatures {
            guard let supertype = decode(supertypeSignature),
                  !supertype.args.isEmpty,
                  types.nominalSupertypeTypeArgs(for: binding.symbol, supertype: supertype.classSymbol).isEmpty
            else {
                continue
            }
            types.setNominalSupertypeTypeArgs(supertype.args, for: binding.symbol, supertype: supertype.classSymbol)
        }
    }

    /// Synthesizes function symbols for precompiled object/companion initializers
    /// discovered in library metadata so that consumers can call them before user `main`.
    private func applyImportedObjectAndCompanionInitializerSymbols(
        work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            let record = binding.record
            let ownerSymbol = binding.symbol

            if record.kind == .object,
               let linkName = record.objectInitializerLinkName,
               !linkName.isEmpty
            {
                let name = interner.intern("__object_init")
                let fqName = record.fqName + [name]
                let initSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(ownerSymbol, for: initSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: initSymbol
                )
                symbols.setExternalLinkName(linkName, for: initSymbol)
                symbols.setObjectInitializerSymbol(initSymbol, for: ownerSymbol)
            }

            if let linkName = record.companionInitializerLinkName,
               !linkName.isEmpty,
               symbols.companionObjectSymbol(for: ownerSymbol) != nil
            {
                let name = interner.intern("__companion_init")
                let fqName = record.fqName + [name]
                let initSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(ownerSymbol, for: initSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: initSymbol
                )
                symbols.setExternalLinkName(linkName, for: initSymbol)
                symbols.setCompanionObjectInitializerSymbol(initSymbol, for: ownerSymbol)
            }
        }
    }

    struct ImportedFieldOffsetEntry {
        let fqName: [InternedString]
        let offset: Int
    }

    struct ImportedVTableSlotEntry {
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let slot: Int
        let typeSignature: String?
        let propertyAccessorKind: PropertyAccessorKind?
    }

    struct ImportedITableSlotEntry {
        let fqName: [InternedString]
        let slot: Int
    }

    struct ImportedLibrarySymbolRecord {
        let kind: SymbolKind
        let mangledName: String
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let isInline: Bool
        let isOperator: Bool
        let isOverride: Bool
        let valueParameterIsVararg: [Bool]
        let valueParameterAllowsNonLocalReturn: [Bool]
        let valueParameterHasDefaultValues: [Bool]
        let canThrow: Bool
        let valueParameterNames: [String]
        let reifiedTypeParameterIndices: Set<Int>
        let typeSignature: String?
        let typeParameterUpperBoundsSignatures: [[String]]
        let defaultStubExternalLinkName: String?
        let externalLinkName: String?
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
        let superFQNames: [[InternedString]]?
        let companionObjectFQName: [InternedString]?
        let fieldOffsets: [ImportedFieldOffsetEntry]
        let vtableSlots: [ImportedVTableSlotEntry]
        let itableSlots: [ImportedITableSlotEntry]
        let objectInitializerLinkName: String?
        let companionInitializerLinkName: String?
        let enumStaticInitLinkName: String?
        let isDataClass: Bool
        let isOpenClass: Bool
        let modality: MetadataModality
        let isSealedClass: Bool
        let isFunInterface: Bool
        let isValueClass: Bool
        let isExpect: Bool
        let isActual: Bool
        let valueClassUnderlyingTypeSig: String?
        let annotations: [MetadataAnnotationRecord]
        let sealedSubclassFQNames: [[InternedString]]
        let propertyReceiverTypeSignature: String?
        let propertyGetterExternalLinkName: String?
        let abiReturnTypeSignature: String?
        let propertyGetterAbiReturnTypeSignature: String?
        let isMutable: Bool
        let nominalTypeParametersSignature: String?
        /// Generic self-signature of the nominal owner, when this record is a
        /// member. It lets imported member types replace metadata placeholders
        /// with the owner's actual type-parameter symbols.
        let ownerNominalTypeParametersSignature: String?
        let nominalSupertypeSignatures: [String]
        let constValueLiteral: String?
        /// Declaration-order type parameters of a nominal type, encoded as
        /// `<typeSignature>:<variance>` pairs (e.g. `T5023:i`).
        let nominalTypeParameters: String?

        init(
            kind: SymbolKind,
            mangledName: String = "",
            fqName: [InternedString] = [],
            arity: Int = 0,
            isSuspend: Bool = false,
            isInline: Bool = false,
            isOperator: Bool = false,
            isOverride: Bool = false,
            valueParameterIsVararg: [Bool] = [],
            valueParameterAllowsNonLocalReturn: [Bool] = [],
            valueParameterHasDefaultValues: [Bool] = [],
            canThrow: Bool = false,
            valueParameterNames: [String] = [],
            reifiedTypeParameterIndices: Set<Int> = [],
            typeSignature: String? = nil,
            typeParameterUpperBoundsSignatures: [[String]] = [],
            defaultStubExternalLinkName: String? = nil,
            externalLinkName: String? = nil,
            declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: [InternedString]? = nil,
        superFQNames: [[InternedString]]? = nil,
            companionObjectFQName: [InternedString]? = nil,
            fieldOffsets: [ImportedFieldOffsetEntry] = [],
            vtableSlots: [ImportedVTableSlotEntry] = [],
        itableSlots: [ImportedITableSlotEntry] = [],
        objectInitializerLinkName: String? = nil,
        companionInitializerLinkName: String? = nil,
        enumStaticInitLinkName: String? = nil,
        isDataClass: Bool = false,
        isOpenClass: Bool = false,
        modality: MetadataModality = .final,
        isSealedClass: Bool = false,
        isFunInterface: Bool = false,
            isValueClass: Bool = false,
            isExpect: Bool = false,
            isActual: Bool = false,
            valueClassUnderlyingTypeSig: String? = nil,
            annotations: [MetadataAnnotationRecord] = [],
            sealedSubclassFQNames: [[InternedString]] = [],
            propertyReceiverTypeSignature: String? = nil,
            propertyGetterExternalLinkName: String? = nil,
            abiReturnTypeSignature: String? = nil,
            propertyGetterAbiReturnTypeSignature: String? = nil,
            isMutable: Bool = false,
        nominalTypeParametersSignature: String? = nil,
        ownerNominalTypeParametersSignature: String? = nil,
        nominalSupertypeSignatures: [String] = [],
            constValueLiteral: String? = nil,
            nominalTypeParameters: String? = nil
        ) {
            self.kind = kind
            self.mangledName = mangledName
            self.fqName = fqName
            self.arity = arity
            self.isSuspend = isSuspend
            self.isInline = isInline
            self.isOperator = isOperator
            self.isOverride = isOverride
            self.valueParameterIsVararg = valueParameterIsVararg
            self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
            self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
            self.canThrow = canThrow
            self.valueParameterNames = valueParameterNames
            self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
            self.typeSignature = typeSignature
            self.typeParameterUpperBoundsSignatures = typeParameterUpperBoundsSignatures
            self.defaultStubExternalLinkName = defaultStubExternalLinkName
            self.externalLinkName = externalLinkName
            self.declaredFieldCount = declaredFieldCount
            self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
        self.superFQNames = superFQNames
            self.companionObjectFQName = companionObjectFQName
            self.fieldOffsets = fieldOffsets
            self.vtableSlots = vtableSlots
            self.itableSlots = itableSlots
        self.objectInitializerLinkName = objectInitializerLinkName
        self.companionInitializerLinkName = companionInitializerLinkName
        self.enumStaticInitLinkName = enumStaticInitLinkName
        self.isDataClass = isDataClass
        self.isOpenClass = isOpenClass
        self.modality = modality
        self.isSealedClass = isSealedClass
        self.isFunInterface = isFunInterface
            self.isValueClass = isValueClass
            self.isExpect = isExpect
            self.isActual = isActual
            self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
            self.annotations = annotations
            self.sealedSubclassFQNames = sealedSubclassFQNames
            self.propertyReceiverTypeSignature = propertyReceiverTypeSignature
            self.propertyGetterExternalLinkName = propertyGetterExternalLinkName
            self.abiReturnTypeSignature = abiReturnTypeSignature
            self.propertyGetterAbiReturnTypeSignature = propertyGetterAbiReturnTypeSignature
            self.isMutable = isMutable
        self.nominalTypeParametersSignature = nominalTypeParametersSignature
        self.ownerNominalTypeParametersSignature = ownerNominalTypeParametersSignature
            self.nominalSupertypeSignatures = nominalSupertypeSignatures
            self.constValueLiteral = constValueLiteral
            self.nominalTypeParameters = nominalTypeParameters
        }
    }

    struct ImportedLibraryBinding {
        let record: ImportedLibrarySymbolRecord
        let symbol: SymbolID
        let metadataPath: String
        let inlineKIRDir: String?
        let isStdlibArtifact: Bool
    }

    /// Walk a decoded type and collect all synthetic type parameter symbols
    /// (those with rawValue <= syntheticTypeParameterBase). Returns them sorted
    /// by index order (T0, T1, T2, ...) matching the original generic parameter list.
    private func collectSyntheticTypeParameters(_ typeID: TypeID, types: TypeSystem) -> [SymbolID] {
        var collected: Set<SymbolID> = []
        collectSyntheticTypeParamsRecursive(typeID, types: types, base: Self.syntheticTypeParameterBase, into: &collected)
        return collected.sorted { $0.rawValue > $1.rawValue }
    }

    private func collectSyntheticTypeParamsRecursive(
        _ typeID: TypeID,
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if tp.symbol.rawValue <= base { collected.insert(tp.symbol) }
        case let .classType(ct):
            collectSyntheticParamsFromClassArgs(ct.args, types: types, base: base, into: &collected)
        case let .functionType(ft):
            collectSyntheticParamsFromFunctionType(ft, types: types, base: base, into: &collected)
        case let .intersection(parts):
            for part in parts {
                collectSyntheticTypeParamsRecursive(part, types: types, base: base, into: &collected)
            }
        case let .kClassType(kc):
            collectSyntheticTypeParamsRecursive(kc.argument, types: types, base: base, into: &collected)
        case .stringStruct, .primitive, .any, .unit, .nothing, .error:
            break
        }
    }

    private func collectSyntheticParamsFromClassArgs(
        _ args: [TypeArg],
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        for arg in args {
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                collectSyntheticTypeParamsRecursive(inner, types: types, base: base, into: &collected)
            case .star:
                break
            }
        }
    }

    private func collectSyntheticParamsFromFunctionType(
        _ ft: FunctionType,
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        for contextReceiver in ft.contextReceivers {
            collectSyntheticTypeParamsRecursive(contextReceiver, types: types, base: base, into: &collected)
        }
        if let receiver = ft.receiver {
            collectSyntheticTypeParamsRecursive(receiver, types: types, base: base, into: &collected)
        }
        for param in ft.params {
            collectSyntheticTypeParamsRecursive(param, types: types, base: base, into: &collected)
        }
        collectSyntheticTypeParamsRecursive(ft.returnType, types: types, base: base, into: &collected)
    }

    func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private func applyImportedBinding(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])],
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool,
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
    ) {
        let record = binding.record
        let symbol = binding.symbol

        applyImportedBindingMetadata(record, symbol: symbol, symbols: symbols)

        if !record.annotations.isEmpty {
            symbols.setAnnotations(record.annotations, for: symbol)
        }

        applyImportedCallableMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            importedInlineFunctions: &importedInlineFunctions,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact,
            externalLinkNameToSymbol: externalLinkNameToSymbol,
            importedSymbolByFQName: importedSymbolByFQName
        )
        applyImportedValueClassMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            isStdlibArtifact: isStdlibArtifact
        )
        applyImportedTypeAliasMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact
        )
        applyImportedNominalMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact,
            pendingSupertypeEdges: &pendingSupertypeEdges
        )
    }

    private func applyImportedBindingMetadata(
        _ record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable
    ) {
        if let linkName = record.externalLinkName, !linkName.isEmpty {
            symbols.setExternalLinkName(linkName, for: symbol)
        }
        restoreImportedParentSymbol(record, symbol: symbol, symbols: symbols)
    }

    private func restoreImportedParentSymbol(
        _ record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable
    ) {
        guard record.kind == .function || record.kind == .property || record.kind == .field || record.kind == .constructor,
              record.fqName.count >= 2
        else {
            return
        }

        let ownerFQName = Array(record.fqName.dropLast())
        let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
        if let packageOwner = ownerCandidates.first(where: { $0.kind == .package }) {
            symbols.setParentSymbol(packageOwner.id, for: symbol)
            return
        }
        guard let ownerSymbol = ownerCandidates.first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id else {
            return
        }
        symbols.setParentSymbol(ownerSymbol, for: symbol)
    }

    private func applyImportedCallableMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool = false,
        externalLinkNameToSymbol: [String: SymbolID] = [:],
        importedSymbolByFQName: [String: SymbolID] = [:]
    ) {
        let record = binding.record
        let symbol = binding.symbol

        if record.kind == .function || record.kind == .constructor {
            let signature = importedFunctionSignature(
                record: record,
                ownerSymbol: symbol,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                cache: cache,
                allowPlaceholders: isStdlibArtifact
            )
            symbols.setFunctionSignature(signature, for: symbol)
            // Extension functions are represented as package-level FQ names in
            // metadata, but source compilation attaches them to their nominal
            // receiver for member fallback/dispatch lookup. Reconstruct that
            // ownership from the decoded receiver type so imported stdlib
            // extensions (for example Sequence.chunked/windowed) follow the
            // same resolution path as bundled source declarations.
            if let receiverType = signature.receiverType,
               case let .classType(receiverClassType) = types.kind(of: types.makeNonNullable(receiverType)),
               let receiverSymbol = symbols.symbol(receiverClassType.classSymbol),
               isNominalLayoutTargetSymbol(receiverSymbol.kind)
            {
                symbols.setParentSymbol(receiverSymbol.id, for: symbol)
            }
            if let defaultStubLink = record.defaultStubExternalLinkName, !defaultStubLink.isEmpty,
               signature.valueParameterHasDefaultValues.contains(true)
            {
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol)
                symbols.setExternalLinkName(defaultStubLink, for: stubSymbol)
                let intType = types.intType
                let reifiedCount = signature.reifiedTypeParameterIndices.count
                let stubParameterTypes = signature.parameterTypes + Array(repeating: intType, count: reifiedCount) + [intType]
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: signature.receiverType,
                        parameterTypes: stubParameterTypes,
                        returnType: signature.returnType,
                        isSuspend: false,
                        canThrow: signature.canThrow,
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: signature.typeParameterSymbols,
                        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                    ),
                    for: stubSymbol
                )
            }
            if let abiSig = record.abiReturnTypeSignature,
               let abiReturnType = decodeImportedTypeSignature(
                   token: abiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(abiReturnType, for: symbol)
            }
            importInlineFunctionIfNeeded(
                binding,
                symbol: symbol,
                signature: signature,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &importedInlineFunctions,
                externalLinkNameToSymbol: externalLinkNameToSymbol,
                importedSymbolByFQName: importedSymbolByFQName
            )
            return
        }

        guard record.kind == .property || record.kind == .field else {
            return
        }
        let propertyType = importedPropertyType(
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: binding.metadataPath,
            cache: cache,
            allowPlaceholders: isStdlibArtifact
        )
        symbols.setPropertyType(propertyType, for: symbol)

        // `const val` values are inlined at every use site, so carry the literal
        // across the library boundary instead of reading the (never initialized)
        // global slot of a precompiled library.
        if let constValueLiteral = record.constValueLiteral,
           let constValue = MetadataConstValueCoder.decode(constValueLiteral, interner: { interner.intern($0) })
        {
            symbols.setConstValueExprKind(constValue, for: symbol)
        }

        // Restore extension property accessor(s). Extension properties are
        // compiled as precompiled getter functions in the artifact objects;
        // we synthesize the accessor symbol and point it at that link name.
        if let receiverSig = record.propertyReceiverTypeSignature,
           let receiverType = decodeImportedTypeSignature(
               token: receiverSig,
               symbols: symbols,
               types: types,
               interner: interner,
               diagnostics: diagnostics,
               metadataPath: binding.metadataPath,
               ownerFQName: record.fqName,
               cache: cache,
               allowPlaceholders: isStdlibArtifact
           )
        {
            symbols.setExtensionPropertyReceiverType(receiverType, for: symbol)

            let getName = interner.intern("get")
            let getterFQName = record.fqName + [getName]
            let getterSymbol = symbols.define(
                kind: .function,
                name: getName,
                fqName: getterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(symbol, for: getterSymbol)
            symbols.setAccessorOwnerProperty(symbol, for: getterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: propertyType
                ),
                for: getterSymbol
            )
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)
            if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                symbols.setExternalLinkName(getterLink, for: getterSymbol)
            }
            if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature,
               let getterAbiReturnType = decodeImportedTypeSignature(
                   token: getterAbiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(getterAbiReturnType, for: getterSymbol)
            }

            if record.isMutable {
                let setName = interner.intern("set")
                let setterFQName = record.fqName + [setName]
                let setterSymbol = symbols.define(
                    kind: .function,
                    name: setName,
                    fqName: setterFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(symbol, for: setterSymbol)
                symbols.setAccessorOwnerProperty(symbol, for: setterSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [propertyType],
                        returnType: types.unitType
                    ),
                    for: setterSymbol
                )
                symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
            }
        }
        // Member and top-level properties with custom getters also carry a
        // precompiled getter link name. Restore a synthetic accessor so reads
        // route through it instead of through a global slot the artifact never
        // allocates.
        // A nominal owner is restored by restoreImportedParentSymbol before this
        // runs, so an owner that is absent or a package means the property is
        // top-level and its getter takes no receiver.
        let getterOwnerInfo = symbols.parentSymbol(for: symbol).flatMap { symbols.symbol($0) }
        if record.propertyGetterExternalLinkName != nil,
           record.propertyReceiverTypeSignature == nil,
           getterOwnerInfo == nil || getterOwnerInfo?.kind == .package
               || getterOwnerInfo?.kind == .class || getterOwnerInfo?.kind == .enumClass
               || getterOwnerInfo?.kind == .interface
               || getterOwnerInfo?.kind == .object
        {
            symbols.setPropertyHasCustomGetter(true, for: symbol)
            let ownerType: TypeID? = getterOwnerInfo.flatMap { ownerInfo in
                ownerInfo.kind == .package
                    ? nil
                    : types.make(.classType(ClassType(classSymbol: ownerInfo.id, args: [], nullability: .nonNull)))
            }
            let getName = interner.intern("get")
            let getterFQName = record.fqName + [getName]
            let getterSymbol = symbols.define(
                kind: .function,
                name: getName,
                fqName: getterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(symbol, for: getterSymbol)
            symbols.setAccessorOwnerProperty(symbol, for: getterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [],
                    returnType: propertyType
                ),
                for: getterSymbol
            )
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)
            if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                symbols.setExternalLinkName(getterLink, for: getterSymbol)
            }
            if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature,
               let getterAbiReturnType = decodeImportedTypeSignature(
                   token: getterAbiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(getterAbiReturnType, for: getterSymbol)
            }
        }
    }

    private func importInlineFunctionIfNeeded(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
    ) {
        let record = binding.record
        guard record.isInline,
              !record.mangledName.isEmpty,
              let inlineDir = binding.inlineKIRDir
        else {
            return
        }

        let fileName = MetadataEncoder.inlineKIRFileName(for: record.mangledName)
        let inlinePath = URL(fileURLWithPath: inlineDir)
            .appendingPathComponent(fileName)
            .standardized
            .path
        let inlineDirResolved = URL(fileURLWithPath: inlineDir).standardized.path
        guard inlinePath.hasPrefix(inlineDirResolved + "/") else {
            diagnostics.error(
                "KSWIFTK-LIB-0019",
                "Inline KIR path for '\(record.mangledName)' escapes inline directory",
                range: nil
            )
            return
        }
        guard FileManager.default.fileExists(atPath: inlinePath) else {
            let recordFQName = record.fqName.map { interner.resolve($0) }.joined(separator: ".")
            if binding.isStdlibArtifact {
                diagnostics.error(
                    "KSWIFTK-LIB-0023",
                    "Stdlib artifact is missing inline KIR for '" + recordFQName + "': " + inlinePath,
                    range: nil
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0002",
                    "Unable to read inline KIR artifact: " + inlinePath,
                    range: nil
                )
            }
            return
        }
        guard let inlineFunction = parseImportedInlineFunction(
            path: inlinePath,
            importedSymbol: symbol,
            signature: signature,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            externalLinkNameToSymbol: externalLinkNameToSymbol,
            importedSymbolByFQName: importedSymbolByFQName
        ) else {
            return
        }
        importedInlineFunctions[symbol] = inlineFunction
    }

    private func applyImportedValueClassMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        isStdlibArtifact: Bool = false
    ) {
        let record = binding.record
        guard record.isValueClass else {
            return
        }

        if let signature = record.valueClassUnderlyingTypeSig {
            let underlyingType = importedValueClassUnderlyingType(
                signature: signature,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                ownerFQName: record.fqName,
                allowPlaceholders: isStdlibArtifact
            )
            if let underlyingType {
                symbols.setValueClassUnderlyingType(underlyingType, for: binding.symbol)
            }
            return
        }

        diagnostics.warning(
            "KSWIFTK-LIB-0007",
            "Value class '\(renderFQName(record.fqName, interner: interner))' has no underlying type signature"
                + " in library metadata at '\(binding.metadataPath)'. Boxing elision will be skipped for this type.",
            range: nil
        )
    }

    private func applyImportedTypeAliasMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool = false
    ) {
        let record = binding.record
        guard record.kind == .typeAlias else {
            return
        }

        let underlyingType = importedTypeAliasUnderlyingType(
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: binding.metadataPath,
            cache: cache,
            allowPlaceholders: isStdlibArtifact
        )
        guard let underlyingType else {
            return
        }
        symbols.setTypeAliasUnderlyingType(underlyingType, for: binding.symbol)
        let syntheticParams = collectSyntheticTypeParameters(underlyingType, types: types)
        if !syntheticParams.isEmpty {
            symbols.setTypeAliasTypeParameters(syntheticParams, for: binding.symbol)
        }
    }

    private func applyImportedNominalMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool,
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])]
    ) {
        let record = binding.record
        guard isNominalLayoutTargetSymbol(record.kind) else {
            return
        }

        applyImportedNominalTypeParameters(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact
        )

        // Restore the parent link for imported nominal types (e.g. nested enum
        // classes like Base64.PaddingOption). Without this, member lookup on
        // the nested owner fails and the consumer falls back to treating the
        // nested type as a constructor call, breaking enum entry references.
        if record.fqName.count >= 2 {
            let ownerFQName = Array(record.fqName.dropLast())
            let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
            if let packageOwner = ownerCandidates.first(where: { $0.kind == .package }) {
                symbols.setParentSymbol(packageOwner.id, for: binding.symbol)
            } else if let ownerSymbol = ownerCandidates.first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id {
                symbols.setParentSymbol(ownerSymbol, for: binding.symbol)
            }
        }

        let hasLayoutHint =
            record.declaredFieldCount != nil ||
            record.declaredInstanceSizeWords != nil ||
            record.declaredVtableSize != nil ||
            record.declaredItableSize != nil
        if hasLayoutHint {
            symbols.setNominalLayoutHint(
                NominalLayoutHint(
                    declaredFieldCount: record.declaredFieldCount,
                    declaredInstanceSizeWords: record.declaredInstanceSizeWords,
                    declaredVtableSize: record.declaredVtableSize,
                    declaredItableSize: record.declaredItableSize
                ),
                for: binding.symbol
            )
        }
        let allSuperFQNames = record.superFQNames ?? record.superFQName.map { [$0] } ?? []
        for superFQName in allSuperFQNames where !superFQName.isEmpty {
            pendingSupertypeEdges.append((subtype: binding.symbol, superFQName: superFQName))
        }

        // Import the precompiled enum static initializer link so the consumer
        // can call it before `main`, ensuring enum entry globals are initialized.
        if record.kind == .enumClass,
           let enumStaticInitLink = record.enumStaticInitLinkName,
           !enumStaticInitLink.isEmpty
        {
            let initName = interner.intern("__enum_static_init")
            let initFQName = record.fqName + [initName]
            let initSymbol = symbols.define(
                kind: .function,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setExternalLinkName(enumStaticInitLink, for: initSymbol)
            symbols.setParentSymbol(binding.symbol, for: initSymbol)
            symbols.setEnumStaticInitSymbol(initSymbol, for: binding.symbol)
        }
    }

    /// Restores the declaration-order type parameters of an imported generic
    /// nominal type. Without them the consumer treats the type as non-generic,
    /// so explicit type arguments (`ArrayDeque<Int>()`) and member type
    /// substitution fail to resolve.
    private func applyImportedNominalTypeParameters(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool
    ) {
        guard let encoded = binding.record.nominalTypeParameters, !encoded.isEmpty else {
            return
        }

        var typeParameterSymbols: [SymbolID] = []
        var variances: [TypeVariance] = []
        for entry in encoded.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let token = parts.first,
                  let decoded = decodeImportedTypeSignature(
                      token: String(token),
                      symbols: symbols,
                      types: types,
                      interner: interner,
                      diagnostics: diagnostics,
                      metadataPath: binding.metadataPath,
                      ownerFQName: binding.record.fqName,
                      cache: cache,
                      allowPlaceholders: isStdlibArtifact
                  ),
                  case let .typeParam(typeParam) = types.kind(of: decoded)
            else {
                return
            }
            typeParameterSymbols.append(typeParam.symbol)
            switch parts.count > 1 ? String(parts[1]) : "i" {
            case "o": variances.append(.out)
            case "n": variances.append(.in)
            default: variances.append(.invariant)
            }
        }

        guard !typeParameterSymbols.isEmpty else {
            return
        }
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: binding.symbol)
        types.setNominalTypeParameterVariances(variances, for: binding.symbol)
    }
}
