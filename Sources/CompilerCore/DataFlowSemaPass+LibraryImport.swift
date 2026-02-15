import Foundation

extension DataFlowSemaPassPhase {
    func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.searchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        for libraryDir in libraryDirs {
            let metadataPath = resolveMetadataPath(libraryDir: libraryDir)
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
                let symbol = symbols.define(
                    kind: record.kind,
                    name: name,
                    fqName: record.fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
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
                if record.kind == .function {
                    let parameterTypes = Array(repeating: types.anyType, count: max(0, record.arity))
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            parameterTypes: parameterTypes,
                            returnType: types.anyType,
                            isSuspend: record.isSuspend
                        ),
                        for: symbol
                    )
                } else if record.kind == .property || record.kind == .field {
                    symbols.setPropertyType(types.anyType, for: symbol)
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
    }

    private struct ImportedLibrarySymbolRecord {
        let kind: SymbolKind
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
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

    private func resolveMetadataPath(libraryDir: String) -> String {
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let metadataRelativePath = object["metadata"] as? String, !metadataRelativePath.isEmpty {
            return URL(fileURLWithPath: libraryDir).appendingPathComponent(metadataRelativePath).path
        }
        return URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path
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
            if kind == .package {
                continue
            }

            var fqName: [InternedString] = []
            var arity = 0
            var isSuspend = false
            var declaredFieldCount: Int? = nil
            var declaredInstanceSizeWords: Int? = nil
            var declaredVtableSize: Int? = nil
            var declaredItableSize: Int? = nil
            var superFQName: [InternedString]? = nil

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
                default:
                    continue
                }
            }

            guard !fqName.isEmpty else {
                continue
            }
            records.append(ImportedLibrarySymbolRecord(
                kind: kind,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName
            ))
        }

        return records
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
