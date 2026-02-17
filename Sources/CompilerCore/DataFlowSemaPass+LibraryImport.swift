import Foundation

extension DataFlowSemaPassPhase {
    private struct LibraryManifestInfo {
        let metadataPath: String
        let inlineKIRDir: String?
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
            let manifestInfo = resolveLibraryManifestInfo(libraryDir: libraryDir)
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

    private struct ImportedFieldOffsetEntry {
        let fqName: [InternedString]
        let offset: Int
    }

    private struct ImportedVTableSlotEntry {
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let slot: Int
    }

    private struct ImportedITableSlotEntry {
        let fqName: [InternedString]
        let slot: Int
    }

    private struct ImportedLibrarySymbolRecord {
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
    }

    private struct ImportedLibraryBinding {
        let record: ImportedLibrarySymbolRecord
        let symbol: SymbolID
        let metadataPath: String
        let inlineKIRDir: String?
    }

    private func discoverLibraryDirectories(searchPaths: [String]) -> [String] {
        let fm = FileManager.default
        var found: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                found.insert(path)
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                found.insert(URL(fileURLWithPath: path).appendingPathComponent(entry).path)
            }
        }
        return found.sorted()
    }

    private func resolveLibraryManifestInfo(libraryDir: String) -> LibraryManifestInfo {
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            let metadataPath: String
            if let metadataRelativePath = object["metadata"] as? String, !metadataRelativePath.isEmpty {
                metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent(metadataRelativePath).path
            } else {
                metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path
            }
            let inlineKIRDir: String?
            if let inlineRelativePath = object["inlineKIRDir"] as? String, !inlineRelativePath.isEmpty {
                inlineKIRDir = URL(fileURLWithPath: libraryDir).appendingPathComponent(inlineRelativePath).path
            } else {
                inlineKIRDir = nil
            }
            return LibraryManifestInfo(metadataPath: metadataPath, inlineKIRDir: inlineKIRDir)
        }
        return LibraryManifestInfo(
            metadataPath: URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path,
            inlineKIRDir: URL(fileURLWithPath: libraryDir).appendingPathComponent("inline-kir").path
        )
    }

    private func parseLibraryMetadata(
        path: String,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> [ImportedLibrarySymbolRecord]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0001",
                "Unable to read library metadata: \(path)",
                range: nil
            )
            return nil
        }

        var records: [ImportedLibrarySymbolRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken) else {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var fqName: [InternedString] = []
            var arity = 0
            var isSuspend = false
            var isInline = false
            var typeSignature: String? = nil
            var externalLinkName: String? = nil
            var declaredFieldCount: Int? = nil
            var declaredInstanceSizeWords: Int? = nil
            var declaredVtableSize: Int? = nil
            var declaredItableSize: Int? = nil
            var superFQName: [InternedString]? = nil
            var fieldOffsets: [ImportedFieldOffsetEntry] = []
            var vtableSlots: [ImportedVTableSlotEntry] = []
            var itableSlots: [ImportedITableSlotEntry] = []

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                switch key {
                case "fq":
                    fqName = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
                case "arity":
                    arity = Int(value) ?? 0
                case "suspend":
                    isSuspend = value == "1" || value == "true"
                case "inline":
                    isInline = value == "1" || value == "true"
                case "sig":
                    typeSignature = value.isEmpty ? nil : value
                case "link":
                    externalLinkName = value.isEmpty ? nil : value
                case "fields":
                    declaredFieldCount = Int(value)
                case "layoutWords":
                    declaredInstanceSizeWords = Int(value)
                case "vtable":
                    declaredVtableSize = Int(value)
                case "itable":
                    declaredItableSize = Int(value)
                case "superFq":
                    let parsed = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
                    superFQName = parsed.isEmpty ? nil : parsed
                case "fieldOffsets":
                    fieldOffsets = parseImportedFieldOffsets(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                case "vtableSlots":
                    vtableSlots = parseImportedVTableSlots(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                case "itableSlots":
                    itableSlots = parseImportedITableSlots(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                default:
                    continue
                }
            }

            guard !fqName.isEmpty else {
                continue
            }
            records.append(ImportedLibrarySymbolRecord(
                kind: kind,
                mangledName: mangledName,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                isInline: isInline,
                typeSignature: typeSignature,
                externalLinkName: externalLinkName,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots
            ))
        }

        return records
    }

    private func importedFunctionSignature(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> FunctionSignature {
        let fallback = FunctionSignature(
            parameterTypes: Array(repeating: types.anyType, count: max(0, record.arity)),
            returnType: types.anyType,
            isSuspend: record.isSuspend
        )
        guard let encodedSignature = record.typeSignature else {
            return fallback
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) else {
            return fallback
        }
        guard case .functionType(let functionType) = types.kind(of: decoded) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0003",
                "Invalid function signature metadata at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
            return fallback
        }
        if record.arity != functionType.params.count || record.isSuspend != functionType.isSuspend {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "Metadata signature/arity mismatch at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
        }
        return FunctionSignature(
            receiverType: functionType.receiver,
            parameterTypes: functionType.params,
            returnType: functionType.returnType,
            isSuspend: functionType.isSuspend
        )
    }

    private func importedPropertyType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> TypeID {
        guard let encodedSignature = record.typeSignature else {
            return types.anyType
        }
        return decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) ?? types.anyType
    }

    private func importedTypeAliasUnderlyingType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> TypeID? {
        guard let encodedSignature = record.typeSignature else {
            return nil
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0003",
                "Invalid typealias signature metadata at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
            return nil
        }
        return decoded
    }

    private func decodeImportedTypeSignature(
        token: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString]
    ) -> TypeID? {
        var parser = MetadataTypeSignatureParser(
            source: token,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName
        )
        return parser.parse()
    }

    private func parseImportedFieldOffsets(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedFieldOffsetEntry] {
        let pairs = parseImportedKeySlotPairs(
            token: token,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner
        )
        return pairs.compactMap { key, offset in
            let fqName = key.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid fieldOffsets entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            return ImportedFieldOffsetEntry(fqName: fqName, offset: offset)
        }
    }

    private func parseImportedVTableSlots(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedVTableSlotEntry] {
        let pairs = parseImportedKeySlotPairs(
            token: token,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner
        )
        return pairs.compactMap { key, slot in
            let components = key.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
            guard components.count == 3,
                  let arity = Int(components[1]) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid vtableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            let fqName = components[0].split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid vtableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            let suspendToken = components[2].lowercased()
            let isSuspend = suspendToken == "1" || suspendToken == "true"
            return ImportedVTableSlotEntry(
                fqName: fqName,
                arity: max(0, arity),
                isSuspend: isSuspend,
                slot: slot
            )
        }
    }

    private func parseImportedITableSlots(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedITableSlotEntry] {
        let pairs = parseImportedKeySlotPairs(
            token: token,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner
        )
        return pairs.compactMap { key, slot in
            let fqName = key.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid itableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            return ImportedITableSlotEntry(fqName: fqName, slot: slot)
        }
    }

    private func parseImportedKeySlotPairs(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [(String, Int)] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        var result: [(String, Int)] = []
        for rawEntry in trimmed.split(separator: ",", omittingEmptySubsequences: true) {
            let entry = String(rawEntry)
            guard let separatorIndex = entry.lastIndex(of: "@"),
                  separatorIndex < entry.index(before: entry.endIndex),
                  let slot = Int(entry[entry.index(after: separatorIndex)...]) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed metadata slot entry at \(metadataPath): \(entry) (\(renderFQName(ownerFQName, interner: interner)))",
                    range: nil
                )
                continue
            }
            let key = String(entry[..<separatorIndex])
            guard !key.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed metadata slot entry at \(metadataPath): \(entry)",
                    range: nil
                )
                continue
            }
            result.append((key, slot))
        }
        return result
    }

    private func applyImportedNominalLayout(
        record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        metadataPath: String
    ) {
        guard !record.fieldOffsets.isEmpty || !record.vtableSlots.isEmpty || !record.itableSlots.isEmpty else {
            return
        }

        var resolvedFieldOffsets: [SymbolID: Int] = [:]
        for entry in record.fieldOffsets {
            guard let fieldSymbol = resolveImportedFieldSymbol(entry.fqName, symbols: symbols) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata field symbol in \(metadataPath): \(entry.fqName)",
                    range: nil
                )
                continue
            }
            resolvedFieldOffsets[fieldSymbol] = entry.offset
        }

        var resolvedVTableSlots: [SymbolID: Int] = [:]
        for entry in record.vtableSlots {
            guard let methodSymbol = resolveImportedMethodSymbol(
                fqName: entry.fqName,
                arity: entry.arity,
                isSuspend: entry.isSuspend,
                symbols: symbols
            ) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata vtable symbol in \(metadataPath): \(entry.fqName)",
                    range: nil
                )
                continue
            }
            resolvedVTableSlots[methodSymbol] = entry.slot
        }

        var resolvedITableSlots: [SymbolID: Int] = [:]
        for entry in record.itableSlots {
            guard let interfaceSymbol = resolveImportedInterfaceSymbol(entry.fqName, symbols: symbols) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata interface symbol in \(metadataPath): \(entry.fqName)",
                    range: nil
                )
                continue
            }
            resolvedITableSlots[interfaceSymbol] = entry.slot
        }

        let objectHeaderWords = 2
        let maxFieldOffsetSize = (resolvedFieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        let instanceFieldCount = max(record.declaredFieldCount ?? 0, resolvedFieldOffsets.count)
        let instanceSizeWords = max(
            record.declaredInstanceSizeWords ?? 0,
            max(objectHeaderWords + instanceFieldCount, maxFieldOffsetSize)
        )
        let maxVTableSize = (resolvedVTableSlots.values.max() ?? -1) + 1
        let maxITableSize = (resolvedITableSlots.values.max() ?? -1) + 1
        if let declaredVTableSize = record.declaredVtableSize,
           declaredVTableSize >= 0,
           declaredVTableSize < maxVTableSize {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "metadata vtable size mismatch at \(metadataPath) for symbol \(symbol.rawValue)",
                range: nil
            )
        }
        if let declaredITableSize = record.declaredItableSize,
           declaredITableSize >= 0,
           declaredITableSize < maxITableSize {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "metadata itable size mismatch at \(metadataPath) for symbol \(symbol.rawValue)",
                range: nil
            )
        }
        let vtableSize = max(record.declaredVtableSize ?? 0, maxVTableSize)
        let itableSize = max(record.declaredItableSize ?? 0, maxITableSize)
        let superClass = symbols.directSupertypes(for: symbol)
            .compactMap { symbols.symbol($0) }
            .first(where: { $0.kind != .interface })?.id

        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: max(0, instanceFieldCount),
                instanceSizeWords: max(0, instanceSizeWords),
                fieldOffsets: resolvedFieldOffsets,
                vtableSlots: resolvedVTableSlots,
                itableSlots: resolvedITableSlots,
                vtableSize: max(0, vtableSize),
                itableSize: max(0, itableSize),
                superClass: superClass
            ),
            for: symbol
        )
    }

    private func resolveImportedFieldSymbol(
        _ fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID? {
        symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .first(where: { $0.kind == .field || $0.kind == .property })?
            .id
    }

    private func resolveImportedMethodSymbol(
        fqName: [InternedString],
        arity: Int,
        isSuspend: Bool,
        symbols: SymbolTable
    ) -> SymbolID? {
        let candidates = symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .filter { symbol in
                guard symbol.kind == .function,
                      let signature = symbols.functionSignature(for: symbol.id) else {
                    return false
                }
                return signature.parameterTypes.count == arity && signature.isSuspend == isSuspend
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
        return candidates.first?.id
    }

    private func resolveImportedInterfaceSymbol(
        _ fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID? {
        symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .first(where: { $0.kind == .interface })?
            .id
    }

    private func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private struct MetadataTypeSignatureParser {
        private let source: [Character]
        private var index: Int
        private let symbols: SymbolTable
        private let types: TypeSystem
        private let interner: StringInterner
        private let diagnostics: DiagnosticEngine
        private let metadataPath: String
        private let ownerFQName: [InternedString]
        private let syntheticTypeParameterBase: Int32 = -1_000_000

        init(
            source: String,
            symbols: SymbolTable,
            types: TypeSystem,
            interner: StringInterner,
            diagnostics: DiagnosticEngine,
            metadataPath: String,
            ownerFQName: [InternedString]
        ) {
            self.source = Array(source)
            self.index = 0
            self.symbols = symbols
            self.types = types
            self.interner = interner
            self.diagnostics = diagnostics
            self.metadataPath = metadataPath
            self.ownerFQName = ownerFQName
        }

        mutating func parse() -> TypeID? {
            guard let type = parseType(), index == source.count else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed type signature in metadata at \(metadataPath): \(String(source)) (\(ownerName()))",
                    range: nil
                )
                return nil
            }
            return type
        }

        private mutating func parseType() -> TypeID? {
            if consume(prefix: "Q<") {
                guard let inner = parseType(), consume(character: ">") else {
                    return nil
                }
                return makeNullable(inner)
            }
            if consume(prefix: "SF"), let next = peek(), next.isNumber {
                return parseFunctionType(isSuspend: true)
            }
            if consume(character: "F") {
                if let next = peek(), next.isNumber {
                    return parseFunctionType(isSuspend: false)
                }
                return types.make(.primitive(.float, .nonNull))
            }
            if consume(character: "E") {
                return types.errorType
            }
            if consume(character: "U") {
                return types.unitType
            }
            if consume(character: "N") {
                return types.nothingType
            }
            if consume(character: "A") {
                return types.anyType
            }
            if consume(character: "Z") {
                return types.make(.primitive(.boolean, .nonNull))
            }
            if consume(character: "C") {
                return types.make(.primitive(.char, .nonNull))
            }
            if consume(character: "I") {
                return types.make(.primitive(.int, .nonNull))
            }
            if consume(character: "J") {
                return types.make(.primitive(.long, .nonNull))
            }
            if consume(character: "D") {
                return types.make(.primitive(.double, .nonNull))
            }
            if consume(character: "L") {
                return parseClassType()
            }
            if consume(character: "T") {
                return parseTypeParameterType()
            }
            if consume(prefix: "X<") {
                return parseIntersectionType()
            }
            return nil
        }

        private mutating func parseClassType() -> TypeID? {
            let name = parseUntilDelimiters(["<", ";"])
            guard !name.isEmpty else {
                return nil
            }

            var args: [TypeArg] = []
            if consume(character: "<") {
                while true {
                    guard let arg = parseTypeArg() else {
                        return nil
                    }
                    args.append(arg)
                    if consume(character: ">") {
                        break
                    }
                    guard consume(character: ",") else {
                        return nil
                    }
                }
            }
            guard consume(character: ";") else {
                return nil
            }
            if name == "kotlin_String" {
                return types.make(.primitive(.string, .nonNull))
            }

            let fqName = name.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                return nil
            }
            let candidates = symbols.lookupAll(fqName: fqName)
                .compactMap { symbols.symbol($0) }
                .filter { symbol in
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })
            guard let classSymbol = candidates.first?.id else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown nominal type in metadata signature at \(metadataPath): \(name) (\(ownerName()))",
                    range: nil
                )
                return types.anyType
            }
            return types.make(.classType(ClassType(classSymbol: classSymbol, args: args, nullability: .nonNull)))
        }

        private mutating func parseTypeArg() -> TypeArg? {
            if consume(character: "*") {
                return .star
            }
            if consume(prefix: "O<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .out(type)
            }
            if consume(prefix: "N<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .in(type)
            }
            guard let type = parseType() else {
                return nil
            }
            return .invariant(type)
        }

        private mutating func parseFunctionType(isSuspend: Bool) -> TypeID? {
            guard let arity = parseNumber(), consume(character: "<") else {
                return nil
            }

            var receiver: TypeID?
            if consume(character: "R") {
                guard let receiverType = parseType(), consume(character: ",") else {
                    return nil
                }
                receiver = receiverType
            }

            var params: [TypeID] = []
            params.reserveCapacity(arity)
            for _ in 0..<arity {
                guard let parameterType = parseType() else {
                    return nil
                }
                params.append(parameterType)
                guard consume(character: ",") else {
                    return nil
                }
            }

            guard let returnType = parseType(), consume(character: ">") else {
                return nil
            }
            return types.make(.functionType(FunctionType(
                receiver: receiver,
                params: params,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: .nonNull
            )))
        }

        private mutating func parseTypeParameterType() -> TypeID? {
            guard let rawIndex = parseNumber() else {
                return nil
            }
            let rawSymbol = syntheticTypeParameterBase - Int32(truncatingIfNeeded: rawIndex)
            return types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: rawSymbol), nullability: .nonNull)))
        }

        private mutating func parseIntersectionType() -> TypeID? {
            var parts: [TypeID] = []
            while true {
                guard let type = parseType() else {
                    return nil
                }
                parts.append(type)
                if consume(character: ">") {
                    break
                }
                guard consume(character: "&") else {
                    return nil
                }
            }
            return types.make(.intersection(parts))
        }

        private func makeNullable(_ type: TypeID) -> TypeID {
            switch types.kind(of: type) {
            case .any:
                return types.nullableAnyType
            case .primitive(let primitive, _):
                return types.make(.primitive(primitive, .nullable))
            case .classType(let classType):
                return types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: classType.args,
                    nullability: .nullable
                )))
            case .typeParam(let typeParam):
                return types.make(.typeParam(TypeParamType(symbol: typeParam.symbol, nullability: .nullable)))
            case .functionType(let functionType):
                return types.make(.functionType(FunctionType(
                    receiver: functionType.receiver,
                    params: functionType.params,
                    returnType: functionType.returnType,
                    isSuspend: functionType.isSuspend,
                    nullability: .nullable
                )))
            default:
                return types.nullableAnyType
            }
        }

        private mutating func parseNumber() -> Int? {
            let start = index
            while let ch = peek(), ch.isNumber {
                index += 1
            }
            guard index > start else {
                return nil
            }
            return Int(String(source[start..<index]))
        }

        private mutating func parseUntilDelimiters(_ delimiters: Set<Character>) -> String {
            let start = index
            while let ch = peek(), !delimiters.contains(ch) {
                index += 1
            }
            return String(source[start..<index])
        }

        private func peek() -> Character? {
            guard index < source.count else {
                return nil
            }
            return source[index]
        }

        private mutating func consume(prefix: String) -> Bool {
            let chars = Array(prefix)
            guard index + chars.count <= source.count else {
                return false
            }
            for (offset, ch) in chars.enumerated() {
                if source[index + offset] != ch {
                    return false
                }
            }
            index += chars.count
            return true
        }

        private mutating func consume(character: Character) -> Bool {
            guard let ch = peek(), ch == character else {
                return false
            }
            index += 1
            return true
        }

        private func ownerName() -> String {
            ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
        }
    }

    private func parseImportedInlineFunction(
        path: String,
        importedSymbol: SymbolID,
        parameterCount: Int,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) -> KIRFunction? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0002",
                "Unable to read inline KIR artifact: \(path)",
                range: nil
            )
            return nil
        }

        var functionName = interner.intern("__imported_inline_\(importedSymbol.rawValue)")
        var parsedParameterCount = max(0, parameterCount)
        var parsedParameterSymbols: [Int32] = []
        var isSuspend = false
        var bodyLines: [String] = []
        var inBody = false

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if inBody {
                bodyLines.append(line)
                continue
            }
            if line == "body:" {
                inBody = true
                continue
            }
            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separatorIndex])
            let value = String(line[line.index(after: separatorIndex)...])
            switch key {
            case "nameB64":
                if let decoded = decodeBase64String(value) {
                    functionName = interner.intern(decoded)
                }
            case "params":
                parsedParameterCount = max(0, Int(value) ?? parsedParameterCount)
            case "paramSymbols":
                parsedParameterSymbols = parseInlineIntList(value).map(Int32.init)
            case "suspend":
                isSuspend = value == "1" || value == "true"
            default:
                continue
            }
        }

        parsedParameterCount = max(parsedParameterCount, parsedParameterSymbols.count)
        var params: [KIRParameter] = []
        var parameterSymbolMapping: [Int32: SymbolID] = [:]
        for index in 0..<parsedParameterCount {
            let localSymbol = importedInlineParameterSymbol(functionSymbol: importedSymbol, index: index)
            params.append(KIRParameter(symbol: localSymbol, type: types.anyType))
            if index < parsedParameterSymbols.count {
                parameterSymbolMapping[parsedParameterSymbols[index]] = localSymbol
            }
        }

        var body: [KIRInstruction] = []
        body.reserveCapacity(bodyLines.count)
        for line in bodyLines {
            guard let instruction = parseImportedInlineInstruction(
                line: line,
                parameterSymbolMapping: parameterSymbolMapping,
                interner: interner
            ) else {
                continue
            }
            body.append(instruction)
        }
        if body.isEmpty {
            body = [.returnUnit]
        }

        return KIRFunction(
            symbol: importedSymbol,
            name: functionName,
            params: params,
            returnType: types.anyType,
            body: body,
            isSuspend: isSuspend,
            isInline: true
        )
    }

    private func importedInlineParameterSymbol(functionSymbol: SymbolID, index: Int) -> SymbolID {
        let raw = Int32(truncatingIfNeeded: Int64(-200_000) - Int64(functionSymbol.rawValue) * 64 - Int64(index))
        return SymbolID(rawValue: raw)
    }

    private func parseImportedInlineInstruction(
        line: String,
        parameterSymbolMapping: [Int32: SymbolID],
        interner: StringInterner
    ) -> KIRInstruction? {
        let parts = line.split(separator: " ")
        guard let opcode = parts.first else {
            return nil
        }
        let pairs = parseInlineKeyValuePairs(parts.dropFirst())

        switch opcode {
        case "nop":
            return .nop
        case "beginBlock":
            return .beginBlock
        case "endBlock":
            return .endBlock
        case "label":
            guard let raw = pairs["id"], let id = Int32(raw) else { return nil }
            return .label(id)
        case "jump":
            guard let raw = pairs["target"], let target = Int32(raw) else { return nil }
            return .jump(target)
        case "jumpIfEqual":
            guard let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw),
                  let targetRaw = pairs["target"], let target = Int32(targetRaw) else {
                return nil
            }
            return .jumpIfEqual(
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs),
                target: target
            )
        case "const":
            guard let resultRaw = pairs["result"], let result = Int32(resultRaw),
                  let valueToken = pairs["value"],
                  let value = parseImportedInlineExprKind(
                    token: valueToken,
                    parameterSymbolMapping: parameterSymbolMapping,
                    interner: interner
                  ) else {
                return nil
            }
            return .constValue(result: KIRExprID(rawValue: result), value: value)
        case "binary":
            guard let opRaw = pairs["op"], let op = parseBinaryOp(opRaw),
                  let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw) else {
                return nil
            }
            return .binary(
                op: op,
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs),
                result: KIRExprID(rawValue: result)
            )
        case "returnUnit":
            return .returnUnit
        case "returnValue":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw) else {
                return nil
            }
            return .returnValue(KIRExprID(rawValue: value))
        case "returnIfEqual":
            guard let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw) else {
                return nil
            }
            return .returnIfEqual(
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs)
            )
        case "select":
            guard let conditionRaw = pairs["condition"], let condition = Int32(conditionRaw),
                  let thenRaw = pairs["then"], let thenValue = Int32(thenRaw),
                  let elseRaw = pairs["else"], let elseValue = Int32(elseRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw) else {
                return nil
            }
            return .select(
                condition: KIRExprID(rawValue: condition),
                thenValue: KIRExprID(rawValue: thenValue),
                elseValue: KIRExprID(rawValue: elseValue),
                result: KIRExprID(rawValue: result)
            )
        case "call":
            guard let calleeEncoded = pairs["calleeB64"],
                  let calleeName = decodeBase64String(calleeEncoded) else {
                return nil
            }
            let args = parseInlineIntList(pairs["args"] ?? "[]").map { value in
                KIRExprID(rawValue: Int32(truncatingIfNeeded: value))
            }
            let result: KIRExprID?
            if let resultRaw = pairs["result"], resultRaw != "_" {
                result = Int32(resultRaw).map(KIRExprID.init(rawValue:))
            } else {
                result = nil
            }
            let canThrowRaw = pairs["canThrow"] ?? "0"
            let canThrow = canThrowRaw == "1" || canThrowRaw == "true"
            return .call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: args,
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            )
        default:
            return nil
        }
    }

    private func parseImportedInlineExprKind(
        token: String,
        parameterSymbolMapping: [Int32: SymbolID],
        interner: StringInterner
    ) -> KIRExprKind? {
        if token == "unit" {
            return .unit
        }
        if token == "null" {
            return .null
        }
        if token.hasPrefix("int:") {
            let value = String(token.dropFirst("int:".count))
            return Int64(value).map(KIRExprKind.intLiteral)
        }
        if token.hasPrefix("bool:") {
            let value = String(token.dropFirst("bool:".count))
            return .boolLiteral(value == "1" || value == "true")
        }
        if token.hasPrefix("stringB64:") {
            let encoded = String(token.dropFirst("stringB64:".count))
            guard let decoded = decodeBase64String(encoded) else {
                return nil
            }
            return .stringLiteral(interner.intern(decoded))
        }
        if token.hasPrefix("symbol:") {
            let raw = String(token.dropFirst("symbol:".count))
            guard let symbolRaw = Int32(raw) else {
                return nil
            }
            if let mapped = parameterSymbolMapping[symbolRaw] {
                return .symbolRef(mapped)
            }
            return .symbolRef(SymbolID(rawValue: symbolRaw))
        }
        if token.hasPrefix("temp:") {
            let raw = String(token.dropFirst("temp:".count))
            return Int32(raw).map(KIRExprKind.temporary)
        }
        return nil
    }

    private func parseBinaryOp(_ raw: String) -> KIRBinaryOp? {
        switch raw {
        case "add":
            return .add
        case "subtract":
            return .subtract
        case "multiply":
            return .multiply
        case "divide":
            return .divide
        case "equal":
            return .equal
        default:
            return nil
        }
    }

    private func parseInlineKeyValuePairs(_ tokens: ArraySlice<Substring>) -> [String: String] {
        var mapping: [String: String] = [:]
        for token in tokens {
            guard let separatorIndex = token.firstIndex(of: "=") else {
                continue
            }
            let key = String(token[..<separatorIndex])
            let value = String(token[token.index(after: separatorIndex)...])
            mapping[key] = value
        }
        return mapping
    }

    private func parseInlineIntList(_ token: String) -> [Int] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return []
        }
        let inner = trimmed.dropFirst().dropLast()
        if inner.isEmpty {
            return []
        }
        return inner.split(separator: ",").compactMap { Int($0) }
    }

    private func decodeBase64String(_ token: String) -> String? {
        guard let data = Data(base64Encoded: token),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    private func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
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
