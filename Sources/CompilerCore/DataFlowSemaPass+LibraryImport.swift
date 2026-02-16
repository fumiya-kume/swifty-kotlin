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
                    if record.isInline,
                       !record.mangledName.isEmpty,
                       let inlineDir = manifestInfo.inlineKIRDir {
                        let inlinePath = URL(fileURLWithPath: inlineDir)
                            .appendingPathComponent(record.mangledName + ".kirbin")
                            .path
                        if let inlineFunction = parseImportedInlineFunction(
                            path: inlinePath,
                            importedSymbol: symbol,
                            parameterCount: max(0, record.arity),
                            types: types,
                            interner: interner,
                            diagnostics: diagnostics
                        ) {
                            importedInlineFunctions[symbol] = inlineFunction
                        }
                    }
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
        let mangledName: String
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let isInline: Bool
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
            if kind == .package {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var fqName: [InternedString] = []
            var arity = 0
            var isSuspend = false
            var isInline = false
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
                case "inline":
                    isInline = value == "1" || value == "true"
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
                mangledName: mangledName,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                isInline: isInline,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName
            ))
        }

        return records
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
                canThrow: canThrow
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
