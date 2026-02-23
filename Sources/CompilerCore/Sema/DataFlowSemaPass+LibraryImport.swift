import Foundation

extension DataFlowSemaPassPhase {
    struct LibraryManifestInfo {
        let metadataPath: String
        let inlineKIRDir: String?
        let isValid: Bool
    }

    func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction]
    ) {
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.searchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        var importedBindings: [ImportedLibraryBinding] = []

        for libraryDir in libraryDirs {
            let manifestInfo = resolveLibraryManifestInfo(
                libraryDir: libraryDir,
                currentTarget: options.target,
                diagnostics: diagnostics
            )
            guard manifestInfo.isValid else {
                continue
            }
            let metadataPath = manifestInfo.metadataPath
            guard let records = parseLibraryMetadata(
                path: metadataPath,
                diagnostics: diagnostics,
                interner: interner
            ) else {
                continue
            }

            for record in records {
                guard !record.fqName.isEmpty else {
                    continue
                }
                let name = record.fqName.last ?? interner.intern("_")
                var flags: SymbolFlags = [.synthetic]
                if record.isSuspend && record.kind == .function {
                    flags.insert(.suspendFunction)
                }
                if record.isInline && record.kind == .function {
                    flags.insert(.inlineFunction)
                }
                if record.isDataClass {
                    flags.insert(.dataType)
                }
                if record.isSealedClass {
                    flags.insert(.sealedType)
                }
                let symbol = symbols.define(
                    kind: record.kind,
                    name: name,
                    fqName: record.fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                importedBindings.append(ImportedLibraryBinding(
                    record: record,
                    symbol: symbol,
                    metadataPath: metadataPath,
                    inlineKIRDir: manifestInfo.inlineKIRDir
                ))
            }
        }

        for binding in importedBindings {
            let record = binding.record
            let symbol = binding.symbol

            if let linkName = record.externalLinkName, !linkName.isEmpty {
                symbols.setExternalLinkName(linkName, for: symbol)
            }

            if !record.annotations.isEmpty {
                symbols.setAnnotations(record.annotations, for: symbol)
            }

            if record.kind == .function {
                let signature = importedFunctionSignature(
                    record: record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: binding.metadataPath
                )
                symbols.setFunctionSignature(signature, for: symbol)
                if record.isInline,
                   !record.mangledName.isEmpty,
                   let inlineDir = binding.inlineKIRDir {
                    let inlinePath = URL(fileURLWithPath: inlineDir)
                        .appendingPathComponent(record.mangledName + ".kirbin")
                        .path
                    if let inlineFunction = parseImportedInlineFunction(
                        path: inlinePath,
                        importedSymbol: symbol,
                        parameterCount: max(0, signature.parameterTypes.count),
                        types: types,
                        interner: interner,
                        diagnostics: diagnostics
                    ) {
                        importedInlineFunctions[symbol] = inlineFunction
                    }
                }
            } else if record.kind == .property || record.kind == .field {
                let propertyType = importedPropertyType(
                    record: record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: binding.metadataPath
                )
                symbols.setPropertyType(propertyType, for: symbol)
            } else if record.kind == .typeAlias {
                let underlyingType = importedTypeAliasUnderlyingType(
                    record: record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: binding.metadataPath
                )
                if let underlyingType {
                    symbols.setTypeAliasUnderlyingType(underlyingType, for: symbol)
                    let syntheticParams = collectSyntheticTypeParameters(underlyingType, types: types)
                    if !syntheticParams.isEmpty {
                        symbols.setTypeAliasTypeParameters(syntheticParams, for: symbol)
                    }
                }
            }

            if isNominalLayoutTargetSymbol(record.kind) {
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
                        for: symbol
                    )
                }
                if let superFQName = record.superFQName, !superFQName.isEmpty {
                    pendingSupertypeEdges.append((subtype: symbol, superFQName: superFQName))
                }
            }
        }

        var syntheticPackagePaths: Set<[InternedString]> = []
        for binding in importedBindings where binding.record.kind != .package {
            let fq = binding.record.fqName
            for length in 1..<fq.count {
                let prefix = Array(fq.prefix(length))
                syntheticPackagePaths.insert(prefix)
            }
        }
        for packagePath in syntheticPackagePaths {
            let existing = symbols.lookupAll(fqName: packagePath)
            let alreadyHasPackage = existing.contains { id in
                symbols.symbol(id)?.kind == .package
            }
            if !alreadyHasPackage {
                let name = packagePath.last ?? interner.intern("_")
                _ = symbols.define(
                    kind: .package,
                    name: name,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }

        for edge in pendingSupertypeEdges {
            guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id else {
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

        for binding in importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            applyImportedNominalLayout(
                record: binding.record,
                symbol: binding.symbol,
                symbols: symbols,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath
            )
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
        let typeSignature: String?
        let externalLinkName: String?
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
        let fieldOffsets: [ImportedFieldOffsetEntry]
        let vtableSlots: [ImportedVTableSlotEntry]
        let itableSlots: [ImportedITableSlotEntry]
        let isDataClass: Bool
        let isSealedClass: Bool
        let annotations: [MetadataAnnotationRecord]
    }

    struct ImportedLibraryBinding {
        let record: ImportedLibrarySymbolRecord
        let symbol: SymbolID
        let metadataPath: String
        let inlineKIRDir: String?
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
        case .typeParam(let tp):
            if tp.symbol.rawValue <= base {
                collected.insert(tp.symbol)
            }
        case .classType(let ct):
            for arg in ct.args {
                switch arg {
                case .invariant(let inner), .out(let inner), .in(let inner):
                    collectSyntheticTypeParamsRecursive(inner, types: types, base: base, into: &collected)
                case .star:
                    break
                }
            }
        case .functionType(let ft):
            if let receiver = ft.receiver {
                collectSyntheticTypeParamsRecursive(receiver, types: types, base: base, into: &collected)
            }
            for param in ft.params {
                collectSyntheticTypeParamsRecursive(param, types: types, base: base, into: &collected)
            }
            collectSyntheticTypeParamsRecursive(ft.returnType, types: types, base: base, into: &collected)
        case .intersection(let parts):
            for part in parts {
                collectSyntheticTypeParamsRecursive(part, types: types, base: base, into: &collected)
            }
        case .primitive, .any, .unit, .nothing, .error:
            break
        case .intersection:
            break
        }
    }

    func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
        switch token {
        case "package":
            return .package
        case "class":
            return .class
        case "interface":
            return .interface
        case "object":
            return .object
        case "enumClass":
            return .enumClass
        case "annotationClass":
            return .annotationClass
        case "typeAlias":
            return .typeAlias
        case "function":
            return .function
        case "constructor":
            return .constructor
        case "property":
            return .property
        case "field":
            return .field
        case "typeParameter":
            return .typeParameter
        case "valueParameter":
            return .valueParameter
        case "local":
            return .local
        case "label":
            return .label
        default:
            return nil
        }
    }
}
