import Foundation

extension DataFlowSemaPhase {
    func parseImportedFieldOffsets(
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

    func parseImportedVTableSlots(
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
                  let arity = Int(components[1])
            else {
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

    func parseImportedITableSlots(
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
                  let slot = Int(entry[entry.index(after: separatorIndex)...])
            else {
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

    func applyImportedNominalLayout(
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
           declaredVTableSize < maxVTableSize
        {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "metadata vtable size mismatch at \(metadataPath) for symbol \(symbol.rawValue)",
                range: nil
            )
        }
        if let declaredITableSize = record.declaredItableSize,
           declaredITableSize >= 0,
           declaredITableSize < maxITableSize
        {
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
                      let signature = symbols.functionSignature(for: symbol.id)
                else {
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
}
